using DraftBook.Core;

namespace DraftBook.Core.Tests;

public sealed class DraftBookStateTests
{
    private static readonly TimeZoneInfo Utc = TimeZoneInfo.Utc;
    private static readonly DateTimeOffset Epoch = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void SealComposerCreatesDraftAndClearsComposer()
    {
        var state = NewState();
        state.Composer = "第一条\n保留换行";

        var draft = state.SealComposer(Epoch);

        Assert.NotNull(draft);
        Assert.Equal("第一条\n保留换行", draft.Content);
        Assert.Equal(Epoch, draft.CreatedAt);
        Assert.Equal(Epoch.AddDays(7), draft.ReviewAt);
        Assert.Equal(string.Empty, state.Composer);
        Assert.Same(draft, state.OrderedDrafts.Single());
    }

    [Theory]
    [InlineData("")]
    [InlineData("   \n\t")]
    public void EmptyComposerDoesNotCreateDraft(string content)
    {
        var state = NewState();
        state.Composer = content;
        Assert.Null(state.SealComposer(Epoch));
        Assert.Empty(state.AllDrafts);
    }

    [Fact]
    public void PinnedDraftsComeFirstWithoutChangingCreationOrder()
    {
        var state = NewState();
        var older = Seal(state, "旧", Epoch);
        var newer = Seal(state, "新", Epoch.AddHours(1));

        state.TogglePinned(older.Id, Epoch.AddHours(2));

        Assert.Equal([older.Id, newer.Id], state.OrderedDrafts.Select(draft => draft.Id));
        Assert.Null(state.Find(older.Id)!.ReviewAt);
    }

    [Fact]
    public void EditingRestartsCleanupButDoesNotResetCreationAge()
    {
        var state = NewState();
        var draft = Seal(state, "旧正文", Epoch);
        var editedAt = Epoch.AddDays(10);

        state.UpdateContent(draft.Id, "新正文", editedAt);

        var edited = state.Find(draft.Id)!;
        Assert.Equal(Epoch, edited.CreatedAt);
        Assert.Equal(editedAt, edited.UpdatedAt);
        Assert.Equal(editedAt.AddDays(7), edited.ReviewAt);
        Assert.Equal(TagAgeStage.SevenDays, DraftTiming.TagAgeStage(edited.CreatedAt, editedAt));
    }

    [Theory]
    [InlineData(0, TagAgeStage.Fresh, 1.0)]
    [InlineData(4.99, TagAgeStage.Fresh, 1.0)]
    [InlineData(5, TagAgeStage.FiveDays, 0.86)]
    [InlineData(7, TagAgeStage.SevenDays, 0.73)]
    [InlineData(30, TagAgeStage.ThirtyDays, 0.60)]
    public void TagFadeUsesCreationAge(double days, TagAgeStage expectedStage, double saturation)
    {
        var reference = Epoch.AddSeconds(days * 86_400);
        Assert.Equal(expectedStage, DraftTiming.TagAgeStage(Epoch, reference));
        Assert.Equal(saturation, DraftTiming.TagSaturation(Epoch, reference), precision: 5);
    }

    [Fact]
    public void DueDraftsExcludePinnedAndPostponedDrafts()
    {
        var state = NewState();
        var due = Seal(state, "到期", Epoch);
        var pinned = Seal(state, "固定", Epoch);
        state.TogglePinned(pinned.Id, Epoch);
        var reference = Epoch.AddDays(8);

        Assert.Equal([due.Id], state.DueDrafts(reference).Select(draft => draft.Id));
        state.Postpone(due.Id, 3, reference);
        Assert.Empty(state.DueDrafts(reference));
        Assert.Equal(reference.AddDays(3), state.Find(due.Id)!.ReviewAt);
    }

    [Fact]
    public void ArchiveTrashAndRestorePreserveOriginalArchiveState()
    {
        var state = NewState();
        var draft = Seal(state, "第一行标题\n正文", Epoch);
        state.Archive(draft.Id, null, DraftColor.Blue, Epoch.AddDays(1));
        var archived = state.Find(draft.Id)!;
        Assert.Equal(DraftState.Archived, archived.State);
        Assert.Equal("第一行标题", archived.Title);
        Assert.Equal(DraftColor.Blue, archived.Color);

        state.MoveToTrash(draft.Id, Epoch.AddDays(2));
        state.RestoreFromTrash(draft.Id, Epoch.AddDays(3));

        var restored = state.Find(draft.Id)!;
        Assert.Equal(DraftState.Archived, restored.State);
        Assert.Null(restored.DeletedAt);
        Assert.Equal(Epoch.AddDays(1), restored.ArchivedAt);
    }

    [Fact]
    public void DeleteSnapshotCanBeUndoneExactly()
    {
        var state = NewState();
        var draft = Seal(state, "可撤销", Epoch);
        state.TogglePinned(draft.Id, Epoch);
        var snapshot = state.MoveToTrash(draft.Id, Epoch.AddDays(1));
        Assert.NotNull(snapshot);

        state.RestoreSnapshot(snapshot!);

        var restored = state.Find(draft.Id)!;
        Assert.Equal(DraftState.Active, restored.State);
        Assert.True(restored.Pinned);
        Assert.Null(restored.DeletedAt);
    }

