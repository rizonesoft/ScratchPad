using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace ScratchPad;

// Status strip, owned by D01 T02 §4. Renders a StatusView computed
// neutrally; MainWindow refreshes it on tab switches, edits, caret
// moves, per-tab property changes, and settings changes.
internal sealed partial class StatusBar : UserControl
{
    // D01 T02 §7: the text and tab the shown score was computed for.
    // Any other text or tab resets the readout to its prompt, so a score
    // never outlives the buffer it measured and nothing recomputes
    // unprompted.
    private string? scoredText;
    private object? scoredTab;

    public StatusBar()
    {
        InitializeComponent();
    }

    // D01 T02 §11: the session goal lives only here, in this window's
    // strip: nothing persists it, so it dies with the window.
    private int? goal;
    private int words;

    // D01 T02 §9: the live words segment. The owner computes off the UI
    // thread and hands over the count and its finished label.
    public void ShowWords(string label, int wordCount, int computeCount)
    {
        ArgumentNullException.ThrowIfNull(label);
        WordsText.Text = label;
        AutomationProperties.SetName(WordsText, label);
        words = wordCount;
        ShowGoal();

        // Test seam (test-run marker only): the number of counts the
        // window has run, so the §9 drive can prove one per pause.
        if (Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable) == "1")
        {
            AutomationProperties.SetHelpText(WordsText, "counts " + computeCount.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
    }

    // Test seam for the §9 typing benchmark's baseline leg: the strip as
    // it was before the words segment existed.
    public void HideWords()
    {
        WordsText.Visibility = Visibility.Collapsed;
        WordsDivider.Visibility = Visibility.Collapsed;
        GoalButton.Visibility = Visibility.Collapsed;
    }

    private void GoalSet_Click(object sender, RoutedEventArgs e)
    {
        (int? parsed, string? error) = WordGoal.Parse(GoalInput.Text);
        if (parsed is null)
        {
            // Refused: the message shows and the goal stays as it was.
            GoalError.Text = error ?? string.Empty;
            GoalError.Visibility = Visibility.Visible;
            return;
        }

        goal = parsed;
        GoalError.Visibility = Visibility.Collapsed;
        GoalFlyout.Hide();
        ShowGoal();
    }

    private void GoalClear_Click(object sender, RoutedEventArgs e)
    {
        goal = null;
        GoalInput.Text = string.Empty;
        GoalError.Visibility = Visibility.Collapsed;
        GoalFlyout.Hide();
        ShowGoal();
    }

    private void ShowGoal()
    {
        string label = WordGoal.Label(goal);
        AutomationProperties.SetName(GoalButton, label);
        ToolTipService.SetToolTip(GoalButton, label);
        GoalClear.IsEnabled = goal is not null;
        if (goal is int target)
        {
            GoalProgress.Value = WordGoal.Percent(words, target);
            GoalProgress.Visibility = Visibility.Visible;
        }
        else
        {
            GoalProgress.Visibility = Visibility.Collapsed;
        }
    }

    // Raised on a click; the owner computes over the active buffer and
    // answers through ShowReadingLevel.
    public event EventHandler? ReadingLevelRequested;

    public void ShowReadingLevel(ReadingLevel? level, object tab, string text)
    {
        ArgumentNullException.ThrowIfNull(tab);
        ArgumentNullException.ThrowIfNull(text);
        scoredTab = tab;
        scoredText = text;
        SetReadingLevel(Readability.Label(level));
    }

    // Called on every refresh: keeps the score only while the active tab
    // and its text are the ones it was computed for.
    public void KeepReadingLevelFor(object? tab, string? text)
    {
        if (scoredText is null)
        {
            return;
        }

        if (!Equals(tab, scoredTab) || !string.Equals(text, scoredText, StringComparison.Ordinal))
        {
            scoredTab = null;
            scoredText = null;
            SetReadingLevel("Reading level");
        }
    }

    private void SetReadingLevel(string label)
    {
        ReadingLevelButton.Content = label;
        AutomationProperties.SetName(ReadingLevelButton, label);
    }

    private void ReadingLevelButton_Click(object sender, RoutedEventArgs e) =>
        ReadingLevelRequested?.Invoke(this, EventArgs.Empty);

    public void Show(StatusView view)
    {
        ArgumentNullException.ThrowIfNull(view);
        LineColumnText.Text = view.LineColumn;

        // UIA names mirror stock's quirks verbatim (newline in the
        // line/column name, leading spaces, bare "Zoom"); visuals carry
        // the plain text. Automation sees parity either way it reads.
        AutomationProperties.SetName(LineColumnText, view.LineColumnName);
        CountText.Text = view.Count;
        AutomationProperties.SetName(CountText, view.Count);
        ZoomText.Text = view.Zoom;
        AutomationProperties.SetName(ZoomText, view.ZoomName);
        EolText.Text = view.Eol;
        AutomationProperties.SetName(EolText, view.EolName);
        EncodingText.Text = view.Encoding;
        AutomationProperties.SetName(EncodingText, view.EncodingName);
        if (view.ModeIsButton)
        {
            // Text label only: the stock button carries a per-view icon
            // whose glyph ships with the live switch in D02 T04 §3 (the
            // disabled placeholder needs no icon).
            ModeText.Visibility = Visibility.Collapsed;
            ModeButton.Visibility = Visibility.Visible;
            ModeButton.Content = view.Mode;
            AutomationProperties.SetName(ModeButton, view.Mode);
        }
        else
        {
            ModeButton.Visibility = Visibility.Collapsed;
            ModeText.Visibility = Visibility.Visible;
            ModeText.Text = view.Mode;
        }
    }
}
