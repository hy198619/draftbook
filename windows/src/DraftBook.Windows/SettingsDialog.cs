using System.Windows;
using System.Windows.Controls;
using DraftBook.Core;

namespace DraftBook.Windows;

public sealed class SettingsDialog : Window
{
    private readonly CheckBox topmost = new() { Content = "窗口始终置顶" };
    private readonly ComboBox reviewDays = new() { Width = 110 };
    private readonly CheckBox backups = new() { Content = "每日自动备份" };
    private readonly ComboBox retention = new() { Width = 110 };
    private readonly Dictionary<DraftColor, TextBox> labels = [];

    public SettingsDialog(AppSettings settings, DraftBookState state)
    {
        Title = "草稿本设置";
        Width = 390;
        Height = 500;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        topmost.IsChecked = settings.Topmost;
        backups.IsChecked = settings.AutomaticBackupsEnabled;

        foreach (var days in new[] { 1, 3, 7, 14, 30 })
        {
            reviewDays.Items.Add(new ComboBoxItem { Content = $"{days} 天", Tag = days, IsSelected = settings.DefaultReviewDays == days });
        }
        foreach (var count in new[] { 7, 14, 30 })
        {
            retention.Items.Add(new ComboBoxItem { Content = $"{count} 份", Tag = count, IsSelected = settings.BackupRetentionCount == count });
        }

        var root = new DockPanel { Margin = new Thickness(18) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", IsCancel = true, MinWidth = 72 };
        var okay = new Button { Content = "保存", IsDefault = true, MinWidth = 72 };
        okay.Click += (_, _) => Save(settings, state);
        buttons.Children.Add(cancel);
        buttons.Children.Add(okay);
        DockPanel.SetDock(buttons, Dock.Bottom);
        root.Children.Add(buttons);

        var form = new StackPanel();
        form.Children.Add(Heading("常规"));
        form.Children.Add(topmost);
        form.Children.Add(Row("默认清理周期", reviewDays));
        form.Children.Add(Heading("备份"));
        form.Children.Add(backups);
        form.Children.Add(Row("自动备份保留", retention));
        form.Children.Add(Heading("分类名称（最多 12 个字）"));
        foreach (var color in Enum.GetValues<DraftColor>().Where(color => color != DraftColor.Gray))
        {
            var box = new TextBox { Text = state.LabelName(color), Width = 190, MaxLength = 24 };
            labels[color] = box;
            form.Children.Add(Row(color.DefaultLabelName(), box));
        }
        root.Children.Add(form);
        Content = root;
    }

    private void Save(AppSettings settings, DraftBookState state)
    {
        try
        {
            settings.Topmost = topmost.IsChecked == true;
            settings.AutomaticBackupsEnabled = backups.IsChecked == true;
            settings.DefaultReviewDays = (reviewDays.SelectedItem as ComboBoxItem)?.Tag as int? ?? 7;
            settings.BackupRetentionCount = (retention.SelectedItem as ComboBoxItem)?.Tag as int? ?? 14;
            state.SetLabelNames(labels.ToDictionary(pair => pair.Key, pair => pair.Value.Text));
            DialogResult = true;
        }
        catch (DraftBookValidationException exception)
        {
            MessageBox.Show(this, exception.Message, "无法保存设置", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 13, 0, 8),
    };

    private static Grid Row(string label, UIElement input)
    {
        var row = new Grid { Margin = new Thickness(0, 4, 0, 4) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(145) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(input, 1);
        row.Children.Add(input);
        return row;
    }
}
