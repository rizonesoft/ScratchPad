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

// D01 T02 §1: the full Notepad menu bar. Structure (labels, order,
// enablement) is pinned against the stock captures; every live item
// invokes its handler; live shortcuts are driven by keyboard
// (accelerator text itself is not UIA-readable; pending items'
// shortcuts ride the captures); pending-owner items assert disabled;
// Bing items assert present and enabled but never clicked (a click
// would open the operator's browser).
[Collection("UI tests")]
public sealed class MenuBarTests
{
    static readonly string[] FileLabels =
    [
        "New tab", "New window", "New Markdown tab", "Open", "Recent", "Save",
        "Save as", "Save all", "Page setup", "Print", "Close tab",
        "Close window", "Exit",
    ];

    // MenuFlyoutSeparator exposes no UIA element (probed 2026-09-16: the
    // tree holds items only), so the arrays pin labels and order; the
    // separators stay XAML-declared and screenshot-visible.
    static readonly string[] EditLabels =
    [
        "Undo", "Cut", "Copy", "Paste", "Delete", "Clear formatting",
        "Search with Bing", "Define with Bing", "Find", "Find next",
        "Find previous", "Replace", "Go to", "Select all", "Time/Date",
        "Font",
    ];

    static readonly string[] ViewLabels =
    [
        "Zoom", "Status bar", "Word wrap", "Markdown",
    ];

    static readonly string[] ToolsLabels =
    [
        "Statistics", "Snapshots", "Templates", "Export", "Lock file",
    ];

