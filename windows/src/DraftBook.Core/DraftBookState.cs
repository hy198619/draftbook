using System.Collections.ObjectModel;
using System.Globalization;

namespace DraftBook.Core;

public sealed class DraftBookState
{
    private readonly List<Draft> drafts;
    private readonly Dictionary<string, string> labelNames;
    private string composer;

    public DraftBookState(
        DraftBookSnapshot? snapshot = null,
        int defaultReviewDays = 7,
        TimeZoneInfo? timeZone = null,
        DateTimeOffset? migrationReferenceDate = null)
    {
        DefaultReviewDays = ValidReviewDays(defaultReviewDays);
        TimeZone = timeZone ?? TimeZoneInfo.Local;
        snapshot ??= new DraftBookSnapshot { SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion };
        composer = snapshot.Composer ?? string.Empty;
        drafts = snapshot.Drafts?.Select(draft => draft.Clone()).ToList() ?? [];
        labelNames = snapshot.LabelNames is null
            ? []
            : new Dictionary<string, string>(snapshot.LabelNames, StringComparer.Ordinal);

        if (snapshot.SchemaVersion < 3)
        {
            MigrateLifecycle(migrationReferenceDate ?? DateTimeOffset.Now);
        }
    }

    public event EventHandler? Changed;

    public int DefaultReviewDays { get; private set; }
    public TimeZoneInfo TimeZone { get; }

    public string Composer
    {
        get => composer;
        set
        {
            value ??= string.Empty;
            if (composer == value)
            {
                return;
            }

            composer = value;
            OnChanged();
        }
    }

    public ReadOnlyCollection<Draft> AllDrafts => drafts.AsReadOnly();

    public IReadOnlyList<Draft> OrderedDrafts => drafts
        .Where(draft => draft.State == DraftState.Active)
        .OrderByDescending(draft => draft.Pinned)
        .ThenByDescending(draft => draft.CreatedAt)
        .ToList();

    public IReadOnlyList<Draft> ArchivedDrafts => drafts
        .Where(draft => draft.State == DraftState.Archived)
        .OrderByDescending(draft => draft.ArchivedAt ?? draft.UpdatedAt)
        .ToList();

    public IReadOnlyList<Draft> TrashedDrafts => drafts
        .Where(draft => draft.State == DraftState.Trash)
        .OrderByDescending(draft => draft.DeletedAt ?? DateTimeOffset.MinValue)
        .ToList();

    public bool HasSampleDrafts => drafts.Any(draft => draft.IsSample);

    public Draft? SealComposer(DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(composer))
        {
            return null;
        }

