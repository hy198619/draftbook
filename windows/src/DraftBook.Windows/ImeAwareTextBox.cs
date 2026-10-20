using System.Windows.Controls;
using System.Windows.Input;

namespace DraftBook.Windows;

public sealed class ImeAwareTextBox : TextBox
{
    private bool isComposing;

    public ImeAwareTextBox()
    {
        TextCompositionManager.AddPreviewTextInputStartHandler(this, OnCompositionStarted);
        TextCompositionManager.AddPreviewTextInputUpdateHandler(this, OnCompositionUpdated);
        TextCompositionManager.AddPreviewTextInputHandler(this, OnCompositionCompleted);
        PreviewKeyDown += OnPreviewKeyDown;
        LostKeyboardFocus += (_, _) => isComposing = false;
    }

    public event EventHandler? CommitRequested;

    public bool IsImeComposing => isComposing;

    private void OnCompositionStarted(object sender, TextCompositionEventArgs e) => isComposing = true;

    private void OnCompositionUpdated(object sender, TextCompositionEventArgs e) => isComposing = true;

    private void OnCompositionCompleted(object sender, TextCompositionEventArgs e) => isComposing = false;

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.ImeProcessed || isComposing)
        {
            return;
        }

        if (e.Key == Key.Enter &&
            Keyboard.Modifiers == ModifierKeys.Control &&
            CommitRequested is not null)
        {
            e.Handled = true;
            CommitRequested.Invoke(this, EventArgs.Empty);
        }
    }
}
