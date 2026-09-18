using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §6: quit and relaunch restores tabs, contents, and carets; both
// startup modes; the missing-file notice plus snapshot drop; multi-window
// restore; recents order, truncation, and the tab-close-only trigger.
[Collection("UI tests")]
public sealed class SessionRestoreTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void QuitAndRelaunchRestoresTabsContentsAndCarets()
    {
        string dir = NewTempDir();
        string fileA = Path.Combine(dir, "alpha.txt");
        string fileB = Path.Combine(dir, "bravo.txt");
        File.WriteAllText(fileA, "alpha one\ntwo\nthree");
        File.WriteAllText(fileB, "bravo base");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows =
            [
                new SessionWindow
                {
                    Active = 0,
                    Tabs =
                    [
                        new SessionTab { Path = fileA, Caret = 5 },
                        new SessionTab { Content = "unsaved one\ntwo", Caret = 8 },
                        new SessionTab { Path = fileB, Content = "bravo edited", Caret = 4 },
                    ],
                },
            ],
        }.Save();
        try
        {
            int wantA;
            int wantU;
            int wantB;
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(3, WaitForTabCount(window, 3));
                    WaitForTabName(window, 0, TabAccessibilityName.For("alpha.txt", isDirty: false));
                    WaitForTabName(window, 1, TabAccessibilityName.For("unsaved one", isDirty: true));
                    WaitForTabName(window, 2, TabAccessibilityName.For("bravo.txt", isDirty: true));
                    Assert.Equal("alpha one\ntwo\nthree", NormalizeBreaks(BoxText(window)));

                    // Restore sets carets: typing lands at the seeded offset.
                    SelectTab(window, 1);
                    Thread.Sleep(400);
                    ContentBox(window).Focus();
                    Keyboard.Type("Q");
                    Assert.Equal(8, ContentBox(window).Text.IndexOf('Q', StringComparison.Ordinal));
                    SelectTab(window, 2);
                    Thread.Sleep(400);
                    ContentBox(window).Focus();
                    Keyboard.Type("Q");
                    Assert.Equal(4, ContentBox(window).Text.IndexOf('Q', StringComparison.Ordinal));

                    // Reposition every caret from the end, then quit.
                    wantA = PositionCaretFromEnd(window, 0, 2);
                    wantU = PositionCaretFromEnd(window, 1, 2);
                    wantB = PositionCaretFromEnd(window, 2, 2);
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            // The snapshot proves capture: clean tab stays a path with its
            // caret, buffers persist, active follows the last touch.
            SessionData snap = SessionData.Load();
            SessionWindow snapWindow = Assert.Single(snap.Windows);
            Assert.Equal(3, snapWindow.Tabs.Count);
            Assert.Equal(2, snapWindow.Active);
            Assert.Equal(fileA, snapWindow.Tabs[0].Path);
            Assert.Null(snapWindow.Tabs[0].Content);
            Assert.Equal(wantA, snapWindow.Tabs[0].Caret);
            Assert.Contains("Q", snapWindow.Tabs[1].Content, StringComparison.Ordinal);
            Assert.Equal(wantU, snapWindow.Tabs[1].Caret);
            Assert.Contains("Q", snapWindow.Tabs[2].Content, StringComparison.Ordinal);
            Assert.Equal(wantB, snapWindow.Tabs[2].Caret);

            // Round-trip: typing after relaunch lands at the snapshotted caret.
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(3, WaitForTabCount(window, 3));
                    AssertTypeLandsAt(window, 0, wantA, "Z");
                    AssertTypeLandsAt(window, 1, wantU, "Z");
                    AssertTypeLandsAt(window, 2, wantB, "Z");
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void FreshModeStartsNewWindowAndDiscardsSession()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "fresh.txt");
        File.WriteAllText(file, "fresh");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Caret = 1 }] }],
        }.Save();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    Assert.Equal(TabAccessibilityName.For("Untitled", isDirty: false), TabItemAt(window, 0).Name);
                    Assert.Equal(string.Empty, ContentBox(window).Text);
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            Assert.False(File.Exists(SessionData.FilePath));
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void CleanProfileRestoresWithContinueDefault()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "clean.txt");
        File.WriteAllText(file, "clean profile");
        try
        {
            if (File.Exists(SessionData.FilePath))
            {
                File.Delete(SessionData.FilePath);
            }

            string settingsPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ScratchPad", "settings.json");
            if (File.Exists(settingsPath))
            {
                File.Delete(settingsPath);
            }

            new SessionData
            {
                Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Caret = 2 }] }],
            }.Save();
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    WaitForTabName(window, 0, TabAccessibilityName.For("clean.txt", isDirty: false));
                    Assert.Equal("clean profile", BoxText(window).Replace("\r\n", "\n", StringComparison.Ordinal));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            SeedSettings(new ShellSettings { WhatsNewSeen = true });
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void MissingFileNotifiesOnActivationAndDropsFromSnapshot()
    {
        string dir = NewTempDir();
        string good = Path.Combine(dir, "good.txt");
        string missing = Path.Combine(dir, "missing.txt");
        File.WriteAllText(good, "good");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows =
            [
                new SessionWindow
                {
                    Active = 0,
                    Tabs =
                    [
                        new SessionTab { Path = good, Caret = 1 },
                        new SessionTab { Path = missing, Caret = 0 },
                    ],
                },
            ],
        }.Save();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 0, TabAccessibilityName.For("good.txt", isDirty: false));
                    WaitForTabName(window, 1, TabAccessibilityName.For("missing.txt", isDirty: false));
                    Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("MissingFileDialog")));

                    // The notice is lazy: activating the ghost raises it.
                    SelectTab(window, 1);
                    WaitForTabSelected(window, 1);
                    var dialog = Retry.WhileNull(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId("MissingFileDialog")),
                        TimeSpan.FromSeconds(10),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.NotNull(dialog);
                    var texts = dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
                        .Select(el =>
                        {
                            try
                            {
                                return el.Properties.Name.ValueOrDefault ?? string.Empty;
                            }
                            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                            {
                                // Torn-down or busy element; treat as no text.
                                return string.Empty;
                            }
                        }).ToList();
                    Assert.Contains(texts, t => t.Contains("Cannot find the", StringComparison.Ordinal));
                    Assert.Contains(texts, t => t.Contains("missing.txt", StringComparison.Ordinal));
                    var ok = dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("OK")));
                    Assert.NotNull(ok);
                    ok.AsButton().Invoke();
                    var gone = Retry.While(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId("MissingFileDialog")),
                        found => found is not null,
                        TimeSpan.FromSeconds(5),
                        TimeSpan.FromMilliseconds(250));
                    Assert.Null(gone.Result);
                    Assert.Equal(2, TabItems(window).Count);
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            SessionData snap = SessionData.Load();
            SessionTab kept = Assert.Single(Assert.Single(snap.Windows).Tabs);
            Assert.Equal(good, kept.Path);

            nint fgBefore2 = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore2);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    WaitForTabName(window, 0, TabAccessibilityName.For("good.txt", isDirty: false));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void MultiWindowSessionRestoresBothWindows()
    {
        string dir = NewTempDir();
        string fileA = Path.Combine(dir, "wina.txt");
        string fileB = Path.Combine(dir, "winb.txt");
        File.WriteAllText(fileA, "window one file");
        File.WriteAllText(fileB, "window two file");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            ActiveWindow = 1,
            Windows =
            [
                new SessionWindow
                {
                    Active = 1,
                    Tabs =
                    [
                        new SessionTab { Path = fileA, Caret = 3 },
                        new SessionTab { Content = "win one unsaved", Caret = 4 },
                    ],
                },
                new SessionWindow
                {
                    Tabs = [new SessionTab { Path = fileB, Caret = 6 }],
                },
            ],
        }.Save();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var first = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(first, fgBefore);
                Assert.NotNull(first);
                Assert.Equal(2, WaitForWindowCount(app, automation, 2).Length);
                Window? one = null;
                Window? two = null;
                bool identified = Retry.While(
                    () =>
                    {
                        Window[] found = app.GetAllTopLevelWindows(automation);
                        if (found.Length != 2)
                        {
                            return false;
                        }

                        Window? match = found.FirstOrDefault(w => TabItems(w).Any(t => string.Equals(t.Name, TabAccessibilityName.For("wina.txt", isDirty: false), StringComparison.Ordinal)));
                        if (match is null)
                        {
                            return false;
                        }

                        one = match;
                        two = found.First(w => !w.Properties.NativeWindowHandle.Value.Equals(match.Properties.NativeWindowHandle.Value));
                        return true;
                    },
                    ok => !ok,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.True(identified);
                Assert.NotNull(one);
                Assert.NotNull(two);
                UiForeground.PlaceForBackground(one);
                UiForeground.PlaceForBackground(two);
                Assert.Equal(2, TabItems(one).Count);
                Assert.Contains("win one unsaved", BoxText(one), StringComparison.Ordinal);
                Assert.Single(TabItems(two));
                WaitForTabName(two, 0, TabAccessibilityName.For("winb.txt", isDirty: false));

                // Non-last close drops the closing window's tabs (stock:
                // nothing merges); the survivor alone snapshots.
                two.Close();
                Assert.Single(WaitForWindowCount(app, automation, 1));
                SessionData mid = SessionData.Load();
                SessionWindow survivor = Assert.Single(mid.Windows);
                Assert.Equal(2, survivor.Tabs.Count);
                Assert.Equal(fileA, survivor.Tabs[0].Path);
                CloseAll(app, automation);
            }

            SessionData snap = SessionData.Load();
            Assert.Equal(2, Assert.Single(snap.Windows).Tabs.Count);

            nint fgBefore2 = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore2);
                Assert.NotNull(window);
                try
                {
                    Assert.Single(app.GetAllTopLevelWindows(automation));
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 0, TabAccessibilityName.For("wina.txt", isDirty: false));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void TabCloseRecordsRecentsNewestFirstCappedAtTen()
    {
        string dir = NewTempDir();
        var files = new List<string>();
        for (int i = 1; i <= 12; i++)
        {
            string file = Path.Combine(dir, $"f{i:00}.txt");
            File.WriteAllText(file, $"cap {i}");
            files.Add(file);
        }

        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows =
            [
                new SessionWindow
                {
                    Tabs = files.Select(f => new SessionTab { Path = f, Caret = 0 }).ToList(),
                },
            ],
        }.Save();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(12, WaitForTabCount(window, 12));
                    for (int left = 11; left >= 0; left--)
                    {
                        UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                        Assert.Equal(left, WaitForTabCount(window, left));
                    }
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            List<string> recents = ShellSettings.Load().RecentFiles;
            Assert.Equal(10, recents.Count);
            Assert.Equal(files[11], recents[0]);
            Assert.Equal(files[2], recents[^1]);
            Assert.DoesNotContain(files[0], recents);
            Assert.DoesNotContain(files[1], recents);
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void WindowCloseRecordsNoRecent()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "zulu.txt");
        File.WriteAllText(file, "zulu");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Caret = 1 }] }],
        }.Save();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            Assert.Empty(ShellSettings.Load().RecentFiles);
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    // Selects tab i, parks its caret `back` chars from the end, returns the
    // expected offset from the live text length.
    static int PositionCaretFromEnd(Window window, int index, int back)
    {
        SelectTab(window, index);
        Thread.Sleep(400);
        var box = ContentBox(window);
        box.Focus();
        Thread.Sleep(150);
        using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
        {
            Keyboard.Press(VirtualKeyShort.END);
        }

        Thread.Sleep(100);
        for (int i = 0; i < back; i++)
        {
            Keyboard.Press(VirtualKeyShort.LEFT);
            Thread.Sleep(50);
        }

        return ContentBox(window).Text.Length - back;
    }

    // Phase 3 uses "Z": U and B already hold a phase-1 "Q", so a second
    // "Q" would find the old one first.
    static void AssertTypeLandsAt(Window window, int index, int want, string marker)
    {
        SelectTab(window, index);
        Thread.Sleep(400);
        ContentBox(window).Focus();
        Thread.Sleep(150);
        Keyboard.Type(marker);
        Thread.Sleep(200);
        Assert.Equal(want, ContentBox(window).Text.IndexOf(marker[0], StringComparison.Ordinal));
    }

    static string BoxText(Window window) => ContentBox(window).Text ?? string.Empty;

    // WinUI boxes report lone \r separators through UIA; files hold \n.
    static string NormalizeBreaks(string text) => text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static Application LaunchApp()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return Application.Launch(appPath);
    }

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        // Session seeds land after this call; the delete keeps cases that
        // assert absence (fresh mode, clean profile) honest.
        SessionData.Delete();
    }


    static TextBox ContentBox(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static AutomationElement TabItemAt(Window window, int index)
    {
        var items = Retry.While(
            () => TabItems(window),
            found => found.Count <= index,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result ?? [];
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        return items[index];
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
    }

    // Tab names propagate to UIA asynchronously after a restore fills the
    // boxes, so name assertions wait like TabBarTests does.
    static void WaitForTabName(Window window, int index, string expected)
    {
        string? NameAt()
        {
            var found = TabItems(window);
            return found.Count > index ? found[index].Name : null;
        }

        var result = Retry.While(
            NameAt,
            name => name != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.Equal(expected, result);
    }

    // Selection lands asynchronously after a click, and the missing-file
    // notice keys off activation: wait for the select first, so a missed
    // select fails here naming the select instead of at the dialog wait.
    static void WaitForTabSelected(Window window, int index)
    {
        bool IsSelected()
        {
            var found = TabItems(window);
            return found.Count > index
                && found[index].Patterns.SelectionItem.PatternOrDefault?.IsSelected == true;
        }

        var result = Retry.While(
            IsSelected,
            selected => !selected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.True(result, $"tab {index} never selected after click");
    }

    // Tab switches drive the SelectionItem pattern, never the cursor:
    // review round 2 caught real clicks missing (wrong-tab landings
    // that failed caret asserts and starved the lazy notice), so the
    // cursor is out. Same shape as TabBarTests.SelectTab.
    static void SelectTab(Window window, int index)
    {
        var pattern = TabItemAt(window, index).Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
    }

    static Window[] WaitForWindowCount(Application app, UIA3Automation automation, int expected)
    {
        var result = Retry.While(
            () => app.GetAllTopLevelWindows(automation),
            found => found.Length != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result ?? [];
    }

    static void CloseAll(Application app, UIA3Automation automation)
    {
        foreach (var window in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                // Already gone; the exit wait below is the real assertion.
            }
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!app.HasExited)
        {
            app.Kill();
        }
    }
}
