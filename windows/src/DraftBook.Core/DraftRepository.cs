namespace DraftBook.Core;

public sealed record DraftRepositoryOptions(
    string DataDirectory,
    bool AutomaticBackupsEnabled = true,
    int BackupRetentionCount = 14);

public sealed record DraftLoadResult(DraftBookSnapshot Snapshot, string? Warning = null);

public sealed class DraftRepository
{
    private readonly Func<DateTimeOffset> clock;

    public DraftRepository(DraftRepositoryOptions options, Func<DateTimeOffset>? clock = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(options.DataDirectory);
        Options = options with { BackupRetentionCount = ValidRetention(options.BackupRetentionCount) };
        this.clock = clock ?? (() => DateTimeOffset.Now);
        FilePath = Path.Combine(Options.DataDirectory, "drafts.json");
        PreviousFilePath = Path.Combine(Options.DataDirectory, "drafts.previous.json");
        BackupDirectory = Path.Combine(Options.DataDirectory, "Backups");
    }

    public DraftRepositoryOptions Options { get; private set; }
    public string FilePath { get; }
    public string PreviousFilePath { get; }
    public string BackupDirectory { get; }

    public void Configure(bool automaticBackupsEnabled, int retentionCount)
    {
        Options = Options with
        {
            AutomaticBackupsEnabled = automaticBackupsEnabled,
            BackupRetentionCount = ValidRetention(retentionCount),
        };
        if (automaticBackupsEnabled)
        {
            PruneBackups();
        }
    }

    public DraftLoadResult Load()
    {
        if (!File.Exists(FilePath))
        {
            return new DraftLoadResult(new DraftBookSnapshot
            {
                SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion,
            });
        }

        try
        {
            var data = File.ReadAllBytes(FilePath);
            var snapshot = SnapshotJson.Deserialize(data);
            CreateDailyBackupIfNeeded(data);
            return new DraftLoadResult(snapshot);
        }
        catch (UnsupportedSchemaException)
        {
            // A newer DraftBook may have written fields this version cannot preserve.
            // Falling back and later auto-saving would silently downgrade that data.
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or DraftBookDataException)
        {
            var recovered = RestoreLatestValidBackup();
            if (recovered is not null)
            {
                return new DraftLoadResult(recovered, "主数据文件异常，已从最近的可用副本恢复。请先导出完整备份确认内容。");
            }

            throw new DraftBookDataException($"无法读取本地草稿：{exception.Message}", exception);
        }
    }

    public void Save(DraftBookSnapshot snapshot)
    {
        var data = SnapshotJson.Serialize(snapshot);
        Directory.CreateDirectory(Options.DataDirectory);
        AtomicWrite(FilePath, data, preservePrevious: true);
        CreateDailyBackupIfNeeded(data);
    }

    public byte[] FullBackup(DraftBookSnapshot snapshot) => SnapshotJson.Serialize(snapshot);

    public DraftBookSnapshot RestoreFullBackup(ReadOnlySpan<byte> data, DateTimeOffset now)
    {
        var snapshot = SnapshotJson.Deserialize(data);
        Directory.CreateDirectory(BackupDirectory);
        if (File.Exists(FilePath))
        {
            var safetyName = $"BeforeRestore-{now.UtcDateTime:yyyyMMdd-HHmmss}.json";
            AtomicWrite(Path.Combine(BackupDirectory, safetyName), File.ReadAllBytes(FilePath), preservePrevious: false);
        }

        Save(snapshot);
        return snapshot;
    }

    public static string DefaultDataDirectory()
    {
        var overridePath = Environment.GetEnvironmentVariable("DRAFTBOOK_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            return Path.GetFullPath(overridePath);
        }

        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local, "DraftBook");
    }

    private void CreateDailyBackupIfNeeded(byte[] data)
    {
        if (!Options.AutomaticBackupsEnabled)
        {
            return;
        }

        Directory.CreateDirectory(BackupDirectory);
        var destination = Path.Combine(BackupDirectory, $"DraftBook-{clock():yyyy-MM-dd}.json");
        if (!File.Exists(destination))
        {
            AtomicWrite(destination, data, preservePrevious: false);
            PruneBackups();
        }
    }

    private DraftBookSnapshot? RestoreLatestValidBackup()
    {
        IEnumerable<string> candidates = File.Exists(PreviousFilePath) ? [PreviousFilePath] : [];
        if (Directory.Exists(BackupDirectory))
        {
            candidates = candidates.Concat(Directory.EnumerateFiles(BackupDirectory, "*.json")
                .OrderByDescending(File.GetLastWriteTimeUtc));
        }

        foreach (var path in candidates)
        {
            try
            {
                return SnapshotJson.Deserialize(File.ReadAllBytes(path));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or DraftBookDataException)
            {
                // Try the next backup. A broken backup must not hide an older valid one.
            }
        }

        return null;
    }

    private void PruneBackups()
    {
        if (!Directory.Exists(BackupDirectory))
        {
            return;
        }

        var automatic = Directory.EnumerateFiles(BackupDirectory, "DraftBook-*.json")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Skip(Options.BackupRetentionCount);
        foreach (var path in automatic)
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
                // Retention cleanup is best effort and must never prevent saving.
            }
            catch (UnauthorizedAccessException)
            {
                // Same rationale as above.
            }
        }
    }

    private void AtomicWrite(string destination, byte[] data, bool preservePrevious)
    {
        var directory = Path.GetDirectoryName(destination)
            ?? throw new InvalidOperationException("保存路径缺少目录。");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".{Path.GetFileName(destination)}.{Guid.NewGuid():N}.tmp");

        try
        {
            using (var stream = new FileStream(
                       temporary,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 16 * 1024,
                       FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }

            if (preservePrevious && File.Exists(destination))
            {
                File.Copy(destination, PreviousFilePath, overwrite: true);
            }

            File.Move(temporary, destination, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                try
                {
                    File.Delete(temporary);
                }
                catch (IOException)
                {
                    // A stale temp file is harmless and can be diagnosed separately.
                }
            }
        }
    }

    private static int ValidRetention(int value) => value is 7 or 14 or 30 ? value : 14;
}
