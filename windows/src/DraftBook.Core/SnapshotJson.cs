using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DraftBook.Core;

public static class SnapshotJson
{
    private static readonly JsonSerializerOptions Options = CreateOptions();

    public static byte[] Serialize(DraftBookSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        Validate(snapshot, rejectFutureSchema: true);
        return JsonSerializer.SerializeToUtf8Bytes(snapshot, Options);
    }

    public static DraftBookSnapshot Deserialize(ReadOnlySpan<byte> data, bool rejectFutureSchema = true)
    {
        DraftBookSnapshot snapshot;
        try
        {
            snapshot = JsonSerializer.Deserialize<DraftBookSnapshot>(data, Options)
                ?? throw new DraftBookDataException("备份内容为空。");
        }
        catch (JsonException exception)
        {
            throw new DraftBookDataException("无法解析草稿数据。", exception);
        }

        Validate(snapshot, rejectFutureSchema);
        return snapshot;
    }

    public static JsonSerializerOptions SerializerOptions => new(Options);

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = false,
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            AllowTrailingCommas = false,
            ReadCommentHandling = JsonCommentHandling.Disallow,
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        options.Converters.Add(new Iso8601SecondPrecisionConverter());
        return options;
    }

    private static void Validate(DraftBookSnapshot snapshot, bool rejectFutureSchema)
    {
        if (snapshot.SchemaVersion < 1)
        {
            throw new DraftBookDataException($"无效的数据版本：{snapshot.SchemaVersion}。");
        }

        if (rejectFutureSchema && snapshot.SchemaVersion > DraftBookSnapshot.CurrentSchemaVersion)
        {
            throw new UnsupportedSchemaException(snapshot.SchemaVersion);
        }

        snapshot.Composer ??= string.Empty;
        snapshot.Drafts ??= [];
        snapshot.LabelNames ??= [];
        foreach (var draft in snapshot.Drafts)
        {
            if (draft.Content is null)
            {
                throw new DraftBookDataException("草稿缺少正文。");
            }

            if (draft.CreatedAt == default || draft.UpdatedAt == default)
            {
                throw new DraftBookDataException("草稿缺少有效的创建或更新时间。");
            }

            if (draft.ReviewIntervalDays is <= 0)
            {
                throw new DraftBookDataException("草稿的清理周期必须大于 0。");
            }
        }

        foreach (var pair in snapshot.LabelNames)
        {
            if (!Enum.TryParse<DraftColor>(pair.Key, ignoreCase: true, out var color) || color == DraftColor.Gray)
            {
                throw new DraftBookDataException($"未知或不可自定义的标签：{pair.Key}。");
            }
        }
    }
}

public sealed class Iso8601SecondPrecisionConverter : JsonConverter<DateTimeOffset>
{
    private const string OutputFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (value is null || !DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                out var result))
        {
            throw new JsonException("日期必须是有效的 ISO 8601 字符串。");
        }

        return result;
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToUniversalTime().ToString(OutputFormat, CultureInfo.InvariantCulture));
}

public class DraftBookDataException(string message, Exception? innerException = null)
    : Exception(message, innerException);

public sealed class UnsupportedSchemaException(int version)
    : DraftBookDataException($"这份备份来自更新版本的草稿本（数据版本 {version}），当前版本无法安全恢复。")
{
    public int Version { get; } = version;
}
