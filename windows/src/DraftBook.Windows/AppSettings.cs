using System.IO;
using System.Text.Json;

namespace DraftBook.Windows;

public sealed class AppSettings
{
    public bool Topmost { get; set; }
    public int DefaultReviewDays { get; set; } = 7;
    public bool AutomaticBackupsEnabled { get; set; } = true;
    public int BackupRetentionCount { get; set; } = 14;
    public double WindowWidth { get; set; } = 560;
    public double WindowHeight { get; set; } = 820;

    public void Normalize()
    {
        DefaultReviewDays = DefaultReviewDays is 1 or 3 or 7 or 14 or 30 ? DefaultReviewDays : 7;
        BackupRetentionCount = BackupRetentionCount is 7 or 14 or 30 ? BackupRetentionCount : 14;
        WindowWidth = Math.Clamp(WindowWidth, 360, 2400);
        WindowHeight = Math.Clamp(WindowHeight, 520, 1600);
    }
}

public sealed class AppSettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    private readonly string path;

    public AppSettingsStore(string dataDirectory)
    {
        path = Path.Combine(dataDirectory, "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(path))
            {
                return new AppSettings();
            }

            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), Options) ?? new AppSettings();
            settings.Normalize();
            return settings;
        }
        catch (JsonException)
        {
            return new AppSettings();
        }
        catch (IOException)
        {
            return new AppSettings();
        }
        catch (UnauthorizedAccessException)
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        settings.Normalize();
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("设置文件路径无效。");
        Directory.CreateDirectory(directory);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(settings, Options));
        File.Move(temporary, path, true);
    }
}
