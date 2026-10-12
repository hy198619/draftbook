using System.Text;
using DraftBook.Core;

namespace DraftBook.Core.Tests;

public sealed class DraftRepositoryTests : IDisposable
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), $"DraftBookWindowsTests-{Guid.NewGuid():N}");
    private readonly DateTimeOffset now = new(2026, 10, 12, 1, 2, 3, TimeSpan.Zero);

    public void Dispose()
    {
        try
        {
            Directory.Delete(directory, recursive: true);
        }
        catch (DirectoryNotFoundException)
        {
        }
    }

    [Fact]
    public void SaveAndLoadPreserveComposerDraftsAndLabels()
    {
        var repository = Repository();
        var state = StateWithDraft("持久化");
        state.SetLabelNames(LabelNames("自定义"));

        repository.Save(state.ToSnapshot());
        var loaded = repository.Load();

        Assert.Null(loaded.Warning);
        Assert.Equal("顶部输入", loaded.Snapshot.Composer);
        Assert.Equal("持久化", loaded.Snapshot.Drafts.Single().Content);
        Assert.Equal("自定义", loaded.Snapshot.LabelNames["blue"]);
        Assert.True(File.Exists(repository.FilePath));
    }

    [Fact]
    public void EverySuccessfulOverwriteKeepsPreviousValidSnapshot()
    {
        var repository = Repository();
        repository.Save(StateWithDraft("第一版").ToSnapshot());
        repository.Save(StateWithDraft("第二版").ToSnapshot());

        var previous = SnapshotJson.Deserialize(File.ReadAllBytes(repository.PreviousFilePath));
        Assert.Equal("第一版", previous.Drafts.Single().Content);
        Assert.Equal("第二版", repository.Load().Snapshot.Drafts.Single().Content);
        Assert.Empty(Directory.EnumerateFiles(directory, "*.tmp", SearchOption.AllDirectories));
    }

    [Fact]
    public void CorruptMainFileRecoversNewestValidBackup()
    {
        var repository = Repository();
        repository.Save(StateWithDraft("可恢复").ToSnapshot());
        File.WriteAllText(repository.FilePath, "broken", Encoding.UTF8);

        var loaded = repository.Load();

        Assert.Contains("已从最近的可用副本恢复", loaded.Warning);
        Assert.Equal("可恢复", loaded.Snapshot.Drafts.Single().Content);
    }

    [Fact]
    public void CorruptMainFileUsesPreviousSnapshotWhenAutomaticBackupsAreDisabled()
    {
        var repository = new DraftRepository(new DraftRepositoryOptions(directory, AutomaticBackupsEnabled: false));
        repository.Save(StateWithDraft("可恢复的上一版").ToSnapshot());
        repository.Save(StateWithDraft("最新版").ToSnapshot());
        Assert.True(File.Exists(repository.PreviousFilePath));
        File.WriteAllText(repository.FilePath, "{ broken", Encoding.UTF8);

        var loaded = repository.Load();

        Assert.Equal("可恢复的上一版", loaded.Snapshot.Drafts.Single().Content);
        Assert.NotNull(loaded.Warning);
    }

    [Fact]
    public void CorruptNewestBackupFallsBackToOlderValidBackup()
    {
        var clock = now;
        var repository = new DraftRepository(new DraftRepositoryOptions(directory), () => clock);
        repository.Save(StateWithDraft("较早有效").ToSnapshot());
        clock = now.AddDays(1);
        repository.Save(StateWithDraft("较新有效").ToSnapshot());
        var newest = Directory.EnumerateFiles(repository.BackupDirectory, "*.json").OrderByDescending(path => path).First();
        File.WriteAllText(newest, "broken", Encoding.UTF8);
        File.WriteAllText(repository.FilePath, "broken", Encoding.UTF8);

        var loaded = repository.Load();

        Assert.Equal("较早有效", loaded.Snapshot.Drafts.Single().Content);
    }

    [Fact]
    public void DisabledAutomaticBackupDoesNotCreateBackupDirectory()
    {
        var repository = new DraftRepository(new DraftRepositoryOptions(directory, AutomaticBackupsEnabled: false));
        repository.Save(StateWithDraft("只保存主数据").ToSnapshot());
        Assert.False(Directory.Exists(repository.BackupDirectory));
    }

    [Fact]
    public void RetentionPrunesOnlyAutomaticBackupsAndKeepsRestoreSafetyFiles()
    {
        var clock = now;
        var repository = new DraftRepository(new DraftRepositoryOptions(directory, BackupRetentionCount: 7), () => clock);
        for (var index = 0; index < 10; index++)
        {
            clock = now.AddDays(index);
            repository.Save(StateWithDraft($"版本{index}").ToSnapshot());
        }

        Directory.CreateDirectory(repository.BackupDirectory);
        var safety = Path.Combine(repository.BackupDirectory, "BeforeRestore-20261012-010203.json");
        File.WriteAllText(safety, "safety", Encoding.UTF8);
        repository.Configure(automaticBackupsEnabled: true, retentionCount: 7);

        Assert.Equal(7, Directory.EnumerateFiles(repository.BackupDirectory, "DraftBook-*.json").Count());
        Assert.True(File.Exists(safety));
    }

    [Fact]
    public void RestoreBackupPreservesCurrentMainFileBeforeReplacement()
    {
        var repository = Repository();
        repository.Save(StateWithDraft("恢复前").ToSnapshot());
        var incoming = SnapshotJson.Serialize(StateWithDraft("来自备份").ToSnapshot());

        var restored = repository.RestoreFullBackup(incoming, now);

        Assert.Equal("来自备份", restored.Drafts.Single().Content);
        var safety = Path.Combine(repository.BackupDirectory, "BeforeRestore-20261012-010203.json");
        Assert.True(File.Exists(safety));
        Assert.Equal("恢复前", SnapshotJson.Deserialize(File.ReadAllBytes(safety)).Drafts.Single().Content);
    }

    [Fact]
    public void FutureBackupDoesNotOverwriteCurrentData()
    {
        var repository = Repository();
        repository.Save(StateWithDraft("当前数据").ToSnapshot());
        var before = File.ReadAllBytes(repository.FilePath);
        var future = Encoding.UTF8.GetBytes("{\"schemaVersion\":999,\"drafts\":[]}");

        Assert.Throws<UnsupportedSchemaException>(() => repository.RestoreFullBackup(future, now));
        Assert.Equal(before, File.ReadAllBytes(repository.FilePath));
    }

    [Fact]
    public void FutureMainFileDoesNotFallBackToAnOlderBackup()
    {
        var repository = Repository();
        repository.Save(StateWithDraft("旧备份").ToSnapshot());
        var future = Encoding.UTF8.GetBytes("""
        { "schemaVersion": 6, "composer": "新版本状态", "drafts": [], "labelNames": {} }
        """);
        File.WriteAllBytes(repository.FilePath, future);

        Assert.Throws<UnsupportedSchemaException>(() => repository.Load());
        Assert.Equal(future, File.ReadAllBytes(repository.FilePath));
    }

    [Fact]
    public async Task AutoSaveDebouncesAndFlushPersistsLatestText()
    {
        var repository = Repository();
        var state = StateWithDraft("初始");
        await using var autosave = new AutoSaveCoordinator(state, repository, TimeSpan.FromMilliseconds(30));
        var draft = state.AllDrafts.Single();

        for (var index = 0; index < 20; index++)
        {
            state.UpdateContent(draft.Id, $"快速输入{index}", now.AddSeconds(index));
        }
        await autosave.FlushAsync();

        Assert.Equal("快速输入19", repository.Load().Snapshot.Drafts.Single().Content);
    }

    [Fact]
    public async Task SaveFailureIsReportedWithoutChangingInMemoryText()
    {
        var fileInsteadOfDirectory = Path.Combine(directory, "not-a-directory");
        Directory.CreateDirectory(directory);
        File.WriteAllText(fileInsteadOfDirectory, "x", Encoding.UTF8);
        var repository = new DraftRepository(new DraftRepositoryOptions(fileInsteadOfDirectory));
        var state = StateWithDraft("仍在内存");
        await using var autosave = new AutoSaveCoordinator(state, repository, TimeSpan.Zero);
        var errors = new List<string?>();
        autosave.SaveErrorChanged += (_, error) => errors.Add(error);

        state.Composer = "不能写入但不能丢";
        await autosave.FlushAsync();

        Assert.Contains(errors, error => error?.StartsWith("自动保存失败：", StringComparison.Ordinal) == true);
        Assert.StartsWith("自动保存失败：", autosave.LastError, StringComparison.Ordinal);
        Assert.Equal("不能写入但不能丢", state.Composer);
    }

    [Fact]
    public async Task SuccessfulFlushClearsEarlierSaveError()
    {
        var badDirectory = Path.Combine(directory, "file-instead-of-directory");
        Directory.CreateDirectory(directory);
        File.WriteAllText(badDirectory, "x", Encoding.UTF8);
        var state = StateWithDraft("保留");
        await using var failing = new AutoSaveCoordinator(
            state, new DraftRepository(new DraftRepositoryOptions(badDirectory)), TimeSpan.Zero);
        state.Composer = "先失败";
        await failing.FlushAsync();
        Assert.NotNull(failing.LastError);

        var working = new AutoSaveCoordinator(state, Repository(), TimeSpan.Zero);
        await using (working)
        {
            await working.FlushAsync();
            Assert.Null(working.LastError);
        }
    }

    private DraftRepository Repository() => new(new DraftRepositoryOptions(directory), () => now);

    private DraftBookState StateWithDraft(string content)
    {
        var state = new DraftBookState(timeZone: TimeZoneInfo.Utc) { Composer = "顶部输入" };
        state.Composer = content;
        state.SealComposer(now);
        state.Composer = "顶部输入";
        return state;
    }

    private static IReadOnlyDictionary<DraftColor, string> LabelNames(string blue) => new Dictionary<DraftColor, string>
    {
        [DraftColor.Yellow] = "分类1",
        [DraftColor.Blue] = blue,
        [DraftColor.Purple] = "分类3",
        [DraftColor.Green] = "分类4",
        [DraftColor.Red] = "分类5",
    };
}