        var draft = new Draft
        {
            Content = composer,
            CreatedAt = now,
            UpdatedAt = now,
            ReviewIntervalDays = DefaultReviewDays,
            ReviewAt = DraftTiming.AddCalendarDays(now, DefaultReviewDays, TimeZone),
        };
        drafts.Insert(0, draft);
        composer = string.Empty;
        OnChanged();
        return draft;
    }

    public Draft? Find(Guid id) => drafts.FirstOrDefault(draft => draft.Id == id);

    public void UpdateContent(Guid id, string content, DateTimeOffset now)
    {
        Mutate(id, draft =>
        {
            draft.Content = content ?? string.Empty;
            draft.UpdatedAt = now;
            if (draft.State == DraftState.Active && !draft.Pinned && draft.ReviewIntervalDays is int days)
            {
                draft.ReviewAt = DraftTiming.AddCalendarDays(now, days, TimeZone);
            }
        });
    }

    public void ToggleMarkdown(Guid id) => Mutate(id, draft => draft.MarkdownEnabled = !draft.MarkdownEnabled);

    public void SetColor(Guid id, DraftColor color) => Mutate(id, draft => draft.Color = color);

    public string LabelName(DraftColor color)
    {
        if (color == DraftColor.Gray)
        {
            return color.DefaultLabelName();
        }

        return labelNames.GetValueOrDefault(color.SerializedName(), color.DefaultLabelName());
    }

    public void SetLabelNames(IReadOnlyDictionary<DraftColor, string> names)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var used = new HashSet<string>(StringComparer.Ordinal)
        {
            UnicodeText.FoldForComparison(DraftColor.Gray.DefaultLabelName()),
        };

        foreach (var color in Enum.GetValues<DraftColor>().Where(color => color != DraftColor.Gray))
        {
            var input = names.GetValueOrDefault(color)?.Trim() ?? string.Empty;
            var name = input.Length == 0 ? color.DefaultLabelName() : input;
            if (UnicodeText.Length(name) > 12)
            {
                throw new DraftBookValidationException("标签名称最多 12 个字。");
            }

            if (!used.Add(UnicodeText.FoldForComparison(name)))
            {
                throw new DraftBookValidationException($"“{name}”已用于其他标签，请换一个名称。");
            }

            result[color.SerializedName()] = name;
        }

        labelNames.Clear();
        foreach (var pair in result)
        {
            labelNames[pair.Key] = pair.Value;
        }

        OnChanged();
    }

    public void ConfigureReviewDays(int days)
    {
        DefaultReviewDays = ValidReviewDays(days);
        OnChanged();
    }

    public void TogglePinned(Guid id, DateTimeOffset now)
    {
        Mutate(id, draft =>
        {
            draft.Pinned = !draft.Pinned;
            if (draft.Pinned)
            {
                draft.ReviewIntervalDays = null;
                draft.ReviewAt = null;
            }
            else
            {
                draft.ReviewIntervalDays = DefaultReviewDays;
                draft.ReviewAt = DraftTiming.AddCalendarDays(now, DefaultReviewDays, TimeZone);
            }
        });
    }

    public void MarkCopied(Guid id, DateTimeOffset now) => Mutate(id, draft => draft.LastCopiedAt = now);

    public Draft? MoveToTrash(Guid id, DateTimeOffset now)
    {
        var original = Find(id)?.Clone();
        Mutate(id, draft =>
        {
            draft.State = DraftState.Trash;
            draft.DeletedAt = now;
            draft.Pinned = false;
            draft.ReviewAt = null;
        });
        return original;
    }

    public void RestoreSnapshot(Draft snapshot)
    {
        var index = drafts.FindIndex(draft => draft.Id == snapshot.Id);
        if (index < 0)
        {
            return;
        }

        drafts[index] = snapshot.Clone();
        OnChanged();
    }

    public void RestoreFromTrash(Guid id, DateTimeOffset now)
    {
        Mutate(id, draft =>
        {
            draft.DeletedAt = null;
            if (draft.ArchivedAt is not null)
            {
                draft.State = DraftState.Archived;
                draft.ReviewAt = null;
            }
            else
            {
                draft.State = DraftState.Active;
                draft.UpdatedAt = now;
                draft.ReviewIntervalDays = DefaultReviewDays;
                draft.ReviewAt = DraftTiming.AddCalendarDays(now, DefaultReviewDays, TimeZone);
            }
        });
    }

    public void DeletePermanently(Guid id)
    {
        var removed = drafts.RemoveAll(draft => draft.Id == id && draft.State == DraftState.Trash);
        if (removed > 0)
        {
            OnChanged();
        }
    }

    public void Postpone(Guid id, int days, DateTimeOffset now)
    {
        if (days <= 0)
        {
            return;
        }

        Mutate(id, draft =>
        {
            draft.State = DraftState.Active;
            draft.ReviewIntervalDays = days;
            draft.ReviewAt = DraftTiming.AddCalendarDays(now, days, TimeZone);
        });
    }

    public void Archive(Guid id, string? title, DraftColor? color, DateTimeOffset now)
    {
        Mutate(id, draft =>
        {
            draft.Title = string.IsNullOrWhiteSpace(title) ? draft.SuggestedTitle : title.Trim();
            if (color is not null)
            {
                draft.Color = color.Value;
            }

            draft.State = DraftState.Archived;
            draft.ArchivedAt = now;
            draft.ReviewAt = null;
            draft.Pinned = false;
        });
    }

    public void RenameArchived(Guid id, string title)
    {
        if (Find(id)?.State != DraftState.Archived)
        {
            return;
        }

        Mutate(id, draft => draft.Title = string.IsNullOrWhiteSpace(title) ? draft.SuggestedTitle : title.Trim());
    }

    public void RestoreFromArchive(Guid id, DateTimeOffset now)
    {
        Mutate(id, draft =>
        {
            draft.State = DraftState.Active;
            draft.ArchivedAt = null;
            draft.UpdatedAt = now;
            draft.ReviewIntervalDays = DefaultReviewDays;
            draft.ReviewAt = DraftTiming.AddCalendarDays(now, DefaultReviewDays, TimeZone);
        });
    }

    public IReadOnlyList<Draft> DueDrafts(DateTimeOffset now, string query = "", DraftColor? color = null) =>
        Filter(OrderedDrafts.Where(draft => !draft.Pinned && draft.ReviewAt <= now), query, color);

    public IReadOnlyList<Draft> Drafts(DraftState state, string query = "", DraftColor? color = null)
    {
        IEnumerable<Draft> source = state switch
        {
            DraftState.Active => OrderedDrafts,
            DraftState.Archived => ArchivedDrafts,
            DraftState.Trash => TrashedDrafts,
            _ => throw new ArgumentOutOfRangeException(nameof(state)),
        };
        return Filter(source, query, color);
    }

    public string ExportPlainText() => string.Join("\n\n---\n\n", ExportableDrafts().Select(draft => draft.Content));

    public string ExportMarkdown()
    {
        var culture = CultureInfo.GetCultureInfo("zh-CN");
        return string.Join("\n\n---\n\n", ExportableDrafts().Select(draft =>
            $"<!-- {draft.CreatedAt.ToLocalTime().ToString("g", culture)} -->\n\n{draft.Content}"));
    }

    public DraftBookSnapshot ToSnapshot() => new()
    {
        SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion,
        Composer = composer,
        Drafts = drafts.Select(draft => draft.Clone()).ToList(),
        LabelNames = new Dictionary<string, string>(labelNames, StringComparer.Ordinal),
    };

    public void ReplaceWithSnapshot(DraftBookSnapshot snapshot, DateTimeOffset? migrationReferenceDate = null)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        composer = snapshot.Composer ?? string.Empty;
        drafts.Clear();
        drafts.AddRange(snapshot.Drafts.Select(draft => draft.Clone()));
        labelNames.Clear();
        foreach (var pair in snapshot.LabelNames)
        {
            labelNames[pair.Key] = pair.Value;
        }

        if (snapshot.SchemaVersion < 3)
        {
            MigrateLifecycle(migrationReferenceDate ?? DateTimeOffset.Now);
        }

        OnChanged();
    }

    public void InstallSampleDrafts(DateTimeOffset now)
    {
        drafts.RemoveAll(draft => draft.IsSample);
        drafts.AddRange(SampleDrafts.Create(now, TimeZone));
        OnChanged();
    }

    public void RemoveSampleDrafts()
    {
        if (drafts.RemoveAll(draft => draft.IsSample) > 0)
        {
            OnChanged();
        }
    }

    private static int ValidReviewDays(int value) => value is 1 or 3 or 7 or 14 or 30 ? value : 7;

    private IReadOnlyList<Draft> Filter(IEnumerable<Draft> source, string query, DraftColor? color)
    {
        var normalized = query.Trim();
        return source.Where(draft =>
        {
            var matchesQuery = normalized.Length == 0 ||
                draft.Content.Contains(normalized, StringComparison.CurrentCultureIgnoreCase) ||
                draft.DisplayTitle.Contains(normalized, StringComparison.CurrentCultureIgnoreCase);
            return matchesQuery && (color is null || draft.Color == color.Value);
        }).ToList();
    }

    private IEnumerable<Draft> ExportableDrafts() => drafts
        .Where(draft => draft.State != DraftState.Trash && !draft.IsSample)
        .OrderByDescending(draft => draft.CreatedAt);

    private void Mutate(Guid id, Action<Draft> mutation)
    {
        var draft = Find(id);
        if (draft is null)
        {
            return;
        }

        mutation(draft);
        OnChanged();
    }

    private void MigrateLifecycle(DateTimeOffset referenceDate)
    {
        foreach (var draft in drafts.Where(draft => draft.State == DraftState.Active))
        {
            if (draft.Pinned)
            {
                draft.ReviewIntervalDays = null;
                draft.ReviewAt = null;
            }
            else
            {
                draft.ReviewIntervalDays = DefaultReviewDays;
                draft.ReviewAt = DraftTiming.AddCalendarDays(referenceDate, DefaultReviewDays, TimeZone);
            }
        }
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}

