using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DraftBook.Windows;

internal static partial class WindowPlacementService
{
    private const uint MonitorDefaultToNearest = 2;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoZOrder = 0x0004;
    private const int EffectiveDpi = 0;
    private const double DefaultDpi = 96;
    private const double MarginDip = 24;

    public static void Restore(Window window, AppSettings settings)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        var left = settings.WindowLeftPixels ?? 0;
        var top = settings.WindowTopPixels ?? 0;
        var hasSavedPosition = settings.WindowLeftPixels.HasValue && settings.WindowTopPixels.HasValue;
        var anchor = hasSavedPosition
            ? new NativeRect(left, top, left + 1, top + 1)
            : default;
        var monitor = hasSavedPosition
            ? MonitorFromRect(ref anchor, MonitorDefaultToNearest)
            : MonitorFromWindow(handle, MonitorDefaultToNearest);

        if (!TryGetWorkingArea(monitor, out var workArea, out var dpiScale))
        {
            return;
        }

        var margin = DipToPixels(MarginDip, dpiScale);
        var minimumWidth = DipToPixels(window.MinWidth, dpiScale);
        var minimumHeight = DipToPixels(window.MinHeight, dpiScale);
        var availableWidth = Math.Max(1, workArea.Width - (margin * 2));
        var availableHeight = Math.Max(1, workArea.Height - (margin * 2));
        var desiredWidth = ClampToArea(DipToPixels(settings.WindowWidth, dpiScale), minimumWidth, availableWidth);
        var desiredHeight = ClampToArea(DipToPixels(settings.WindowHeight, dpiScale), minimumHeight, availableHeight);

        var desiredLeft = hasSavedPosition
            ? left
            : workArea.Left + ((workArea.Width - desiredWidth) / 2);
        var desiredTop = hasSavedPosition
            ? top
            : workArea.Top + ((workArea.Height - desiredHeight) / 2);
        var maximumLeft = workArea.Right - margin - desiredWidth;
        var maximumTop = workArea.Bottom - margin - desiredHeight;
        desiredLeft = Math.Clamp(desiredLeft, workArea.Left + margin, Math.Max(workArea.Left + margin, maximumLeft));
        desiredTop = Math.Clamp(desiredTop, workArea.Top + margin, Math.Max(workArea.Top + margin, maximumTop));

        SetWindowPos(handle, IntPtr.Zero, desiredLeft, desiredTop, desiredWidth, desiredHeight, SwpNoActivate | SwpNoZOrder);
        if (settings.WindowMaximized)
        {
            window.WindowState = WindowState.Maximized;
        }
    }

    public static void Capture(Window window, AppSettings settings)
    {
        var handle = new WindowInteropHelper(window).Handle;
        var placement = new WindowPlacement { Length = Marshal.SizeOf<WindowPlacement>() };
        if (handle == IntPtr.Zero || !GetWindowPlacement(handle, ref placement))
        {
            return;
        }

        var bounds = placement.NormalPosition;
        var monitor = MonitorFromRect(ref bounds, MonitorDefaultToNearest);
        if (!TryGetWorkingArea(monitor, out _, out var dpiScale))
        {
            dpiScale = 1;
        }

        settings.WindowWidth = Math.Max(window.MinWidth, PixelsToDip(bounds.Width, dpiScale));
        settings.WindowHeight = Math.Max(window.MinHeight, PixelsToDip(bounds.Height, dpiScale));
        settings.WindowLeftPixels = bounds.Left;
        settings.WindowTopPixels = bounds.Top;
        settings.WindowMaximized = window.WindowState == WindowState.Maximized;
    }

    private static bool TryGetWorkingArea(IntPtr monitor, out NativeRect workArea, out double dpiScale)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info))
        {
            workArea = default;
            dpiScale = 1;
            return false;
        }

        workArea = info.WorkArea;
        dpiScale = 1;
        try
        {
            if (GetDpiForMonitor(monitor, EffectiveDpi, out var dpiX, out _) == 0 && dpiX > 0)
            {
                dpiScale = dpiX / DefaultDpi;
            }
        }
        catch (DllNotFoundException)
        {
            // Windows 10 and 11 provide Shcore.dll; keep the 96-DPI fallback for safety.
        }
        catch (EntryPointNotFoundException)
        {
            // Keep the 96-DPI fallback on an unexpectedly old host.
        }
        return true;
    }

    private static int ClampToArea(int requested, int minimum, int available) =>
        Math.Min(Math.Max(requested, Math.Min(minimum, available)), available);

    private static int DipToPixels(double value, double scale) => (int)Math.Round(value * scale);

    private static double PixelsToDip(int value, double scale) => value / Math.Max(scale, 0.01);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect(int left, int top, int right, int bottom)
    {
        public int Left = left;
        public int Top = top;
        public int Right = right;
        public int Bottom = bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect MonitorArea;
        public NativeRect WorkArea;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowPlacement
    {
        public int Length;
        public int Flags;
        public int ShowCommand;
        public NativePoint MinimumPosition;
        public NativePoint MaximumPosition;
        public NativeRect NormalPosition;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromRect(ref NativeRect rectangle, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowPlacement(IntPtr window, ref WindowPlacement placement);

    [DllImport("Shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);
}
