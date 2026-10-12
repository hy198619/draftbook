using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;

namespace DraftBook.Core;

[JsonConverter(typeof(JsonStringEnumConverter<DraftColor>))]
public enum DraftColor
{
    Gray,
    Yellow,
    Blue,
    Purple,
    Green,
    Red,
}

[JsonConverter(typeof(JsonStringEnumConverter<DraftState>))]
public enum DraftState
{
    Active,
    Archived,
    Trash,
}

public sealed class Draft
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Content { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DraftColor Color { get; set; } = DraftColor.Gray;
    public bool MarkdownEnabled { get; set; }
    public bool Pinned { get; set; }
    public DateTimeOffset? LastCopiedAt { get; set; }
    public DraftState State { get; set; } = DraftState.Active;
    public DateTimeOffset? ArchivedAt { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }
    public string? Title { get; set; }
    public int? ReviewIntervalDays { get; set; }
    public DateTimeOffset? ReviewAt { get; set; }
    public bool IsSample { get; set; }

    [JsonIgnore]
    public string SuggestedTitle
    {
        get
        {
            var firstLine = Content
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                .Select(line => line.Trim())
                .FirstOrDefault(line => line.Length > 0) ?? "未命名草稿";
            return UnicodeText.Prefix(firstLine, 20);
        }
    }

    [JsonIgnore]
    public string DisplayTitle => string.IsNullOrWhiteSpace(Title) ? SuggestedTitle : Title.Trim();

    public Draft Clone() => new()
    {
        Id = Id,
        Content = Content,
        CreatedAt = CreatedAt,
        UpdatedAt = UpdatedAt,
        Color = Color,
        MarkdownEnabled = MarkdownEnabled,
        Pinned = Pinned,
        LastCopiedAt = LastCopiedAt,
        State = State,
        ArchivedAt = ArchivedAt,
        DeletedAt = DeletedAt,
        Title = Title,
        ReviewIntervalDays = ReviewIntervalDays,
        ReviewAt = ReviewAt,
        IsSample = IsSample,
    };
}

public sealed class DraftBookSnapshot
{
    public const int CurrentSchemaVersion = 5;

    // A missing version is schema 1 in the published macOS data contract.
    public int SchemaVersion { get; set; } = 1;
    public string Composer { get; set; } = string.Empty;
    public List<Draft> Drafts { get; set; } = [];
    public Dictionary<string, string> LabelNames { get; set; } = [];

    public DraftBookSnapshot Clone() => new()
    {
        SchemaVersion = SchemaVersion,
        Composer = Composer,
        Drafts = Drafts.Select(draft => draft.Clone()).ToList(),
        LabelNames = new Dictionary<string, string>(LabelNames, StringComparer.Ordinal),
    };
}

public static class DraftColorNames
{
    public static string DefaultLabelName(this DraftColor color) => color switch
    {
        DraftColor.Gray => "未分类",
        DraftColor.Yellow => "分类1",
        DraftColor.Blue => "分类2",
        DraftColor.Purple => "分类3",
        DraftColor.Green => "分类4",
        DraftColor.Red => "分类5",
        _ => throw new ArgumentOutOfRangeException(nameof(color)),
    };

    public static string SerializedName(this DraftColor color) => color.ToString().ToLowerInvariant();
}

public static class UnicodeText
{
    public static int Length(string value) => new StringInfo(value).LengthInTextElements;

    public static string Prefix(string value, int count)
    {
        if (count <= 0 || value.Length == 0)
        {
            return string.Empty;
        }

        var indices = StringInfo.ParseCombiningCharacters(value);
        return indices.Length <= count ? value : value[..indices[count]];
    }

    public static string FoldForComparison(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var rune in normalized.EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(rune);
            if (category is not UnicodeCategory.NonSpacingMark and
                not UnicodeCategory.SpacingCombiningMark and
                not UnicodeCategory.EnclosingMark)
            {
                builder.Append(rune.ToString());
            }
        }

        return builder.ToString().Normalize(NormalizationForm.FormC).ToUpper(CultureInfo.CurrentCulture);
    }
}
