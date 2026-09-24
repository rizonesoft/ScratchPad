using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §21 item 11: the shortcut text each menu item displays (its
// UIA AcceleratorKey, which WinUI derives from the KeyboardAccelerator
// when no override exists) matches the binding manifest. Read on the
// rendered menu of a background window: menus open through Invoke and
// ExpandCollapse, never focus. Stock-text parity (Del vs Delete,
// Ctrl+Plus vs Ctrl++) is D01 T02 §6's audit, not this check.
[Collection("UI tests")]
public sealed class MenuLabelTests
{
    static readonly (string Top, string? Sub)[] Menus =
    [
        ("MenuFile", null),
        ("MenuEdit", null),
        ("MenuView", "MenuViewZoom"),
        ("MenuTools", null),
    ];

    [Fact]
    public void DisplayedShortcutTextMatchesTheManifest()
    {
        string root = BindingManifestTests.RepoRoot();
        var decls = BindingManifest.ParseMenuXaml(File.ReadAllText(Path.Combine(root, BindingManifest.MenuXamlPath)), out _, out var parse);
        Assert.Empty(parse);
        var expected = decls.GroupBy(d => d.Command).ToDictionary(g => g.Key, g => BindingManifest.ExpectedLabel(g.First().Chord), StringComparer.Ordinal);
        var seen = new Dictionary<string, string>(StringComparer.Ordinal);
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            foreach (var (top, sub) in Menus)
            {
                OpenMenu(window, top);
                if (sub is not null)
                {
                    var subItem = Retry.WhileNull(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId(sub)),
                        TimeSpan.FromSeconds(5),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.NotNull(subItem);
                    subItem.Patterns.ExpandCollapse.Pattern.Expand();
                    Thread.Sleep(600);
                }

                foreach (string id in expected.Keys)
                {
                    var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                    if (item is not null)
                    {
                        seen[id] = item.Properties.AcceleratorKey.ValueOrDefault ?? string.Empty;
                    }
                }

                CloseMenu(window, top);
            }
        }
        finally
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                // Already gone.
            }

            if (!app.HasExited)
            {
                app.Kill();
            }
        }

        Assert.Equal(expected.Keys.Order(StringComparer.Ordinal), seen.Keys.Order(StringComparer.Ordinal));
        Assert.Empty(BindingManifestTests.LabelMismatches(expected, seen));
    }

    static void OpenMenu(Window window, string topId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        var expand = top.Patterns.ExpandCollapse.PatternOrDefault;
        if (expand is not null && expand.ExpandCollapseState != FlaUI.Core.Definitions.ExpandCollapseState.Expanded)
        {
            top.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(600);
        }
    }

    static void CloseMenu(Window window, string topId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        var expand = top?.Patterns.ExpandCollapse.PatternOrDefault;
        if (top is not null && (expand is null || expand.ExpandCollapseState == FlaUI.Core.Definitions.ExpandCollapseState.Expanded))
        {
            top.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(400);
        }
    }
}
