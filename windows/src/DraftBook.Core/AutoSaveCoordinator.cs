namespace DraftBook.Core;

public sealed class AutoSaveCoordinator : IAsyncDisposable
{
    private readonly DraftBookState state;
    private readonly DraftRepository repository;
    private readonly TimeSpan debounce;
    private readonly SemaphoreSlim saveGate = new(1, 1);
    private readonly object synchronization = new();
    private readonly HashSet<Task> backgroundTasks = [];
    private DraftBookSnapshot latestSnapshot;
    private CancellationTokenSource? pendingDelay;
    private bool disposed;

    public AutoSaveCoordinator(DraftBookState state, DraftRepository repository, TimeSpan? debounce = null)
    {
        this.state = state;
        this.repository = repository;
        this.debounce = debounce ?? TimeSpan.FromMilliseconds(280);
        // DraftBookState is owned by the UI thread. Capture snapshots on the
        // caller's thread and let background tasks write only detached copies.
        latestSnapshot = state.ToSnapshot();
        state.Changed += StateChanged;
    }

    public event EventHandler<string?>? SaveErrorChanged;

    public string? LastError { get; private set; }

    public Task FlushAsync(CancellationToken cancellationToken = default)
    {
        CancelPendingDelay();
        return SaveLatestAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        state.Changed -= StateChanged;
        CancelPendingDelay();
        Task[] tasks;
        lock (synchronization)
        {
            tasks = [.. backgroundTasks];
        }
        await Task.WhenAll(tasks).ConfigureAwait(false);
        await SaveLatestAsync(CancellationToken.None).ConfigureAwait(false);
        saveGate.Dispose();
        lock (synchronization)
        {
            pendingDelay?.Dispose();
            pendingDelay = null;
        }
    }

    private void StateChanged(object? sender, EventArgs eventArgs)
    {
        if (disposed)
        {
            return;
        }

        CancellationTokenSource cancellation;
        lock (synchronization)
        {
            latestSnapshot = state.ToSnapshot();
            pendingDelay?.Cancel();
            pendingDelay?.Dispose();
            pendingDelay = new CancellationTokenSource();
            cancellation = pendingDelay;
        }

        var task = SaveAfterDelayAsync(cancellation.Token);
        lock (synchronization)
        {
            backgroundTasks.Add(task);
        }
        _ = task.ContinueWith(completed =>
        {
            _ = completed.Exception;
            lock (synchronization)
            {
                backgroundTasks.Remove(completed);
            }
        }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }

    private async Task SaveAfterDelayAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(debounce, cancellationToken).ConfigureAwait(false);
            await SaveLatestAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // A newer edit superseded this save.
        }
    }

    private async Task SaveLatestAsync(CancellationToken cancellationToken)
    {
        await saveGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            DraftBookSnapshot snapshot;
            lock (synchronization)
            {
                // Read only after earlier writes finish. Otherwise an older save task can
                // acquire the gate after a newer one and overwrite the newest snapshot.
                snapshot = latestSnapshot;
            }
            await Task.Run(() => repository.Save(snapshot), cancellationToken).ConfigureAwait(false);
            LastError = null;
            SaveErrorChanged?.Invoke(this, null);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or DraftBookDataException)
        {
            LastError = $"自动保存失败：{exception.Message}";
            SaveErrorChanged?.Invoke(this, LastError);
        }
        finally
        {
            saveGate.Release();
        }
    }

    private void CancelPendingDelay()
    {
        lock (synchronization)
        {
            pendingDelay?.Cancel();
            pendingDelay?.Dispose();
            pendingDelay = null;
        }
    }
}
