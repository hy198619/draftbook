using System.Runtime.InteropServices;
using System.Windows;

namespace DraftBook.Windows;

public static class ClipboardService
{
    public static bool TrySetText(Window owner, string text)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(text, copy: true);
                return true;
            }
            catch (COMException)
            {
                if (attempt == 4)
                {
                    break;
                }
                Thread.Sleep(25 * (attempt + 1));
            }
        }

        MessageBox.Show(owner, "剪贴板正被其他程序占用，请稍后重试。", "复制失败",
            MessageBoxButton.OK, MessageBoxImage.Warning);
        return false;
    }
}
