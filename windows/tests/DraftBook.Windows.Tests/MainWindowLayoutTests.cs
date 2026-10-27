using System.Xml.Linq;

namespace DraftBook.Windows.Tests;

public sealed class MainWindowLayoutTests
{
    [Fact]
    public void DraftListUsesPhysicalPixelScrolling()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "MainWindow.xaml");
        var document = XDocument.Load(path);
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

        var panel = Assert.Single(document
            .Descendants(presentation + "StackPanel")
            .Where(element => (string?)element.Attribute(xaml + "Name") == "DraftPanel"));
        var viewer = Assert.IsType<XElement>(panel.Parent);

        Assert.Equal(presentation + "ScrollViewer", viewer.Name);
        Assert.Equal("False", (string?)viewer.Attribute("CanContentScroll"));
    }
}