    [Fact]
    public void PermanentDeleteOnlyRemovesTrash()
    {
        var state = NewState();
        var active = Seal(state, "活跃", Epoch);
        state.DeletePermanently(active.Id);
        Assert.NotNull(state.Find(active.Id));

        state.MoveToTrash(active.Id, Epoch);
        state.DeletePermanently(active.Id);
        Assert.Null(state.Find(active.Id));
    }

    [Fact]
    public void ArchivedBodyCanChangeWithoutRestartingCleanup()
    {
        var state = NewState();
        var draft = Seal(state, "旧", Epoch);
        state.Archive(draft.Id, "名称", null, Epoch.AddDays(1));

        state.UpdateContent(draft.Id, "新", Epoch.AddDays(2));
        state.RenameArchived(draft.Id, "新名称");

        var archived = state.Find(draft.Id)!;
        Assert.Equal("新", archived.Content);
        Assert.Equal("新名称", archived.Title);
        Assert.Null(archived.ReviewAt);
        Assert.Equal(DraftState.Archived, archived.State);
    }

    [Fact]
    public void SearchCombinesTitleBodyAndColor()
    {
        var state = NewState();
        var blue = Seal(state, "苹果正文", Epoch);
        state.SetColor(blue.Id, DraftColor.Blue);
        var red = Seal(state, "其他正文", Epoch.AddMinutes(1));
        state.SetColor(red.Id, DraftColor.Red);
        state.Archive(red.Id, "苹果标题", null, Epoch.AddMinutes(2));

        Assert.Equal([blue.Id], state.Drafts(DraftState.Active, "苹果", DraftColor.Blue).Select(draft => draft.Id));
        Assert.Equal([red.Id], state.Drafts(DraftState.Archived, "苹果", DraftColor.Red).Select(draft => draft.Id));
        Assert.Empty(state.Drafts(DraftState.Active, "苹果", DraftColor.Red));
    }

    [Fact]
    public void LabelNamesValidateUnicodeLengthAndDuplicatesBeforeMutation()
    {
        var state = NewState();
        state.SetLabelNames(Names((DraftColor.Blue, "内容"), (DraftColor.Red, "重要")));
        Assert.Equal("内容", state.LabelName(DraftColor.Blue));
        Assert.Equal("未分类", state.LabelName(DraftColor.Gray));

        var duplicate = Names((DraftColor.Yellow, "Résumé"), (DraftColor.Blue, "resume"));
        var exception = Assert.Throws<DraftBookValidationException>(() => state.SetLabelNames(duplicate));
        Assert.Contains("已用于其他标签", exception.Message);
        Assert.Equal("内容", state.LabelName(DraftColor.Blue));

        var tooLong = Names((DraftColor.Blue, string.Concat(Enumerable.Repeat("📝", 13))));
        Assert.Throws<DraftBookValidationException>(() => state.SetLabelNames(tooLong));
    }

    [Fact]
    public void ExportsExcludeTrashAndSamples()
    {
        var state = NewState();
        var kept = Seal(state, "保留", Epoch);
        var trash = Seal(state, "删除", Epoch.AddMinutes(1));
        state.MoveToTrash(trash.Id, Epoch.AddMinutes(2));
        state.InstallSampleDrafts(Epoch.AddDays(1));

        Assert.Contains("保留", state.ExportPlainText());
        Assert.DoesNotContain("删除", state.ExportPlainText());
        Assert.DoesNotContain("示例", state.ExportPlainText());
        Assert.Contains("<!--", state.ExportMarkdown());
        Assert.NotNull(state.Find(kept.Id));
    }

    [Fact]
    public void SamplesCoverAllStatesAndRemovalKeepsRealDrafts()
    {
        var state = NewState();
        var real = Seal(state, "真实但仅存在于单元测试的数据", Epoch);
        state.InstallSampleDrafts(Epoch);

        Assert.Contains(state.AllDrafts, draft => draft.IsSample && draft.State == DraftState.Active);
        Assert.Contains(state.AllDrafts, draft => draft.IsSample && draft.State == DraftState.Archived);
        Assert.Contains(state.AllDrafts, draft => draft.IsSample && draft.State == DraftState.Trash);

        state.RemoveSampleDrafts();
        Assert.Single(state.AllDrafts);
        Assert.Equal(real.Id, state.AllDrafts.Single().Id);
    }

    [Fact]
    public void SuggestedTitleUsesTwentyUnicodeTextElements()
    {
        var title = string.Concat(Enumerable.Repeat("📝", 21));
        var draft = new Draft { Content = $"\n{title}\n正文" };
        Assert.Equal(20, UnicodeText.Length(draft.SuggestedTitle));
        Assert.DoesNotContain('\uFFFD', draft.SuggestedTitle);
    }