    [Fact]
    public void MenuStructureMatchesStockCaptures()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(
                    ["File", "Edit", "View", "Tools"],
                    TopLabels(window));
                Assert.Equal(FileLabels, OpenMenuLabels(window, "MenuFile"));
                Assert.Equal(EditLabels, OpenMenuLabels(window, "MenuEdit"));
                Assert.Equal(ViewLabels, OpenMenuLabels(window, "MenuView"));
                Assert.Equal(ToolsLabels, OpenMenuLabels(window, "MenuTools"));
                Assert.Equal(
                    ["Zoom in", "Zoom out", "Restore default zoom"],
                    OpenSubmenuLabels(window, "MenuView", "MenuViewZoom"));
                Assert.Equal(
                    ["Formatted", "Syntax"],
                    OpenSubmenuLabels(window, "MenuView", "MenuViewMarkdown"));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void PendingOwnerItemsStayDisabled()
    {
        (string Top, string[] Ids)[] menus =
        [
            ("MenuFile", ["MenuFileNewMarkdownTab", "MenuFilePageSetup", "MenuFilePrint"]),
            (
                "MenuEdit",
                [
                    "MenuEditUndo", "MenuEditCut", "MenuEditCopy",
                    "MenuEditPaste", "MenuEditDelete", "MenuEditClearFormatting",
                    "MenuEditFind", "MenuEditFindNext", "MenuEditFindPrevious",
                    "MenuEditReplace", "MenuEditGoTo", "MenuEditSelectAll",
                    "MenuEditTimeDate",
                ]
            ),
            ("MenuView", ["MenuViewStatusBar", "MenuViewWordWrap"]),
        ];
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                foreach (var (top, ids) in menus)
                {
                    OpenMenu(window, top);
                    foreach (string id in ids)
                    {
                        var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                        Assert.NotNull(item);
                        Assert.False(item.IsEnabled, id);
                    }

                    DismissMenu();
                }

                OpenMenu(window, "MenuView");
                foreach (string id in new[] { "MenuViewStatusBar", "MenuViewWordWrap" })
                {
                    var toggle = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                    Assert.NotNull(toggle);
                    Assert.True(toggle.Patterns.Toggle.IsSupported, id);
                    Assert.Equal(
                        FlaUI.Core.Definitions.ToggleState.Off,
                        toggle.Patterns.Toggle.Pattern.ToggleState);
                }

                DismissMenu();
                OpenMenu(window, "MenuView");
                OpenSubmenu(window, "MenuViewZoom");
                foreach (string id in new[] { "MenuViewZoomIn", "MenuViewZoomOut", "MenuViewZoomRestore" })
                {
                    var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                    Assert.NotNull(item);
                    Assert.False(item.IsEnabled, id);
                }

                DismissMenu();
                DismissMenu();
                OpenMenu(window, "MenuView");
                OpenSubmenu(window, "MenuViewMarkdown");
                foreach (string id in new[] { "MenuViewMarkdownFormatted", "MenuViewMarkdownSyntax" })
                {
                    var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                    Assert.NotNull(item);
                    Assert.False(item.IsEnabled, id);
                }

                DismissMenu();
                DismissMenu();
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void LiveItemsStayEnabledAcrossStates()
    {
        string[] live =
        [
            "MenuFileNewTab", "MenuFileNewWindow", "MenuFileOpen",
            "MenuFileRecent", "MenuFileSave", "MenuFileSaveAs",
            "MenuFileSaveAll", "MenuFileCloseTab", "MenuFileCloseWindow",
            "MenuFileExit", "MenuEditSearchBing", "MenuEditDefineBing",
            "MenuEditFont",
            "MenuToolsStats", "MenuToolsSnapshots", "MenuToolsTemplates",
            "MenuToolsExport", "MenuToolsLock",
        ];
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                AssertStates(window, live);
                SetBoxText(window, "some text here");
                AssertStates(window, live);
                SelectAll(window);
                AssertStates(window, live);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void AccessKeysOpenEachMenu()
    {
        (VirtualKeyShort Key, string Menu, string First)[] cases =
        [
            (VirtualKeyShort.KEY_F, "MenuFile", "MenuFileNewTab"),
            (VirtualKeyShort.KEY_E, "MenuEdit", "MenuEditUndo"),
            (VirtualKeyShort.KEY_V, "MenuView", "MenuViewZoom"),
            (VirtualKeyShort.KEY_T, "MenuTools", "MenuToolsStats"),
        ];
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                window.Focus();
                Thread.Sleep(150);
                foreach (var (key, menu, first) in cases)
                {
                    using (Keyboard.Pressing(VirtualKeyShort.ALT))
                    {
                        Keyboard.Press(key);
                    }

                    var item = Retry.WhileNull(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId(first)),
                        TimeSpan.FromSeconds(5),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.NotNull(item);
                    DismissMenu();
                    Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId(first)));
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void FileMenuLiveAcceleratorsWork()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Press(window, VirtualKeyShort.KEY_N, withControl: true);
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    Press(window, VirtualKeyShort.KEY_O, withControl: true);
                    var open = WaitForNativeModal(window, "Open");
                    CancelNativeModal(window, open, "Open");
                    SetBoxText(window, "accel work");
                    Press(window, VirtualKeyShort.KEY_S, withControl: true, withShift: true);
                    var saveAs = WaitForNativeModal(window, "Save As");
                    try
                    {
                        Assert.Equal("accel work.txt", FileNameText(saveAs));
                    }
                    finally
                    {
                        CancelNativeModal(window, saveAs, "Save As");
                    }

                    Assert.Equal("accel work", BoxText(window));
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            SeedSettings(new ShellSettings { WhatsNewSeen = true });
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    SetBoxText(window, "accel close");
                    Press(window, VirtualKeyShort.KEY_W, withControl: true, withShift: true);
                    Assert.True(SpinWait.SpinUntil(() => app.HasExited, TimeSpan.FromSeconds(10)));
                    Assert.True(app.HasExited);
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window2 = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window2);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window2, 1));
                    Assert.Equal("accel close", BoxText(window2));
                }
                finally
                {
                    CloseApp(app, window2);
                }
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    static void AssertStates(Window window, string[] live)
    {
        // Per-menu lists with presence asserts: a silently skipped item
        // would pass without proving anything. View carries no live items
        // (every entry waits on its owner), so it is not opened here.
        (string Top, string[] Ids)[] menus =
        [
            (
                "MenuFile",
                [
                    "MenuFileNewTab", "MenuFileNewWindow", "MenuFileOpen",
                    "MenuFileRecent", "MenuFileSave", "MenuFileSaveAs",
                    "MenuFileSaveAll", "MenuFileCloseTab", "MenuFileCloseWindow",
                    "MenuFileExit",
                ]
            ),
            ("MenuEdit", ["MenuEditSearchBing", "MenuEditDefineBing"]),
            (
                "MenuTools",
                [
                    "MenuToolsStats", "MenuToolsSnapshots", "MenuToolsTemplates",
                    "MenuToolsExport", "MenuToolsLock",
                ]
            ),
        ];
        foreach (var (top, ids) in menus)
        {
            OpenMenu(window, top);
            foreach (string id in ids)
            {
                Assert.Contains(id, live);
                var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                Assert.NotNull(item);
                Assert.True(item.IsEnabled, id);
            }

            DismissMenu();
        }
    }

    [Fact]
    public void FileNewTabOpensAndFocusesTab()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                ClickMenuItem(window, "MenuFile", "MenuFileNewTab");
                Assert.Equal(2, WaitForTabCount(window, 2));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void FileNewWindowOpensSecondWindow()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                ClickMenuItem(window, "MenuFile", "MenuFileNewWindow");
                var both = Retry.While(
                    () => app.GetAllTopLevelWindows(automation).ToList().Count,
                    count => count != 2,
                    TimeSpan.FromSeconds(15),
                    TimeSpan.FromMilliseconds(500));
                Assert.Equal(2, both.Result);
                var windows = app.GetAllTopLevelWindows(automation).ToList();
                var other = windows.First(w => w.Properties.NativeWindowHandle.Value != window.Properties.NativeWindowHandle.Value);
                other.Close();
                var back = Retry.While(
                    () => app.GetAllTopLevelWindows(automation).ToList().Count,
                    count => count != 1,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250));
                Assert.Equal(1, back.Result);
            }
            finally
            {
                CloseAllWindows(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void FileOpenShowsPickerWithEncodingList()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                ClickMenuItem(window, "MenuFile", "MenuFileOpen");
                var dialog = WaitForNativeModal(window, "Open");
                try
                {
                    var combo = FindEncodingCombo(dialog);
                    Assert.NotNull(combo);
                    Assert.Equal(
                        ["Auto-Detect", "ANSI", "UTF-16 LE", "UTF-16 BE", "UTF-8", "UTF-8 with BOM"],
                        EncodingComboItems(dialog, combo));
                    Assert.Equal("Auto-Detect", ComboValue(combo));
                    var filter = dialog.FindFirstDescendant(
                        cf => cf.ByControlType(ControlType.ComboBox).And(cf.ByName("Files of type:")));
                    Assert.NotNull(filter);
                    Assert.Equal("Text documents (*.txt)", ComboValue(filter));
                }
                finally
                {
                    CancelNativeModal(window, dialog, "Open");
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void FileOpenLoadsFileWithForcedEncoding()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = Path.Combine(dir, "forced1252.txt");
            // Lone 0xE9: invalid UTF-8, so forced UTF-8 must decode it to
            // U+FFFD (a u8 literal would emit the two-byte form C3 A9).
            File.WriteAllBytes(file, [0x63, 0x61, 0x66, 0xE9, 0x20, 0x74, 0x75, 0x6C, 0x69, 0x70, 0x73]);
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                ClickMenuItem(window, "MenuFile", "MenuFileOpen");
                var dialog = WaitForNativeModal(window, "Open");
                SetFileNameText(dialog, file);
                SelectEncoding(dialog, "UTF-8");
                ClickDialogButton(dialog, "Open");
                WaitForNativeModalGone(window, "Open");
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Assert.Contains("�", BoxText(window), StringComparison.Ordinal);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileOpenOpensExactlyOneFile()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SeedFile(dir, "single-a.txt", "alpha");
            SeedFile(dir, "single-b.txt", "beta");
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                ClickMenuItem(window, "MenuFile", "MenuFileOpen");
                var dialog = WaitForNativeModal(window, "Open");
                var combo = dialog.FindFirstDescendant(
                    cf => cf.ByControlType(ControlType.ComboBox).And(cf.ByName("File name:")));
                Assert.NotNull(combo);
                var edit = combo.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit))?.AsTextBox();
                Assert.NotNull(edit);
                edit.Focus();
                Thread.Sleep(200);
                edit.Text = dir;
                Thread.Sleep(300);
                Keyboard.Press(VirtualKeyShort.ENTER);
                var first = Retry.WhileNull(
                    () =>
                    {
                        try
                        {
                            return dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem))
                                .FirstOrDefault(i => i.Properties.Name.ValueOrDefault == "single-a.txt");
                        }
                        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                        {
                            return null;
                        }
                    },
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(500)).Result;
                Assert.NotNull(first);
                var select = first.Patterns.SelectionItem.PatternOrDefault;
                Assert.NotNull(select);
                select.Select();
                first.Focus();
                Thread.Sleep(200);
                using (Keyboard.Pressing(VirtualKeyShort.SHIFT))
                {
                    Keyboard.Press(VirtualKeyShort.DOWN);
                }

                Thread.Sleep(300);
                ClickDialogButton(dialog, "Open");
                WaitForNativeModalGone(window, "Open");
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Assert.True(BoxText(window) is "alpha" or "beta", BoxText(window));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileOpenMissingNameOffersCreate()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string missing = Path.Combine(dir, "missing.txt");
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                ClickMenuItem(window, "MenuFile", "MenuFileOpen");
                var dialog = WaitForNativeModal(window, "Open");
                SetFileNameText(dialog, missing);
                ClickDialogButton(dialog, "Open");
                WaitForNativeModalGone(window, "Open");
                var offer = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("CreateFileDialog")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(offer);
                Assert.Contains(missing, DialogText(offer), StringComparison.Ordinal);
                var no = offer.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("No")));
                Assert.NotNull(no);
                no.AsButton().Invoke();
                var gone = Retry.While(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("CreateFileDialog")),
                    el => el is not null,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250));
                Assert.Null(gone.Result);
                Assert.Equal(1, WaitForTabCount(window, 1));
                Assert.False(File.Exists(missing));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileSaveWritesPathedTabInPlace()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "saveme.txt", "original");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "edited body");
                ClickMenuItem(window, "MenuFile", "MenuFileSave");
                Assert.Equal("edited body", Retry.While(
                    () => File.ReadAllText(file),
                    text => text != "edited body",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileSaveOnUntitledOpensSaveAs()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                SetBoxText(window, "unsaved work");
                Press(window, VirtualKeyShort.KEY_S, withControl: true);
                var dialog = WaitForNativeModal(window, "Save As");
                try
                {
                    Assert.Equal("unsaved work.txt", FileNameText(dialog));
                }
                finally
                {
                    CancelNativeModal(window, dialog, "Save As");
                }

                Assert.Equal("unsaved work", BoxText(window));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileSaveAsWritesChosenPathAndEncoding()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                SetBoxText(window, "save as body");
                ClickMenuItem(window, "MenuFile", "MenuFileSaveAs");
                var dialog = WaitForNativeModal(window, "Save As");
                string target = Path.Combine(dir, "savedas.txt");
                SetFileNameText(dialog, target);
                SelectEncoding(dialog, "UTF-16 LE");
                ClickDialogButton(dialog, "Save");
                WaitForNativeModalGone(window, "Save As");
                byte[] bytes = Retry.While(
                    () =>
                    {
                        try
                        {
                            return File.ReadAllBytes(target);
                        }
                        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                        {
                            return null;
                        }
                    },
                    found => found is null,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result!;
                Assert.Equal("save as body", System.Text.Encoding.Unicode.GetString(bytes));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileSaveAsPrefillsEncodingAndEol()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = Path.Combine(dir, "prefill.txt");
            File.WriteAllText(
                file,
                "crlf one\r\ncrlf two\r\n",
                new System.Text.UnicodeEncoding(bigEndian: false, byteOrderMark: false));
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                ClickMenuItem(window, "MenuFile", "MenuFileSaveAs");
                var dialog = WaitForNativeModal(window, "Save As");
                Assert.Equal("prefill.txt", FileNameText(dialog));
                var combo = FindEncodingCombo(dialog);
                Assert.NotNull(combo);
                Assert.Equal("UTF-16 LE", ComboValue(combo));
                string target = Path.Combine(dir, "prefilled.txt");
                SetFileNameText(dialog, target);
                ClickDialogButton(dialog, "Save");
                WaitForNativeModalGone(window, "Save As");
                byte[] bytes = Retry.While(
                    () =>
                    {
                        try
                        {
                            return File.ReadAllBytes(target);
                        }
                        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                        {
                            return null;
                        }
                    },
                    found => found is null,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result!;
                Assert.Equal("crlf one\r\ncrlf two\r\n", System.Text.Encoding.Unicode.GetString(bytes));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileSaveAllWalksDirtyTabs()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "first.txt", "one");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "one edited");
                SelectTab(window, 0);
                SetBoxText(window, "two new");
                Press(window, VirtualKeyShort.KEY_S, withControl: true, withAlt: true);
                string target = Path.Combine(dir, "second.txt");
                var dialog = WaitForNativeModal(window, "Save As");
                SetFileNameText(dialog, target);
                ClickDialogButton(dialog, "Save");
                WaitForNativeModalGone(window, "Save As");
                Assert.Equal("one edited", Retry.While(
                    () => File.ReadAllText(file),
                    text => text != "one edited",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result);
                Assert.Equal("two new", Retry.While(
                    () =>
                    {
                        try
                        {
                            return File.ReadAllText(target);
                        }
                        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                        {
                            return string.Empty;
                        }
                    },
                    text => text != "two new",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileRecentRendersListClearAndReopen()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "recent.txt", "remember me");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                CloseTabViaMenu(window);
                Assert.Equal(1, WaitForTabCount(window, 1));
                OpenMenu(window, "MenuFile");
                OpenSubmenu(window, "MenuFileRecent");
                var entry = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFileRecentEntry"));
                Assert.NotNull(entry);
                Assert.Equal("recent.txt", entry.Name);
                InvokeOrClick(entry);
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Assert.Equal("remember me", BoxText(window));
                CloseTabViaMenu(window);
                Assert.Equal(1, WaitForTabCount(window, 1));
                OpenMenu(window, "MenuFile");
                OpenSubmenu(window, "MenuFileRecent");
                ClickSubmenuItem(window, "MenuFileRecentClear");
                DismissMenu();
                Thread.Sleep(500);
                OpenMenu(window, "MenuFile");
                OpenSubmenu(window, "MenuFileRecent");
                var empty = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFileRecentEmpty"));
                Assert.NotNull(empty);
                Assert.Equal("No recent files", empty.Name);
                DismissMenu();
                DismissMenu();
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileRecentMissingReportsNotFound()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "gone.txt", "here then gone");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                CloseTabViaMenu(window);
                Assert.Equal(1, WaitForTabCount(window, 1));
                File.Delete(file);
                OpenMenu(window, "MenuFile");
                OpenSubmenu(window, "MenuFileRecent");
                var entry = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFileRecentEntry"));
                Assert.NotNull(entry);
                InvokeOrClick(entry);
                var failure = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("OpenFailureDialog")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(failure);
                Assert.Contains(
                    "The system cannot find the path specified.",
                    DialogText(failure),
                    StringComparison.Ordinal);
                var ok = failure.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("OK")));
                Assert.NotNull(ok);
                ok.AsButton().Invoke();
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileCloseTabFollowsPrompt()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                SetBoxText(window, "dirty close me");
                CloseTabViaMenu(window);
                var prompt = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(prompt);
                var dont = prompt.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("Don't save")));
                Assert.NotNull(dont);
                dont.AsButton().Invoke();
                Assert.Equal(0, WaitForTabCount(window, 0));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileCloseWindowPreservesSilently()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                SetBoxText(window, "window close body");
                ClickMenuItem(window, "MenuFile", "MenuFileCloseWindow");
                Assert.True(SpinWait.SpinUntil(() => app.HasExited, TimeSpan.FromSeconds(10)));
            }

            using var app2 = LaunchApp();
            using var automation2 = new UIA3Automation();
            var window2 = UiApp.Attach(app2, automation2, TimeSpan.FromSeconds(30));
            Assert.NotNull(window2);
            try
            {
                Assert.Equal(1, WaitForTabCount(window2, 1));
                Assert.Equal("window close body", BoxText(window2));
            }
            finally
            {
                CloseApp(app2, window2);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FileExitClosesApp()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            ClickMenuItem(window, "MenuFile", "MenuFileExit");
            Assert.True(SpinWait.SpinUntil(() => app.HasExited, TimeSpan.FromSeconds(10)));
            Assert.True(app.HasExited);
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void EditBingItemsPresentEnabledAndUnclicked()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenMenu(window, "MenuEdit");
                foreach (string id in new[] { "MenuEditSearchBing", "MenuEditDefineBing" })
                {
                    var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                    Assert.NotNull(item);
                    Assert.True(item.IsEnabled, id);
                }

                DismissMenu();
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void ToolsMenuInvokesStats() => OpenToolsDialog("MenuToolsStats", "StatsDialog");

    [Fact]
    public void ToolsMenuInvokesSnapshots() => OpenToolsDialog("MenuToolsSnapshots", "SnapshotsDialog");

    [Fact]
    public void ToolsMenuInvokesTemplates() => OpenToolsDialog("MenuToolsTemplates", "TemplatesDialog");

    [Fact]
    public void ToolsMenuInvokesExport() => OpenToolsDialog("MenuToolsExport", "ExportDialog");

    [Fact]
    public void ToolsMenuInvokesLock() => OpenToolsDialog("MenuToolsLock", "LockDialog");

    static void OpenToolsDialog(string itemId, string dialogId)
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "tools.txt", "tool body here");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                ClickMenuItem(window, "MenuTools", itemId);
                var found = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(found);
                var close = found.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton()
                    ?? found.FindFirstDescendant(cf => cf.ByName("Cancel"))?.AsButton();
                Assert.NotNull(close);
                close.Invoke();
                var gone = Retry.While(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)),
                    el => el is not null,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250));
                Assert.Null(gone.Result);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    static List<string> TopLabels(Window window)
    {
        var bar = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuRegion"));
        Assert.NotNull(bar);
        return bar.FindAllChildren(cf => cf.ByControlType(ControlType.MenuItem)).Select(m => m.Name).ToList();
    }

    static void OpenMenu(Window window, string topId)
    {
        // Foreground first: a click into an inactive window's menu is eaten
        // by activation instead of dispatching (Tools dialog no-show).
        // Then Escape to a known-closed state: Invoke toggles, so opening
        // over a lingering menu shuts it and the follow-up click eats
        // itself on the closing animation (Recent close2 no-op).
        window.Focus();
        Thread.Sleep(150);
        DismissMenu();
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
    }

    static void OpenSubmenu(Window window, string subId)
    {
        var sub = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(subId)),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(sub);
        if (sub.Patterns.ExpandCollapse.IsSupported)
        {
            sub.Patterns.ExpandCollapse.Pattern.Expand();
        }
        else
        {
            sub.Click();
        }

        Thread.Sleep(600);
    }

    static void DismissMenu()
    {
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(350);
    }

    static void ClickMenuItem(Window window, string topId, string itemId, bool expectClose = true)
    {
        OpenMenu(window, topId);
        ClickFoundItem(window, itemId);
        if (expectClose && !WaitForMenuClosed(window, itemId))
        {
            // One retry: a click eaten by a stale light-dismiss layer
            // leaves the menu open with no dispatch (Recent close2).
            OpenMenu(window, topId);
            ClickFoundItem(window, itemId);
            Assert.True(WaitForMenuClosed(window, itemId), $"menu item {itemId} never dispatched");
        }
    }

    // Handlers that block the UI thread on a synchronous native dialog:
    // pattern Invoke waits for the handler to return and times out, so
    // these two keep the mouse Click (async input). They never run after
    // a submenu click, so the stale-capture no-op cannot reach them.
    static readonly HashSet<string> MouseOnlyItems = new(["MenuFileOpen", "MenuFileSaveAs"]);

    static void ClickFoundItem(Window window, string itemId)
    {
        var item = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(itemId)),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(item);
        if (MouseOnlyItems.Contains(itemId))
        {
            item.Click();
        }
        else
        {
            InvokeOrClick(item);
        }

        Thread.Sleep(400);
    }

    static void InvokeOrClick(AutomationElement item)
    {
        // Invoke first: after a submenu mouse-click the pointer capture
        // goes stale and later menu mouse-clicks eat themselves despite
        // perfect hit-testing (probed 2026-09-16: Close tab onscreen,
        // enabled, FromPoint-clean, Click a no-op). Patterns are immune.
        if (item.Patterns.Invoke.IsSupported)
        {
            item.Patterns.Invoke.Pattern.Invoke();
        }
        else
        {
            item.Click();
        }
    }

    static bool WaitForMenuClosed(Window window, string itemId)
    {
        var deadline = DateTime.UtcNow.AddSeconds(2);
        while (DateTime.UtcNow < deadline)
        {
            AutomationElement? still;
            try
            {
                still = window.FindFirstDescendant(cf => cf.ByAutomationId(itemId));
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                return true;
            }

            if (still is null)
            {
                return true;
            }

            Thread.Sleep(200);
        }

        return false;
    }

    static void ClickSubmenuItem(Window window, string itemId)
    {
        var item = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(itemId)),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(item);
        InvokeOrClick(item);
        Thread.Sleep(400);
    }

    static void CloseTabViaMenu(Window window) => ClickMenuItem(window, "MenuFile", "MenuFileCloseTab");

    static List<string> OpenMenuLabels(Window window, string topId)
    {
        OpenMenu(window, topId);
        var names = window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem).Or(cf.ByControlType(ControlType.Separator)))
            .Where(m =>
            {
                try
                {
                    if (m.ControlType == ControlType.Separator)
                    {
                        return true;
                    }

                    if (m.IsOffscreen)
                    {
                        return false;
                    }

                    string id = m.Properties.AutomationId.ValueOrDefault ?? string.Empty;
                    return id.StartsWith(topId, StringComparison.Ordinal) && id.Length > topId.Length;
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return false;
                }
            })
            .Select(m => m.ControlType == ControlType.Separator ? string.Empty : m.Name)
            .ToList();
        DismissMenu();
        return names;
    }

    static List<string> OpenSubmenuLabels(Window window, string topId, string subId)
    {
        // The expanded children render in a separate popup, not under the
        // submenu element (probed 2026-09-16): collect window-wide.
        OpenMenu(window, topId);
        OpenSubmenu(window, subId);
        var names = window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem))
            .Where(m =>
            {
                try
                {
                    if (m.IsOffscreen)
                    {
                        return false;
                    }

                    string id = m.Properties.AutomationId.ValueOrDefault ?? string.Empty;
                    return id.StartsWith(subId, StringComparison.Ordinal) && id.Length > subId.Length;
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return false;
                }
            })
            .Select(m => m.Name)
            .ToList();
        DismissMenu();
        DismissMenu();
        return names;
    }

    static Window WaitForNativeModal(Window window, string title)
    {
        var modal = Retry.WhileNull(
            () =>
            {
                try
                {
                    return window.ModalWindows.FirstOrDefault(m => m.Title == title);
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return null;
                }
            },
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(modal);
        return modal;
    }

    static void WaitForNativeModalGone(Window window, string title)
    {
        // A transient COM error must not read as "gone" (that false-pass
        // hid the stuck Open dialog): errors keep polling, and absence
        // must hold twice in a row before it counts.
        int absent = 0;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            bool present;
            try
            {
                present = window.ModalWindows.Any(m => m.Title == title);
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                present = true;
            }

            if (!present)
            {
                absent++;
                if (absent >= 2)
                {
                    return;
                }
            }
            else
            {
                absent = 0;
            }

            Thread.Sleep(250);
        }

        bool stillPresent;
        try
        {
            stillPresent = window.ModalWindows.Any(m => m.Title == title);
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            stillPresent = true;
        }

        Assert.False(stillPresent, $"modal '{title}' still open");
    }

    static void CancelNativeModal(Window window, Window modal, string title)
    {
        ClickDialogButton(modal, "Cancel");
        WaitForNativeModalGone(window, title);
    }

    static void ClickDialogButton(Window modal, string name)
    {
        // Three 16px combo-arrow buttons are also named "Open" (probed
        // 2026-09-16); the accept/cancel buttons carry the stock dialog
        // ids IDOK=1 / IDCANCEL=2, so match the id, then confirm the name.
        string id = name == "Cancel" ? "2" : "1";
        var button = Retry.WhileNull(
            () =>
            {
                try
                {
                    return modal.FindAllDescendants(cf => cf.ByControlType(ControlType.Button))
                        .FirstOrDefault(b => b.Properties.AutomationId.ValueOrDefault == id && !b.IsOffscreen);
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return null;
                }
            },
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(button);
        Assert.Equal(name, button.Name);
        button.AsButton().Invoke();
    }

    static void SetFileNameText(Window modal, string text)
    {
        var combo = modal.FindFirstDescendant(cf => cf.ByControlType(ControlType.ComboBox).And(cf.ByName("File name:")));
        Assert.NotNull(combo);
        var edit = combo.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit))?.AsTextBox();
        Assert.NotNull(edit);
        edit.Text = text;
        Thread.Sleep(300);
    }

    static string FileNameText(Window modal)
    {
        var combo = modal.FindFirstDescendant(cf => cf.ByControlType(ControlType.ComboBox).And(cf.ByName("File name:")));
        Assert.NotNull(combo);
        var edit = combo.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit))?.AsTextBox();
        Assert.NotNull(edit);
        return edit.Text ?? string.Empty;
    }

    static AutomationElement? FindEncodingCombo(Window modal)
    {
        // The custom combo is labelled "Encoding:", matching stock.
        return modal.FindAllDescendants(cf => cf.ByControlType(ControlType.ComboBox))
            .FirstOrDefault(c =>
            {
                try
                {
                    return c is not null && c.Properties.Name.ValueOrDefault == "Encoding:";
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return false;
                }
            }, null);
    }

    static void ExpandCombo(AutomationElement combo)
    {
        if (combo.Patterns.ExpandCollapse.IsSupported)
        {
            combo.Patterns.ExpandCollapse.Pattern.Expand();
        }
        else
        {
            combo.Click();
        }

        Thread.Sleep(700);
    }

    static List<AutomationElement> ComboDropItems(AutomationElement combo)
    {
        // Scoped to the combo: the dialog's file view holds ListItems too.
        var found = Retry.While(
            () =>
            {
                try
                {
                    return combo.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem)).ToList();
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return new List<AutomationElement>();
                }
            },
            list => list.Count == 0,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250));
        return found.Result ?? new List<AutomationElement>();
    }

    static string ComboValue(AutomationElement combo)
    {
        try
        {
            return combo.Patterns.Value.Pattern.Value ?? string.Empty;
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            return string.Empty;
        }
    }

    static string DialogText(AutomationElement dialog)
    {
        return string.Join(
            "\n",
            dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
                .Select(el =>
                {
                    try
                    {
                        return el.Properties.Name.ValueOrDefault ?? string.Empty;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        return string.Empty;
                    }
                })
                .Where(text => text.Length > 0));
    }

    static List<string> EncodingComboItems(Window modal, AutomationElement combo)
    {
        ExpandCombo(combo);
        var names = ComboDropItems(combo)
            .Select(i =>
            {
                try
                {
                    return i.Properties.Name.ValueOrDefault ?? string.Empty;
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return string.Empty;
                }
            })
            .Where(n => n.Length > 0)
            .ToList();
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(350);
        return names;
    }

    static void SelectEncoding(Window modal, string name)
    {
        var combo = FindEncodingCombo(modal);
        Assert.NotNull(combo);
        ExpandCombo(combo);
        var item = ComboDropItems(combo)
            .FirstOrDefault(i =>
            {
                try
                {
                    return i.Properties.Name.ValueOrDefault == name;
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return false;
                }
            });
        Assert.NotNull(item);
        if (item.Patterns.SelectionItem.IsSupported)
        {
            item.Patterns.SelectionItem.Pattern.Select();
        }
        else
        {
            item.Click();
        }

        Thread.Sleep(400);
    }

    static void SelectTab(Window window, int index)
    {
        var items = window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        var pattern = items[index].Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
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

    static void SetBoxText(Window window, string text)
    {
        ContentBox(window).Text = text;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            if (string.Equals(ContentBox(window).Text, text, StringComparison.Ordinal))
            {
                return;
            }

            Thread.Sleep(100);
        }

        Assert.Equal(text, ContentBox(window).Text);
    }

    static string BoxText(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box.Text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);
    }

    static void SelectAll(Window window)
    {
        window.Focus();
        Thread.Sleep(150);
        using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
        {
            Keyboard.Press(VirtualKeyShort.KEY_A);
        }

        Thread.Sleep(250);
    }

    static int WaitForTabCount(Window window, int expected)
    {
        // lastValueOnTimeout: without it a timeout reports default(int)
        // instead of the stuck count (that 0 hid two real failures).
        var result = Retry.While(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList().Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
    }

    static void Press(Window window, VirtualKeyShort key, bool withControl, bool withShift = false, bool withAlt = false)
    {
        window.Focus();
        Thread.Sleep(150);
        var mods = new List<VirtualKeyShort>();
        if (withControl)
        {
            mods.Add(VirtualKeyShort.CONTROL);
        }

        if (withShift)
        {
            mods.Add(VirtualKeyShort.SHIFT);
        }

        if (withAlt)
        {
            mods.Add(VirtualKeyShort.ALT);
        }

        if (mods.Count > 0)
        {
            using (Keyboard.Pressing(mods.ToArray()))
            {
                Keyboard.Press(key);
            }
        }
        else
        {
            Keyboard.Press(key);
        }

        Thread.Sleep(250);
    }

    static string AppExePath()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return appPath;
    }

    static Application LaunchApp() => Application.Launch(AppExePath());

    static Application LaunchAppWithArgs(string args) => Application.Launch(AppExePath(), args);

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        SessionData.Delete();
    }

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static string SeedFile(string dir, string name, string content)
    {
        string path = Path.Combine(dir, name);
        File.WriteAllText(path, content);
        return path;
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    static void CloseAllWindows(Application app, UIA3Automation automation)
    {
        foreach (var w in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                w.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException or System.Runtime.InteropServices.COMException)
            {
                // Best-effort: the Kill below is the guarantee. A COM
                // timeout here once skipped the reap and poisoned 13 tests
                // through single-instance redirect (2026-09-16 cascade).
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

        Assert.True(app.HasExited, "app did not exit after Close");
    }

    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException or System.Runtime.InteropServices.COMException)
        {
            // Best-effort: the Kill below is the guarantee. A COM
            // timeout here once skipped the reap and poisoned 13 tests
            // through single-instance redirect (2026-09-16 cascade).
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

        Assert.True(app.HasExited, "app did not exit after Close");
    }
}
