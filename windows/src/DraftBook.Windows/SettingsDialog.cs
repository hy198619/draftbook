using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DraftBook.Core;

namespace DraftBook.Windows;

public sealed partial class SettingsDialog : Window
{
    private readonly AppSettings settings;
    private readonly DraftBookState state;
    private readonly Dictionary<DraftColor, TextBox> labels = [];

    public SettingsDialog(AppSettings settings, DraftBookState state, bool showLabelSection = false)
    {
        InitializeComponent();
        this.settings = settings;
        this.state = state;

        TopmostCheckBox.IsChecked = settings.Topmost;
        UpdatesCheckBox.IsChecked = settings.AutomaticUpdatesEnabled;
        BackupsCheckBox.IsChecked = settings.AutomaticBackupsEnabled;

        foreach (var days in new[] { 1, 3, 7, 14, 30 })
        {
            ReviewDaysComboBox.Items.Add(new ComboBoxItem
            {
                Content = $"{days} 天",
                Tag = days,
                IsSelected = settings.DefaultReviewDays == days,
            });
        }
        foreach (var count in new[] { 7, 14, 30 })
        {
            RetentionComboBox.Items.Add(new ComboBoxItem
            {
                Content = $"{count} 份",
                Tag = count,
                IsSelected = settings.BackupRetentionCount == count,
            });
        }

        foreach (var color in Enum.GetValues<DraftColor>().Where(color => color != DraftColor.Gray))
        {
            var box = new TextBox
            {
                Text = state.LabelName(color),
                Width = 210,
                MaxLength = 12,
                VerticalContentAlignment = VerticalAlignment.Center,
            };
            labels[color] = box;
            LabelPanel.Children.Add(LabelRow(color, box));
        }

        if (showLabelSection)
        {
            Loaded += (_, _) =>
            {
                LabelSectionHeading.BringIntoView();
                if (labels.Values.FirstOrDefault() is { } firstLabel)
                {
                    firstLabel.Focus();
                    firstLabel.SelectAll();
                }
            };
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            // Validate the labels before mutating the shared settings object. If
            // validation fails and the user cancels, none of their other choices
            // should leak out of the dialog and be saved later on app exit.
            state.SetLabelNames(labels.ToDictionary(pair => pair.Key, pair => pair.Value.Text));
            settings.Topmost = TopmostCheckBox.IsChecked == true;
            settings.AutomaticUpdatesEnabled = UpdatesCheckBox.IsChecked == true;
            settings.AutomaticBackupsEnabled = BackupsCheckBox.IsChecked == true;
            settings.DefaultReviewDays = (ReviewDaysComboBox.SelectedItem as ComboBoxItem)?.Tag as int? ?? 7;
            settings.BackupRetentionCount = (RetentionComboBox.SelectedItem as ComboBoxItem)?.Tag as int? ?? 14;
            DialogResult = true;
        }
        catch (DraftBookValidationException exception)
        {
            MessageBox.Show(this, exception.Message, "无法保存设置", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static Grid LabelRow(DraftColor color, UIElement input)
    {
        var row = new Grid { Margin = new Thickness(0, 5, 0, 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var label = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        label.Children.Add(new Border
        {
            Width = 22,
            Height = 7,
            CornerRadius = new CornerRadius(4),
            Background = ColorBrush(color),
            Margin = new Thickness(0, 0, 9, 0),
        });
        label.Children.Add(new TextBlock { Text = color.DefaultLabelName(), VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(label);

        Grid.SetColumn(input, 1);
        row.Children.Add(input);
        return row;
    }

    private static Brush ColorBrush(DraftColor color) => new SolidColorBrush(color switch
    {
        DraftColor.Yellow => Color.FromRgb(244, 191, 67),
        DraftColor.Blue => Color.FromRgb(79, 147, 238),
        DraftColor.Purple => Color.FromRgb(154, 106, 221),
        DraftColor.Green => Color.FromRgb(75, 172, 114),
        DraftColor.Red => Color.FromRgb(226, 91, 91),
        _ => Color.FromRgb(183, 183, 183),
    });
}
