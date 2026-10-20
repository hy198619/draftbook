using System.Text;
using System.Text.Json;
using DraftBook.Core;

namespace DraftBook.Core.Tests;

public sealed class SnapshotJsonTests
{
    [Fact]
    public void SyntheticMacSnapshotRoundTripsWithoutLosingFields()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "schema-v5-synthetic.json");
        var snapshot = SnapshotJson.Deserialize(File.ReadAllBytes(path));

        Assert.Equal(5, snapshot.SchemaVersion);
        Assert.Equal(3, snapshot.Drafts.Count);
        Assert.Contains("emoji", snapshot.Composer);
        Assert.Equal("内容", snapshot.LabelNames["blue"]);
        Assert.Contains(snapshot.Drafts, draft => draft.State == DraftState.Archived && draft.Title == "合成存档标题");

        var roundTrip = SnapshotJson.Deserialize(SnapshotJson.Serialize(snapshot));
        Assert.Equal(snapshot.Drafts.Select(draft => draft.Id), roundTrip.Drafts.Select(draft => draft.Id));
        Assert.Equal(snapshot.Drafts.Select(draft => draft.Content), roundTrip.Drafts.Select(draft => draft.Content));
    }

    [Fact]
    public void TextMarkdownWhitespaceAndLinksRoundTripExactly()
    {
        const string content = "开头  保留两个空格\r\n\t制表符与换行\n\n" +
                               "**Markdown 粗体** 和 https://example.com/path?q=草稿\n" +
                               "[Markdown 链接](https://example.com/docs?id=1#part)";
        var snapshot = new DraftBookSnapshot
        {
            SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion,
            Composer = content,
            Drafts =
            [
                new Draft
                {
                    Content = content,
                    CreatedAt = DateTimeOffset.UnixEpoch,
                    UpdatedAt = DateTimeOffset.UnixEpoch,
                },
            ],
        };

        var restored = SnapshotJson.Deserialize(SnapshotJson.Serialize(snapshot));

        Assert.Equal(content, restored.Composer);
        Assert.Equal(content, restored.Drafts.Single().Content);
    }

    [Fact]
    public void DatesWriteUtcAtSecondPrecisionAndReadFractionsAndOffsets()
    {
        var json = """
        {
          "schemaVersion": 5,
          "composer": "",
          "drafts": [{
            "id": "11111111-1111-4111-8111-111111111111",
            "content": "日期",
            "createdAt": "2026-10-12T09:02:03.456+08:00",
            "updatedAt": "2026-10-12T01:02:03Z"
          }],
          "labelNames": {}
        }
        """;

        var snapshot = SnapshotJson.Deserialize(Encoding.UTF8.GetBytes(json));
        var output = Encoding.UTF8.GetString(SnapshotJson.Serialize(snapshot));

        Assert.Contains("2026-10-12T01:02:03Z", output);
        Assert.DoesNotContain(".456", output);
    }

    [Fact]
    public void LegacySnapshotDefaultsAndMigratesLifecycle()
    {
        var json = """
        {
          "composer": "旧版输入",
          "drafts": [{
            "content": "旧版草稿",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
          }]
        }
        """;
        var snapshot = SnapshotJson.Deserialize(Encoding.UTF8.GetBytes(json));
        var state = new DraftBookState(
            snapshot,
            defaultReviewDays: 7,
            timeZone: TimeZoneInfo.Utc,
            migrationReferenceDate: new DateTimeOffset(2026, 2, 1, 0, 0, 0, TimeSpan.Zero));

        var draft = state.OrderedDrafts.Single();
        Assert.Equal(1, snapshot.SchemaVersion);
        Assert.Equal(DraftColor.Gray, draft.Color);
        Assert.Equal(DraftState.Active, draft.State);
        Assert.Equal(7, draft.ReviewIntervalDays);
        Assert.Equal(new DateTimeOffset(2026, 2, 8, 0, 0, 0, TimeSpan.Zero), draft.ReviewAt);
    }

    [Theory]
    [InlineData(6)]
    [InlineData(999)]
    public void FutureSchemaIsRejected(int version)
    {
        var data = Encoding.UTF8.GetBytes($$"""
        { "schemaVersion": {{version}}, "composer": "", "drafts": [], "labelNames": {} }
        """);
        var exception = Assert.Throws<UnsupportedSchemaException>(() => SnapshotJson.Deserialize(data));
        Assert.Equal(version, exception.Version);
    }

    [Theory]
    [InlineData("{ not-json")]
    [InlineData("{\"schemaVersion\":5,\"drafts\":[{\"content\":\"缺日期\"}]}")]
    [InlineData("{\"schemaVersion\":5,\"drafts\":[{\"content\":\"x\",\"createdAt\":\"bad\",\"updatedAt\":\"bad\"}]}")]
    public void InvalidDataIsRejected(string json) =>
        Assert.Throws<DraftBookDataException>(() => SnapshotJson.Deserialize(Encoding.UTF8.GetBytes(json)));

    [Fact]
    public void UnknownEnumIsRejectedInsteadOfSilentlyChangingMeaning()
    {
        var json = """
        {
          "schemaVersion": 5,
          "drafts": [{
            "content": "x",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "color": "orange"
          }]
        }
        """;
        Assert.Throws<DraftBookDataException>(() => SnapshotJson.Deserialize(Encoding.UTF8.GetBytes(json)));
    }

    [Fact]
    public void SerializedKeysUsePublishedCamelCaseContract()
    {
        var snapshot = new DraftBookSnapshot
        {
            SchemaVersion = 5,
            Drafts =
            [
                new Draft
                {
                    Content = "x",
                    CreatedAt = DateTimeOffset.UnixEpoch,
                    UpdatedAt = DateTimeOffset.UnixEpoch,
                    Color = DraftColor.Blue,
                    State = DraftState.Active,
                },
            ],
        };
        using var document = JsonDocument.Parse(SnapshotJson.Serialize(snapshot));
        var root = document.RootElement;
        Assert.Equal(5, root.GetProperty("schemaVersion").GetInt32());
        var draft = root.GetProperty("drafts")[0];
        Assert.Equal("blue", draft.GetProperty("color").GetString());
        Assert.Equal("active", draft.GetProperty("state").GetString());
        Assert.True(draft.TryGetProperty("reviewIntervalDays", out _));
    }
}
