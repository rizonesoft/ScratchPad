using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// Document statistics panel, owned by D01 T01 §14. Code-built ContentDialog
// following SavePromptDialog (default WinUI styling): three sections over
// StatsController.Current, computed on open, re-read only through Refresh.
// The provider arrives injected (MainWindow reads the active tab's buffer)
// until D02 T01 §1 binds the real editor buffer. Tabular rows share one
// grid per section so values right-align on a common edge.
internal sealed class StatsDialog : ContentDialog
{
    // Display cap for the unbounded repetition list; the engine keeps all.
    const int MaxRepeatedRows = 50;

    readonly StatsController controller;
    readonly StackPanel topWords = new();
    readonly StackPanel sentences = new();
    readonly StackPanel repeated = new();

    public StatsDialog(ITextProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        controller = new StatsController(provider);
        AutomationProperties.SetAutomationId(this, "StatsDialog");
        Title = "Document statistics";
        CloseButtonText = "Close";
        AutomationProperties.SetAutomationId(topWords, "StatsTopWords");
        AutomationProperties.SetAutomationId(sentences, "StatsSentences");
        AutomationProperties.SetAutomationId(repeated, "StatsRepeatedWords");
        var refresh = new Button { Content = "Refresh", Margin = new Thickness(0, 12, 0, 0) };
        AutomationProperties.SetAutomationId(refresh, "StatsRefreshButton");
        refresh.Click += (_, _) =>
        {
            controller.Refresh();
            Render(controller.Current);
        };
        Content = new StackPanel
        {
            Children = { Section("Top words", topWords), Section("Sentences", sentences), Section("Repeated words", repeated), refresh },
        };
        Render(controller.Current);
    }

    static StackPanel Section(string heading, StackPanel rows)
    {
        var header = new TextBlock { Text = heading, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 4) };
        return new StackPanel { Children = { header, rows } };
    }

    // One grid per section: labels left, values on the shared right edge.
    static Grid ValueGrid(IReadOnlyList<(string Label, string Value)> rows, string? trailer = null)
    {
        var grid = new Grid();
        // Auto/Auto, never Star: a Star column inside the dialog's vertical
        // stack measures unbounded width and pushes the values off-screen
        // (caught on the eyeballed capture). The shared Auto value column
        // still lands every value on one right edge.
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        int row = 0;
        foreach ((string label, string value) in rows)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var labelBlock = new TextBlock { Text = label, Margin = new Thickness(0, 0, 16, 0) };
            var valueBlock = new TextBlock { Text = value, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetRow(labelBlock, row);
            Grid.SetColumn(labelBlock, 0);
            Grid.SetRow(valueBlock, row);
            Grid.SetColumn(valueBlock, 1);
            grid.Children.Add(labelBlock);
            grid.Children.Add(valueBlock);
            row++;
        }

        if (trailer is not null)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var trailerBlock = new TextBlock { Text = trailer };
            Grid.SetRow(trailerBlock, row);
            Grid.SetColumnSpan(trailerBlock, 2);
            grid.Children.Add(trailerBlock);
        }

        return grid;
    }

    void Render(DocumentStats stats)
    {
        topWords.Children.Clear();
        topWords.Children.Add(ValueGrid(stats.TopWords.Select(word => (word.Word, word.Count.ToString(CultureInfo.InvariantCulture))).ToList()));
        sentences.Children.Clear();
        sentences.Children.Add(ValueGrid(
        [
            ("Sentences", stats.TotalSentences.ToString(CultureInfo.InvariantCulture)),
            ("Mean length", FormattableString.Invariant($"{stats.MeanSentenceLength:0.0}")),
            ("Shortest", stats.ShortestSentence.ToString(CultureInfo.InvariantCulture)),
            ("Longest", stats.LongestSentence.ToString(CultureInfo.InvariantCulture)),
            ("Short (1-10)", stats.Buckets.Small.ToString(CultureInfo.InvariantCulture)),
            ("Medium (11-25)", stats.Buckets.Medium.ToString(CultureInfo.InvariantCulture)),
            ("Long (26+)", stats.Buckets.Large.ToString(CultureInfo.InvariantCulture)),
        ]));
        repeated.Children.Clear();
        foreach (string word in stats.RepeatedWords.Take(MaxRepeatedRows))
        {
            repeated.Children.Add(new TextBlock { Text = word });
        }

        if (stats.RepeatedWords.Count > MaxRepeatedRows)
        {
            repeated.Children.Add(new TextBlock { Text = $"+{stats.RepeatedWords.Count - MaxRepeatedRows} more" });
        }
    }
}

// The §14 text seam: MainWindow injects the active tab's buffer; D02 T01 §1
// swaps this for the real editor buffer without touching the dialog.
internal sealed class ActiveTabTextProvider : ITextProvider
{
    readonly Func<string> read;

    public ActiveTabTextProvider(Func<string> read)
    {
        ArgumentNullException.ThrowIfNull(read);
        this.read = read;
    }

    public string GetText() => read();
}