public sealed class DraftBookValidationException(string message) : Exception(message);

internal static class SampleDrafts
{
    public static IReadOnlyList<Draft> Create(DateTimeOffset now, TimeZoneInfo timeZone) =>
    [
        New("【示例：普通草稿】\n这是一条刚创建的蓝色草稿。最后修改 7 天后，它会进入清理台。", now, DraftColor.Blue, 7, timeZone),
        New("【示例：即将到期】\n这条黄色草稿会在 1 天后进入清理台。", now.AddDays(-6), DraftColor.Yellow, 1, timeZone, updatedAt: now),
        New("【示例：待处理草稿】\n这条红色草稿已经到期，可延期、固定、存档或删除。", now.AddDays(-8), DraftColor.Red, 7, timeZone, reviewAt: now.AddHours(-1)),
        new Draft
        {
            Content = "【示例：固定保留】\n这条紫色草稿不会进入清理台。",
            CreatedAt = now.AddDays(-30), UpdatedAt = now.AddDays(-30), Color = DraftColor.Purple,
            Pinned = true, ReviewIntervalDays = null, ReviewAt = null, IsSample = true,
        },
        New("# 示例：Markdown\n\n- 划定后自动呈现 **Markdown**\n- 点击正文编辑源码\n\n> 随手写，稍后再整理。", now.AddDays(-1), DraftColor.Green, 7, timeZone, markdown: true),
        new Draft
        {
            Content = "【示例：已存档】\n存档适合已经完成、但仍值得长期保留的文字。",
            CreatedAt = now.AddDays(-20), UpdatedAt = now.AddDays(-10), Color = DraftColor.Blue,
            State = DraftState.Archived, ArchivedAt = now.AddDays(-1), Title = "一条已完成的示例存档",
            ReviewIntervalDays = null, ReviewAt = null, IsSample = true,
        },
        new Draft
        {
            Content = "【示例：回收站】\n删除不是立即消失：可以恢复，也可以确认后永久删除。",
            CreatedAt = now.AddDays(-12), UpdatedAt = now.AddDays(-12), State = DraftState.Trash,
            DeletedAt = now.AddHours(-1), ReviewIntervalDays = null, ReviewAt = null, IsSample = true,
        },
    ];

    private static Draft New(
        string content,
        DateTimeOffset createdAt,
        DraftColor color,
        int days,
        TimeZoneInfo timeZone,
        DateTimeOffset? updatedAt = null,
        DateTimeOffset? reviewAt = null,
        bool markdown = false) => new()
        {
            Content = content,
            CreatedAt = createdAt,
            UpdatedAt = updatedAt ?? createdAt,
            Color = color,
            MarkdownEnabled = markdown,
            ReviewIntervalDays = days,
            ReviewAt = reviewAt ?? DraftTiming.AddCalendarDays(updatedAt ?? createdAt, days, timeZone),
            IsSample = true,
        };
}
