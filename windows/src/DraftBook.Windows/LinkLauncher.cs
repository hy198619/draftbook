using System.Diagnostics;
using System.IO;
using System.Windows;

namespace DraftBook.Windows;

public static class LinkLauncher
{
    private static readonly HashSet<string> RiskyExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".bat", ".cmd", ".com", ".cpl", ".exe", ".hta", ".js", ".jse", ".lnk", ".msi", ".msp",
        ".ps1", ".reg", ".scr", ".vbe", ".vbs", ".wsf",
    };

    public static bool TryNormalize(string? destination, out Uri? uri)
    {
        uri = null;
        if (string.IsNullOrWhiteSpace(destination))
        {
            return false;
        }

        var value = destination.Trim();
        if (Uri.TryCreate(value, UriKind.Absolute, out var parsed) &&
            (parsed.Scheme == Uri.UriSchemeHttp || parsed.Scheme == Uri.UriSchemeHttps))
        {
            uri = parsed;
            return true;
        }

        if (Uri.TryCreate(value, UriKind.Absolute, out parsed) && parsed.IsFile && File.Exists(parsed.LocalPath))
        {
            uri = parsed;
            return true;
        }

        if (Path.IsPathFullyQualified(value) && File.Exists(value))
        {
            uri = new Uri(value);
            return true;
        }

        return false;
    }

    public static void Open(Window owner, Uri uri)
    {
        if (uri.IsFile && RiskyExtensions.Contains(Path.GetExtension(uri.LocalPath)))
        {
            var answer = MessageBox.Show(owner,
                $"这个文件可能执行命令：\n{uri.LocalPath}\n\n确定要用默认应用打开吗？",
                "确认打开文件", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes)
            {
                return;
            }
        }

        try
        {
            Process.Start(new ProcessStartInfo(uri.IsFile ? uri.LocalPath : uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            MessageBox.Show(owner, $"无法打开目标：\n{exception.Message}", "草稿本",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