    [Fact]
    public void CleanupDescriptionsMatchCalendarDays()
    {
        var now = new DateTimeOffset(2026, 1, 1, 23, 30, 0, TimeSpan.Zero);
        Assert.Equal("已固定，不进入清理台", DraftTiming.CleanupDescription(null, true, now, Utc));
        Assert.Equal("没有清理计划", DraftTiming.CleanupDescription(null, false, now, Utc));
        Assert.Equal("明天进入清理台", DraftTiming.CleanupDescription(now.AddHours(1), false, now, Utc));
        Assert.Equal("已进入清理台", DraftTiming.CleanupDescription(now, false, now, Utc));
    }

    [Fact]
    public void RestoreFromArchiveReturnsToActiveAndRestartsReviewClock()
    {
        var state = NewState();
        var draft = Seal(state, "恢复存档", Epoch);
        state.Archive(draft.Id, "存档标题", DraftColor.Green, Epoch.AddDays(1));

        state.RestoreFromArchive(draft.Id, Epoch.AddDays(2));

        var restored = state.Find(draft.Id)!;
        Assert.Equal(DraftState.Active, restored.State);
        Assert.Null(restored.ArchivedAt);
        Assert.Equal(Epoch.AddDays(9), restored.ReviewAt);
        Assert.Equal(DraftColor.Green, restored.Color);
    }

    [Fact]
    public void RestoreActiveTrashRestartsReviewAndTrashSortsNewestFirst()
    {
        var state = NewState();
        var first = Seal(state, "先删", Epoch);
        var second = Seal(state, "后删", Epoch.AddMinutes(1));
        state.MoveToTrash(first.Id, Epoch.AddHours(1));
        state.MoveToTrash(second.Id, Epoch.AddHours(2));
        Assert.Equal(new[] { second.Id, first.Id }, state.TrashedDrafts.Select(draft => draft.Id));

        state.RestoreFromTrash(first.Id, Epoch.AddDays(3));
        Assert.Equal(DraftState.Active, state.Find(first.Id)!.State);
        Assert.Equal(Epoch.AddDays(10), state.Find(first.Id)!.ReviewAt);
    }

    [Fact]
    public void CopyMarkdownColorAndReviewSettingsMutateOnlyExpectedFields()
    {
        var state = NewState();
        var draft = Seal(state, "**原文**", Epoch);
        state.ToggleMarkdown(draft.Id);
        state.SetColor(draft.Id, DraftColor.Red);
        state.MarkCopied(draft.Id, Epoch.AddMinutes(1));
        state.ConfigureReviewDays(14);

        var changed = state.Find(draft.Id)!;
        Assert.True(changed.MarkdownEnabled);
        Assert.Equal(DraftColor.Red, changed.Color);
        Assert.Equal(Epoch.AddMinutes(1), changed.LastCopiedAt);
        Assert.Equal(14, state.DefaultReviewDays);
        Assert.Equal(Epoch.AddDays(7), changed.ReviewAt);
    }

    [Fact]
    public void ReplaceWithSnapshotReplacesEveryPersistedCollection()
    {
        var state = NewState();
        Seal(state, "会被替换", Epoch);
        var replacement = new DraftBookSnapshot
        {
            SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion,
            Composer = "恢复的输入区",
            Drafts =
            [
                new Draft { Content = "恢复的草稿", CreatedAt = Epoch, UpdatedAt = Epoch },
            ],
            LabelNames = new Dictionary<string, string> { ["blue"] = "备份分类" },
        };

        state.ReplaceWithSnapshot(replacement);

        Assert.Equal("恢复的输入区", state.Composer);
        Assert.Single(state.AllDrafts);
        Assert.Equal("恢复的草稿", state.AllDrafts.Single().Content);
        Assert.Equal("备份分类", state.LabelName(DraftColor.Blue));
    }

    [Fact]
    public void InvalidOrMissingMutationsDoNotChangeState()
    {
        var state = NewState();
        var draft = Seal(state, "保留", Epoch);
        var missing = Guid.NewGuid();
        state.Postpone(draft.Id, 0, Epoch);
        state.RenameArchived(draft.Id, "不应改名");
        state.RestoreSnapshot(new Draft { Id = missing, Content = "x" });
        state.TogglePinned(missing, Epoch);

        Assert.Equal("保留", state.Find(draft.Id)!.Content);
        Assert.Null(state.Find(draft.Id)!.Title);
        Assert.Equal(Epoch.AddDays(7), state.Find(draft.Id)!.ReviewAt);
        Assert.Null(state.Find(missing));
    }

    private static DraftBookState NewState() => new(defaultReviewDays: 7, timeZone: Utc);

    private static Draft Seal(DraftBookState state, string content, DateTimeOffset now)
    {
        state.Composer = content;
        return state.SealComposer(now)!;
    }

    private static IReadOnlyDictionary<DraftColor, string> Names(params (DraftColor Color, string Name)[] overrides)
    {
        var names = Enum.GetValues<DraftColor>()
            .Where(color => color != DraftColor.Gray)
            .ToDictionary(color => color, color => color.DefaultLabelName());
        foreach (var pair in overrides)
        {
            names[pair.Color] = pair.Name;
        }
        return names;
    }
}
