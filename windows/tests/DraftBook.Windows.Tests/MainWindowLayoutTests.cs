using System.IO;
using System.Xml.Linq;

namespace DraftBook.Windows.Tests;

public sealed class MainWindowLayoutTests
{
    [Fact]
    public void DraftListUsesPhysicalPixelScrolling()
    {
        var document = LoadMainWindow();

        var panel = Assert.Single(
            document.Descendants(Presentation + "StackPanel"),
            element => (string?)element.Attribute(Xaml + "Name") == "DraftPanel");
        var viewer = Assert.Single(panel.Ancestors(Presentation + "ScrollViewer"));

        Assert.Equal("False", (string?)viewer.Attribute("CanContentScroll"));
    }

    [Fact]
    public void ComposerGrowsInsideTheSharedOuterScroller()
    {
        var document = LoadMainWindow();
        var composer = Assert.Single(
            document.Descendants(Local + "ImeAwareTextBox"),
            element => (string?)element.Attribute(Xaml + "Name") == "ComposerBox");
        var draftPanel = Assert.Single(
            document.Descendants(Presentation + "StackPanel"),
            element => (string?)element.Attribute(Xaml + "Name") == "DraftPanel");

        Assert.Null(composer.Attribute("Height"));
        Assert.Null(composer.Attribute("MaxHeight"));
        Assert.Equal("Disabled", (string?)composer.Attribute("VerticalScrollBarVisibility"));
        Assert.Same(
            Assert.Single(composer.Ancestors(Presentation + "ScrollViewer")),
            Assert.Single(draftPanel.Ancestors(Presentation + "ScrollViewer")));
    }

    private static readonly XNamespace Presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
    private static readonly XNamespace Local = "clr-namespace:DraftBook.Windows";

    private static XDocument LoadMainWindow()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "MainWindow.xaml");
        return XDocument.Load(path);
    }
}
