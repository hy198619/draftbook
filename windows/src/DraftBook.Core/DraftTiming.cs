namespace DraftBook.Core;

public enum TagAgeStage
{
    Fresh,
    FiveDays,
    SevenDays,
    ThirtyDays,
}

public static class DraftTiming
{
    private static readonly TimeSpan FiveDays = TimeSpan.FromDays(5);
    private static readonly TimeSpan SevenDays = TimeSpan.FromDays(7);
    private static readonly TimeSpan ThirtyDays = TimeSpan.FromDays(30);

    public static TagAgeStage TagAgeStage(DateTimeOffset createdAt, DateTimeOffset referenceDate)
    {
        var age = referenceDate - createdAt;
        if (age < TimeSpan.Zero || age < FiveDays)
        {
            return Core.TagAgeStage.Fresh;
        }

        if (age < SevenDays)
        {
            return Core.TagAgeStage.FiveDays;
        }

        return age < ThirtyDays ? Core.TagAgeStage.SevenDays : Core.TagAgeStage.ThirtyDays;
    }

    public static double TagSaturation(DateTimeOffset createdAt, DateTimeOffset referenceDate) =>
        TagAgeStage(createdAt, referenceDate) switch
        {
            Core.TagAgeStage.Fresh => 1,
            Core.TagAgeStage.FiveDays => 0.86,
            Core.TagAgeStage.SevenDays => 0.73,
            Core.TagAgeStage.ThirtyDays => 0.60,
            _ => throw new ArgumentOutOfRangeException(),
        };

    public static int WholeDaysSinceUpdate(DateTimeOffset updatedAt, DateTimeOffset referenceDate) =>
        Math.Max(0, (int)Math.Floor((referenceDate - updatedAt).TotalDays));

    public static string UneditedDescription(DateTimeOffset updatedAt, DateTimeOffset referenceDate)
    {
        var days = WholeDaysSinceUpdate(updatedAt, referenceDate);
        return days == 0 ? "今天更新" : $"已有 {days} 天未编辑";
    }

    public static string CleanupDescription(
        DateTimeOffset? reviewAt,
        bool isPinned,
        DateTimeOffset referenceDate,
        TimeZoneInfo? timeZone = null)
    {
        if (isPinned)
        {
            return "已固定，不进入清理台";
        }

        if (reviewAt is null)
        {
            return "没有清理计划";
        }

        if (reviewAt <= referenceDate)
        {
            return "已进入清理台";
        }

        timeZone ??= TimeZoneInfo.Local;
        var start = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(referenceDate, timeZone).Date);
        var end = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(reviewAt.Value, timeZone).Date);
        var days = end.DayNumber - start.DayNumber;
        return days switch
        {
            <= 0 => "今天进入清理台",
            1 => "明天进入清理台",
            _ => $"还有 {days} 天进入清理台",
        };
    }

    public static DateTimeOffset AddCalendarDays(
        DateTimeOffset instant,
        int days,
        TimeZoneInfo? timeZone = null)
    {
        timeZone ??= TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(instant, timeZone);
        var targetLocal = local.DateTime.AddDays(days);
        var offset = timeZone.GetUtcOffset(targetLocal);
        return new DateTimeOffset(targetLocal, offset);
    }
}
