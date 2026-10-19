using System.IO;
using System.Text.Json;

namespace DraftBook.Windows;

public sealed class AppSettings
{
    public const int CurrentWindowLayoutVersion = 2;

    public bool Topmost { get; set; }
    public bool HasShownTopmostHint { get; set; }
    public int DefaultReviewDays { get; set; } = 7;
    public bool AutomaticBackupsEnabled { get; set; } = true;
    public int BackupRetentionCount { get; set; } = 14;
    public int WindowLayoutVersion { get; set; } = CurrentWindowLayoutVersion;
    public double WindowWidth { get; set; } = 420;
    public double WindowHeight { get; set; } = 680;
    public int? WindowLeftPixels { get; set; }
    public int? WindowTopPixels { get; set; }
    public bool WindowMaximized { get; set; }

    public void Normalize()
    {
        DefaultReviewDays = DefaultReviewDays is 1 or 3 or 7 or 14 or 30 ? DefaultReviewDays : 7;
        BackupRetentionCount = BackupRetentionCount is 7 or 14 or 30 ? BackupRetentionCount : 14;
        WindowWidth = double.IsFinite(WindowWidth) ? Math.Clamp(WindowWidth, 360, 1600) : 420;
        WindowHeight = double.IsFinite(WindowHeight) ? Math.Clamp(WindowHeight, 380, 1400) : 680;
        WindowLayoutVersion = CurrentWindowLayoutVersion;
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

            var json = File.ReadAllText(path);
            using var document = JsonDocument.Parse(json);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
            if (!document.RootElement.TryGetProperty(nameof(AppSettings.WindowLayoutVersion), out _))
            {
                // preview.1 only stored a fixed 560 x 820 DIP size. On high-DPI and
                // short displays that can place both title bar and footer off-screen.
                settings.WindowWidth = 420;
                settings.WindowHeight = 680;
                settings.WindowLeftPixels = null;
                settings.WindowTopPixels = null;
                settings.WindowMaximized = false;
            }
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
