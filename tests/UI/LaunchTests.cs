using System.Runtime.InteropServices;
using System.Diagnostics;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Microsoft.Win32;
using Notepad.Core;
using Windows.UI.StartScreen;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// D01 T01 §8: command-line launch, single-instance redirect, the missing
// offer, failure rendering, print exit, the double-click command, and the
// association cycle. These tests require no running app instance (the
// single-instance key would redirect their launches); the suite already
// assumes a quiet box. Each test purges launch drops in setup so a killed
// predecessor cannot inject stale files.
[Collection("UI tests")]
public sealed class LaunchTests
{
    readonly ITestOutputHelper output;

    public LaunchTests(ITestOutputHelper output) => this.output = output;

    [Fact]
    public void SingleFileLaunchOpensTab()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "launch8.txt");
        File.WriteAllText(file, "launch eight");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("launch8.txt", isDirty: false));
                SelectTab(window, 1);
                Assert.Equal("launch eight", BoxText(window));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void MultiFileLaunchOpensTabsInOneWindow()
    {
        string dir = NewTempDir();
        string first = Path.Combine(dir, "m81.txt");
        string second = Path.Combine(dir, "m82.txt");
        File.WriteAllText(first, "one");
        File.WriteAllText(second, "two");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{first}\" \"{second}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(3, WaitForTabCount(window, 3));
                Assert.Single(app.GetAllTopLevelWindows(automation));
                WaitForTabName(window, 1, TabAccessibilityName.For("m81.txt", isDirty: false));
                WaitForTabName(window, 2, TabAccessibilityName.For("m82.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void SecondLaunchRedirectsFileIntoFirst()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "redir8.txt");
        File.WriteAllText(file, "redirected");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var first = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                using var second = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                Assert.Single(first.GetAllTopLevelWindows(automation));
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("redir8.txt", isDirty: false));
                Assert.Empty(LaunchDrops.Drain());
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void BareSecondLaunchOpensNewWindow()
    {
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var first = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                using var second = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected bare launch did not exit");
                var windows = Retry.While(
                    () => first.GetAllTopLevelWindows(automation).ToList(),
                    found => found.Count != 2,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result ?? [];
                Assert.Equal(2, windows.Count);
                foreach (Window w in windows)
                {
                    UiForeground.Background(w, fgBefore);
                }
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    [Fact]
    public void MissingFileOfferNoCreatesNothing()
    {
        string dir = NewTempDir();
        string missing = Path.Combine(dir, "nope8.txt");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{missing}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "CreateFileDialog");
                string text = DialogText(dialog);
                Assert.Contains(missing, text, StringComparison.Ordinal);
                Assert.Contains("Do you want to create a new file?", text, StringComparison.Ordinal);
                AnswerDialog(window, dialog, "CreateFileDialog", "No");
                Assert.Equal(1, WaitForTabCount(window, 1));
                Assert.False(File.Exists(missing));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact(Skip = "QUARANTINED 2026-09-17 D01-T01-S7 save-prompt-dialog-null")]
    public void MissingFileOfferYesBindsTabAndSaveCreates()
    {
        string dir = NewTempDir();
        string missing = Path.Combine(dir, "yes8.txt");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{missing}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "CreateFileDialog");
                AnswerDialog(window, dialog, "CreateFileDialog", "Yes");
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("yes8.txt", isDirty: false));
                Assert.False(File.Exists(missing));
                SelectTab(window, 1);
                UiInput.AppendText(ContentBox(window), "bound eight");
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                var prompt = WaitForDialog(window, "SavePromptDialog");
                AnswerDialog(window, prompt, "SavePromptDialog", "Save");
                Assert.Equal("bound eight", WaitForFileContent(missing));
                Assert.Equal(1, WaitForTabCount(window, 1));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void MissingFileOfferEnterAcceptsAsYes()
    {
        // Fenced (grandfather §8): ENTER acceptance IS the point (audit keyboard).
        string dir = NewTempDir();
        string missing = Path.Combine(dir, "enter8.txt");
        SeedFresh();
        try
        {
            using var app = UiLaunch.LaunchAppWithArgs($"\"{missing}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "CreateFileDialog");
                dialog.Click();
                Thread.Sleep(500);
                for (int i = 0; i < 20; i++)
                {
                    if (window.FindFirstDescendant(cf => cf.ByAutomationId("CreateFileDialog")) is null)
                    {
                        break;
                    }

                    UiInput.PressKey(window, VirtualKeyShort.RETURN);
                    Thread.Sleep(500);
                }

                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("enter8.txt", isDirty: false));
                Assert.False(File.Exists(missing));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ForegroundDefaultsLandOnScreen()
    {
        // Regression (D00 T02 §18 R3-F1): a foreground first-window
        // birth with untouched defaults must land on-screen. Fresh
        // profiles saw nothing when BirthOrigin mapped defaults
        // off-screen unconditionally. Night-owed (D00-T02-S18-N1):
        // foreground steal, runs in the collector window.
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        // Clear before seeding (D00 T02 §18 C-I1): SeedFresh
        // maps defaults off-screen when the flag reads 1, so
        // seeding first would test the wrong setup under an
        // inherited flag.
        Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, null);
        SessionData.Delete();
        SeedFresh();
        try
        {
            using var app = UiLaunch.LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                nint hwnd = window.Properties.NativeWindowHandle.Value;
                int[]? rect = UiLaunchDiagnostics.WindowRect(hwnd);
                Assert.NotNull(rect);
                UiLaunch.ScreenBounds screen = UiLaunch.ReadVirtualScreen();
                Assert.True(
                    UiLaunch.WindowIntersects(screen, rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]),
                    $"foreground birth at {rect[0]},{rect[1]} misses the virtual screen");
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
            SessionData.Delete();
        }
    }

    [Fact(Skip = "QUARANTINED 2026-09-20 D01-T01-S4 locked-file-null")]
    public void LockedFileReportsLocked()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "locked8.txt");
        File.WriteAllText(file, "held");
        SeedFresh();
        try
        {
            using var hold = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "OpenFailureDialog");
                string lockedText = WaitForDialogText(dialog);
                Assert.Contains(OpenMessages.LockedText, lockedText, StringComparison.Ordinal);
                AnswerDialog(window, dialog, "OpenFailureDialog", "OK");
                Assert.Equal(1, WaitForTabCount(window, 1));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void OverLimitFileRefusesTooLarge()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "huge8.bin");
        CreateSparseFile(file, OpenOptions.DefaultMaxBytes + 1);
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "OpenFailureDialog");
                string largeText = WaitForDialogText(dialog);
                Assert.Contains(OpenMessages.TooLargeText, largeText, StringComparison.Ordinal);
                AnswerDialog(window, dialog, "OpenFailureDialog", "OK");
                Assert.Equal(1, WaitForTabCount(window, 1));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void LargeFileOpensResponsively()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "big8.txt");
        File.WriteAllText(file, new string('8', 4 * 1024 * 1024));
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("big8.txt", isDirty: false));
                SelectTab(window, 1);
                Assert.Equal(4 * 1024 * 1024, BoxText(window).Length);
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void OpenInNewWindowModeOpensSecondWindow()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "w8.txt");
        File.WriteAllText(file, "two");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh, OpenIn = OpenInRouting.NewWindow }, drainLaunchDrops: true);
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var first = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                using var second = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                var windows = Retry.While(
                    () => first.GetAllTopLevelWindows(automation).ToList(),
                    found => found.Count != 2,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result ?? [];
                Assert.Equal(2, windows.Count);
                foreach (Window w in windows)
                {
                    UiForeground.Background(w, fgBefore);
                }

                SettleForProviders();
                // The file window is the one that is not the first window:
                // both hold exactly one tab, so a most-tabs pick ties and
                // falls back to enumeration (Z) order, which the background
                // move reshuffles (D00 T02 §8 item 10).
                nint firstHwnd = window.Properties.NativeWindowHandle.Value;
                var fileWindow = windows.Single(w => w.Properties.NativeWindowHandle.Value != firstHwnd);
                Assert.Equal(1, WaitForTabCount(fileWindow, 1));
                WaitForTabName(fileWindow, 0, TabAccessibilityName.For("w8.txt", isDirty: false));
                Assert.Empty(LaunchDrops.Drain());
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FreshLaunchHoldsFilesInOneWindowInNewWindowMode()
    {
        string dir = NewTempDir();
        string first = Path.Combine(dir, "w81.txt");
        string second = Path.Combine(dir, "w82.txt");
        File.WriteAllText(first, "one");
        File.WriteAllText(second, "two");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh, OpenIn = OpenInRouting.NewWindow }, drainLaunchDrops: true);
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{first}\" \"{second}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(3, WaitForTabCount(window, 3));
                Assert.Single(app.GetAllTopLevelWindows(automation));
                WaitForTabName(window, 1, TabAccessibilityName.For("w81.txt", isDirty: false));
                WaitForTabName(window, 2, TabAccessibilityName.For("w82.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public async Task JumpListCommitsRecentsAndPinsFromStore()
    {
        string dir = NewTempDir();
        string pin = Path.Combine(dir, "pin8.txt");
        string rec = Path.Combine(dir, "rec8.txt");
        await File.WriteAllTextAsync(pin, "pinned");
        await File.WriteAllTextAsync(rec, "recent");
        var seeded = new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh };
        seeded.PinnedFiles.Add(pin);
        seeded.RecentFiles.Add(rec);
        seeded.RecentFiles.Add(pin);
        UiLaunch.SeedSettings(seeded, drainLaunchDrops: true);
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                string expected = JumpListFeed.Fingerprint(JumpListFeed.Build(seeded.PinnedFiles, seeded.RecentFiles));
                string? hash = null;
                for (int i = 0; i < 40 && string.IsNullOrEmpty(hash); i++)
                {
                    hash = ShellSettings.Load().JumpListHash;
                    if (string.IsNullOrEmpty(hash))
                    {
                        await Task.Delay(250);
                    }
                }

                Assert.Equal(expected, hash);
                SetCurrentProcessExplicitAppUserModelID(AppUserModelId);
                JumpList? list = null;
                for (int i = 0; i < 40 && (list is null || list.Items.Count == 0); i++)
                {
                    list = await JumpList.LoadCurrentAsync();
                    if (list.Items.Count == 0)
                    {
                        await Task.Delay(250);
                    }
                }

                Assert.NotNull(list);
                var pinEntry = list.Items.SingleOrDefault(item => item.DisplayName == "pin8.txt");
                Assert.NotNull(pinEntry);
                Assert.Equal(JumpListFeed.PinnedCategory, pinEntry.GroupName);
                Assert.Equal("\"" + pin + "\"", pinEntry.Arguments);
                var recEntry = list.Items.SingleOrDefault(item => item.DisplayName == "rec8.txt");
                Assert.NotNull(recEntry);
                Assert.Equal(JumpListFeed.RecentCategory, recEntry.GroupName);
                Assert.Equal("\"" + rec + "\"", recEntry.Arguments);
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // D01 T02 §5 absorbed PrintSeam: /p /pt print-then-close for real.
    // /p targets the OS default printer, discovered at runtime: exit 0
    // with no windows when one exists (plus a next-to-source PDF when the
    // default is Print to PDF), exit 2 naming the missing printer when
    // none exists. Either way no window may appear.
    [PrinterFact]
    public void PrintFlagPrintsThenCloses()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "print8.txt");
        File.WriteAllText(file, "print me");
        SeedFresh();
        try
        {
            string? def = DefaultPrinterName();
            (int exit, string stderr) = UiLaunch.RunHeadlessCapture($"/p \"{file}\"", TimeSpan.FromMinutes(2));
            if (def is null)
            {
                Assert.Equal(2, exit);
                Assert.Contains("not installed", stderr, StringComparison.OrdinalIgnoreCase);
            }
            else
            {
                Assert.Equal(0, exit);
                if (def.Equals("Microsoft Print to PDF", StringComparison.OrdinalIgnoreCase))
                {
                    Assert.True(File.Exists(Path.ChangeExtension(file, ".pdf")), "expected next-to-source PDF");
                }
            }

            Assert.Empty(RunningAppProcesses());
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // /pt to a bogus printer: the failure path reports on stderr, writes
    // nothing, and exits 2 (D01 T02 §5 item 3).
    [Fact]
    public void PrintToBogusPrinterExits2()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "print8.txt");
        File.WriteAllText(file, "print me");
        SeedFresh();
        try
        {
            (int exit, string stderr) = UiLaunch.RunHeadlessCapture($"/pt \"{file}\" \"NoSuchPrinter8\"", TimeSpan.FromSeconds(30));
            Assert.Equal(2, exit);
            Assert.Contains("NoSuchPrinter8", stderr, StringComparison.Ordinal);
            Assert.False(File.Exists(Path.ChangeExtension(file, ".pdf")), "failure must write nothing");
            Assert.Empty(RunningAppProcesses());
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void DoubleClickCommandOpensTab()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "dbl8.txt");
        File.WriteAllText(file, "double clicked");
        SeedFresh();
        try
        {
            string command = FileAssociation.OpenCommand(UiLaunch.AppExePath());
            int firstSpace = command.IndexOf(' ', StringComparison.Ordinal);
            string exe = command[..firstSpace].Trim('"');
            string args = command[(firstSpace + 1)..].Replace("%1", file, StringComparison.Ordinal);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithExe(exe, args);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("dbl8.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void AssociationVerbsCycleCleanly()
    {
        UiLaunch.RunHeadless("/unregister-associations", TimeSpan.FromSeconds(20));
        Dictionary<string, string?> before = SnapshotDefaults();
        try
        {
            Assert.Equal(0, UiLaunch.RunHeadless("/register-associations", TimeSpan.FromSeconds(20)));
            foreach (string ext in FileAssociation.ClaimedExtensions)
            {
                Assert.Equal(FileAssociation.ProgId, ReadDefault(FileAssociation.ExtensionKey(ext)));
            }

            Assert.False(string.IsNullOrEmpty(ReadDefault($@"Software\Classes\{FileAssociation.ProgId}\shell\open\command")));
            Assert.Equal(0, UiLaunch.RunHeadless("/unregister-associations", TimeSpan.FromSeconds(20)));
            Dictionary<string, string?> after = SnapshotDefaults();
            Assert.Equal(before, after);
            Assert.False(KeyExists($@"Software\Classes\{FileAssociation.ProgId}"));
            Assert.False(KeyExists(FileAssociation.BackupRoot));
        }
        finally
        {
            UiLaunch.RunHeadless("/unregister-associations", TimeSpan.FromSeconds(20));
        }
    }

    // Mirrors JumpListService.AppId (the app assembly is a black box to
    // these tests): the read-back below runs under the same identity
    // the app commits with.
    const string AppUserModelId = "Rizonesoft.ScratchPad";

    [System.Runtime.InteropServices.DllImport("shell32.dll", ExactSpelling = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    static extern void SetCurrentProcessExplicitAppUserModelID(string appId);


    static string? DefaultPrinterName()
    {
        string name = new System.Drawing.Printing.PrinterSettings().PrinterName;
        return string.IsNullOrEmpty(name) ? null : name;
    }

    static List<Process> RunningAppProcesses() =>
        Process.GetProcessesByName(Path.GetFileNameWithoutExtension(UiLaunch.AppExePath())).ToList();

    static bool WaitForExit(Application app, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        return app.HasExited;
    }

    static void SeedFresh() => UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh }, drainLaunchDrops: true);

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
    }

    static Dictionary<string, string?> SnapshotDefaults()
    {
        var snapshot = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (string ext in FileAssociation.ClaimedExtensions)
        {
            snapshot[ext] = ReadDefault(FileAssociation.ExtensionKey(ext));
        }

        return snapshot;
    }

    static string? ReadDefault(string keyPath)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
        return key?.GetValue(string.Empty) as string;
    }

    static bool KeyExists(string keyPath)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
        return key is not null;
    }

    static void CreateSparseFile(string path, long length)
    {
        string? root = Path.GetPathRoot(path);
        Assert.NotNull(root);
        Assert.Equal("NTFS", new DriveInfo(root).DriveFormat);
        IntPtr handle = CreateFileW(path, 0x40000000u, 0u, IntPtr.Zero, 2u, 0x80u, IntPtr.Zero);
        Assert.False(handle == IntPtr.Zero || handle == new IntPtr(-1));
        try
        {
            Assert.True(DeviceIoControl(handle, 0x900C4u, IntPtr.Zero, 0u, IntPtr.Zero, 0u, out _, IntPtr.Zero));
            Assert.True(SetFilePointerEx(handle, length, out _, 0u));
            Assert.True(SetEndOfFile(handle));
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    static AutomationElement WaitForDialog(Window window, string automationId)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
        SettleForProviders();
        return dialog;
    }

    // Provider settling (D01 T01 §8): a freshly appeared element answers
    // subtree queries (text, buttons, tab items) before its UIA providers
    // finish registering, and an early touch can stick that way for the
    // querying client (drives showed dialog text and buttons reading
    // empty when touched at birth but present a moment later, and tab
    // counts masking the same way). Callers wait out the race window
    // before their first subtree touch; the polls after stay adaptive.
    static void SettleForProviders() => Thread.Sleep(1500);

    // Polls dialog text until it renders (same budget shape as the
    // other waits): the container appears before its content does.
    static string WaitForDialogText(AutomationElement dialog)
    {
        string text = string.Empty;
        for (int i = 0; i < 40 && string.IsNullOrEmpty(text); i++)
        {
            text = DialogText(dialog);
            if (string.IsNullOrEmpty(text))
            {
                Thread.Sleep(250);
            }
        }

        return text;
    }

    static string DialogText(AutomationElement dialog)
    {
        var texts = dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
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
            });
        return string.Join(" // ", texts);
    }

    static void AnswerDialog(Window window, AutomationElement dialog, string automationId, string button)
    {
        var btn = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName(button))),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(btn);
        btn.AsButton().Invoke();
        var gone = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            found => found is not null,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250));
        Assert.Null(gone.Result);
    }

    static void SelectTab(Window window, int index)
    {
        var pattern = TabItemAt(window, index).Patterns.SelectionItem.PatternOrDefault;
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

    static string BoxText(Window window) => ContentBox(window).Text ?? string.Empty;

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static AutomationElement TabItemAt(Window window, int index)
    {
        var items = Retry.While(
            () => TabItems(window),
            found => found.Count <= index,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result ?? [];
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        return items[index];
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
    }

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
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result;
        Assert.Equal(expected, result);
    }

    // Polls a just-saved file until its bytes land: the save runs on
    // the UI thread after the prompt dismisses, so an immediate read
    // races the write (drives showed the file present within 250 ms).
    static string WaitForFileContent(string path)
    {
        for (int i = 0; i < 40; i++)
        {
            if (File.Exists(path))
            {
                string content = File.ReadAllText(path);
                if (content.Length > 0)
                {
                    return content;
                }
            }

            Thread.Sleep(250);
        }

        return File.Exists(path) ? File.ReadAllText(path) : string.Empty;
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

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool DeviceIoControl(IntPtr handle, uint code, IntPtr input, uint inputBytes, IntPtr output, uint outputBytes, out uint returned, IntPtr overlapped);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool SetFilePointerEx(IntPtr handle, long distance, out long position, uint method);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool SetEndOfFile(IntPtr handle);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool CloseHandle(IntPtr handle);

    // D00 T02 §26: a window birth sweeps only its own constructor-born
    // helpers. The first window's live File flyout (a popup HWND the
    // process owns) must keep its rect while a second window is born
    // through a redirected launch (open-in-new-window mode), which
    // touches neither window's UI; the pre-§26 sweep pinned every
    // non-main top-level window in the process, this popup included.
    [Fact]
    public void WindowBirthLeavesOtherWindowsHelpersInPlace()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "w26.txt");
        File.WriteAllText(file, "two");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh, OpenIn = OpenInRouting.NewWindow }, drainLaunchDrops: true);
        using var sweepLog = new SweepLogScope();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var first = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                nint firstMain = window.Properties.NativeWindowHandle.Value;

                // D00 T02 §34 item 3: WinUI creates its helper windows once per
                // UI thread, with the first window, so the first birth is where
                // constructor-born helpers exist; each still sits at its sweep
                // target, so narrowing never silently disabled placement.
                SweepLine own = sweepLog.ReadBirth(firstMain);
                Assert.True(own.Pinned.Count > 0, $"the first birth pinned no helper, so background placement is untested: {own.Raw}");
                // The expected set, read independently of the selection (§34
                // R1-F3): every window the sweep saw that the first main owns,
                // or that owns itself, and that is no main, must be pinned; a
                // helper the selection wrongly skipped fails here.
                foreach (nint hwnd in own.Skipped.Keys.Where(h => HelperNative.IsWindow(h)))
                {
                    nint rootOwner = HelperNative.GetAncestor(hwnd, 3);
                    bool main = HelperClass(hwnd) == "WinUIDesktopWin32WindowClass";
                    bool ownedHere = rootOwner == hwnd || rootOwner == firstMain;
                    Assert.False(ownedHere && !main && own.Skipped[hwnd] != "preexisting", $"the first birth skipped its own helper 0x{hwnd:X} ({own.Skipped[hwnd]}): {own.Raw}");
                }
                foreach (nint hwnd in own.Pinned)
                {
                    Assert.True(own.PinnedAt.TryGetValue(hwnd, out var at), $"the sweep logged no readback for helper 0x{hwnd:X}: {own.Raw}");
                    Assert.True(at.X == own.TargetX && at.Y == own.TargetY, $"the first window's helper 0x{hwnd:X} read back at ({at.X},{at.Y}) right after its pin, not the sweep target ({own.TargetX},{own.TargetY})");
                }

                HashSet<nint> before = HelperWindows(first.ProcessId).Keys.ToHashSet();
                var menu = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
                Assert.NotNull(menu);
                menu.Patterns.Invoke.Pattern.Invoke();
                Thread.Sleep(800);
                var helpers = HelperWindows(first.ProcessId).Where(kv => !before.Contains(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value);
                Assert.True(helpers.Count > 0, $"the first window's File flyout opened no helper window ({before.Count} helpers before)");

                // WinUI's popup host snaps a moved popup back to its anchor,
                // so a before/after rect can read unchanged while the sweep
                // moved it mid-birth; the location-change recorder sees
                // every move of the helpers while the birth runs.
                using var moves = new LocationRecorder((uint)first.ProcessId, helpers.Keys);
                // The test's own pre-birth set (§34 R2-F2): every window of
                // the process, visible or not, read before the second birth.
                HashSet<nint> preBirth = ProcessWindows(first.ProcessId);
                using var second = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                var windows = Retry.While(
                    () => first.GetAllTopLevelWindows(automation).ToList(),
                    found => found.Count != 2,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result ?? [];
                Assert.Equal(2, windows.Count);
                Thread.Sleep(800);

                // The observation barrier (D00 T02 §41 item 6): both mains'
                // UI threads have processed their queues, then every
                // location event already queued to the recorder drains.
                int drained = moves.DrainToBarrier(windows.Select(w => w.Properties.NativeWindowHandle.Value));
                output.WriteLine($"recorder drained {drained} event(s) at the barrier");
                var moved = moves.Stop();
                Assert.True(moves.Hooked, "the location-change recorder never hooked; the proof would read vacuous");
                Assert.True(moved.Count == 0, $"another window's birth moved this window's live helpers: {string.Join("; ", moved)}");
                var after = HelperWindows(first.ProcessId);
                foreach (var (hwnd, rect) in helpers)
                {
                    Assert.True(after.TryGetValue(hwnd, out HelperRect now), $"helper 0x{hwnd:X} closed before the birth settled; the premise needs it live");
                    Assert.True(rect.Left == now.Left && rect.Top == now.Top, $"helper 0x{hwnd:X} moved from ({rect.Left},{rect.Top}) to ({now.Left},{now.Top}) when another window was born");
                }

                // D00 T02 §34 item 5: the sweep's own decision, read from its
                // log, never rests on a missed WinEvent: the second birth
                // skipped every one of the first window's helpers.
                SweepLine birth = sweepLog.ReadBirthOtherThan(firstMain);
                foreach (nint hwnd in helpers.Keys)
                {
                    Assert.DoesNotContain(hwnd, birth.Pinned);
                    Assert.True(birth.Skipped.ContainsKey(hwnd), $"the second birth's sweep never considered helper 0x{hwnd:X}: {birth.Raw}");
                }

                // The second birth creates no top-level helper of its own (the
                // thread's helpers already exist), so it pins nothing.
                Assert.Empty(birth.Pinned);
                // Independently of the selection (§34 R2-F2): every handle the
                // log calls preexisting was in the test's own pre-birth set,
                // and every window born during the construction is a main or
                // another main's, never a skipped helper of this birth.
                foreach (var (hwnd, reason) in birth.Skipped)
                {
                    if (reason == "preexisting")
                    {
                        Assert.True(preBirth.Contains(hwnd), $"the sweep called 0x{hwnd:X} preexisting, but the test's own pre-birth set lacks it: {birth.Raw}");
                    }
                    else if (!preBirth.Contains(hwnd))
                    {
                        Assert.True(reason is "main" or "other-owner", $"a window born during the second construction, 0x{hwnd:X}, was skipped as {reason}: {birth.Raw}");
                    }
                }

                foreach (Window w in windows)
                {
                    UiForeground.Background(w, fgBefore);
                }
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // D00 T02 §41 item 4: a helper born after the sweep still lands at the
    // sweep target. The late-helper seam creates one hidden unowned popup
    // on the UI thread right after the sweep, on-screen at (100,100); the
    // delayed pass must pin it and log the readback.
    [Fact]
    public void HelperBornAfterTheSweepIsParkedByTheDelayedPass()
    {
        SeedFresh();
        using var sweepLog = new SweepLogScope();
        string? prior = Environment.GetEnvironmentVariable("SCRATCHPAD_TEST_LATE_HELPER");
        Environment.SetEnvironmentVariable("SCRATCHPAD_TEST_LATE_HELPER", "1");
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                nint main = window.Properties.NativeWindowHandle.Value;
                nint planted = sweepLog.ReadPlanted(main);
                Assert.True(planted != nint.Zero, $"the late-helper seam planted nothing for 0x{main:X}");
                SweepLine birth = sweepLog.ReadBirth(main);
                Assert.DoesNotContain(planted, birth.Pinned);
                SweepLine late = sweepLog.ReadLate(main);
                Assert.Equal(birth.Generation, late.Generation);
                Assert.Contains(planted, late.Pinned);
                Assert.True(late.PinnedAt.TryGetValue(planted, out var at) && at.X == late.TargetX && at.Y == late.TargetY, $"the late helper read back away from the target: {late.Raw}");
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable("SCRATCHPAD_TEST_LATE_HELPER", prior);
        }
    }

    // D00 T02 §41 item 9: the first birth's preexisting set, checked against
    // an outside observation. The hold seam stops the app just before its
    // first window; the test reads every window of the process from
    // outside, releases it, and requires the sweep's preexisting set to be
    // exactly that observation: nothing the app saw before its construction
    // escapes it, and nothing born during the construction hides in it.
    [Fact]
    public void FirstBirthPreexistingSetMatchesAnOutsideObservation()
    {
        SeedFresh();
        using var sweepLog = new SweepLogScope();
        string name = $"scratchpad-hold-{Guid.NewGuid():N}";
        using var held = new EventWaitHandle(false, EventResetMode.ManualReset, name + "-held");
        using var release = new EventWaitHandle(false, EventResetMode.ManualReset, name + "-release");
        string? prior = Environment.GetEnvironmentVariable(TestHold.Variable);
        Environment.SetEnvironmentVariable(TestHold.Variable, name);
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            Environment.SetEnvironmentVariable(TestHold.Variable, prior);
            Assert.True(held.WaitOne(TimeSpan.FromSeconds(30)), "the app never reached the hold before its first window");
            HashSet<nint> outside = ProcessWindows(app.ProcessId);
            Assert.True(release.Set());
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                nint main = window.Properties.NativeWindowHandle.Value;
                SweepLine birth = sweepLog.ReadBirth(main);
                var preexisting = birth.Skipped.Where(kv => kv.Value == "preexisting").Select(kv => kv.Key).ToHashSet();
                output.WriteLine($"outside {outside.Count} window(s), sweep preexisting {preexisting.Count}: {birth.Raw}");
                foreach (nint hwnd in outside.Where(h => HelperNative.IsWindow(h)))
                {
                    Assert.True(preexisting.Contains(hwnd), $"0x{hwnd:X} existed before the first construction (outside observation) but the sweep read it as {(birth.Skipped.TryGetValue(hwnd, out var r) ? r : birth.Pinned.Contains(hwnd) ? "pinned" : "unseen")}: {birth.Raw}");
                }

                foreach (nint hwnd in preexisting)
                {
                    Assert.True(outside.Contains(hwnd), $"the sweep read 0x{hwnd:X} as preexisting, but the outside observation before the construction never saw it: {birth.Raw}");
                }
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(TestHold.Variable, prior);
        }
    }

    // D00 T02 §34 item 2: a live owned dialog (the File > Open picker, a
    // real owned HWND unlike an in-window ContentDialog) keeps its rect
    // while another window is born. Fenced: the picker takes the
    // foreground. Night-owed D00-T02-S34-N1.
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void WindowBirthLeavesAnOwnedDialogInPlace()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "w34.txt");
        File.WriteAllText(file, "two");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh, OpenIn = OpenInRouting.NewWindow }, drainLaunchDrops: true);
        using var sweepLog = new SweepLogScope();
        try
        {
            using var first = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                nint firstMain = window.Properties.NativeWindowHandle.Value;
                HashSet<nint> before = HelperWindows(first.ProcessId).Keys.ToHashSet();
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileOpen");
                // Only the picker: a #32770 dialog whose root owner is the
                // first main, never a menu popup that also appeared; the
                // filter rides the retry so a popup cannot end the wait early
                // (§34 R1-F2, R2-F1).
                var dialogs = Retry.While(
                    () => HelperWindows(first.ProcessId).Where(kv => !before.Contains(kv.Key) && HelperClass(kv.Key) == "#32770" && HelperNative.GetAncestor(kv.Key, 3) == firstMain).ToDictionary(kv => kv.Key, kv => kv.Value),
                    found => found.Count == 0,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result ?? [];
                Assert.True(dialogs.Count > 0, "File > Open raised no #32770 dialog owned by the first main window");
                using var moves = new LocationRecorder((uint)first.ProcessId, dialogs.Keys);
                using var second = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                Thread.Sleep(1500);
                int drained = moves.DrainToBarrier(first.GetAllTopLevelWindows(automation).Select(w => w.Properties.NativeWindowHandle.Value));
                output.WriteLine($"recorder drained {drained} event(s) at the barrier");
                var moved = moves.Stop();
                Assert.True(moves.Hooked, "the location-change recorder never hooked; the proof would read vacuous");
                Assert.True(moved.Count == 0, $"another window's birth moved the owned dialog: {string.Join("; ", moved)}");
                SweepLine birth = sweepLog.ReadBirthOtherThan(firstMain);
                foreach (nint hwnd in dialogs.Keys)
                {
                    Assert.DoesNotContain(hwnd, birth.Pinned);
                }

                var cancel = Retry.WhileNull(
                    () => automation.GetDesktop().FindFirstDescendant(cf => cf.ByAutomationId("2").And(cf.ByControlType(FlaUI.Core.Definitions.ControlType.Button))),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250)).Result;
                cancel?.Patterns.Invoke.PatternOrDefault?.Invoke();
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // Every top-level window of the process, visible or not.
    static HashSet<nint> ProcessWindows(int pid)
    {
        var found = new HashSet<nint>();
        _ = HelperNative.EnumWindows((hwnd, param) =>
        {
            _ = param;
            _ = HelperNative.GetWindowThreadProcessId(hwnd, out uint owner);
            if (owner == (uint)pid)
            {
                _ = found.Add(hwnd);
            }

            return true;
        }, nint.Zero);
        return found;
    }

    static string HelperClass(nint hwnd)
    {
        var name = new char[256];
        int n = HelperNative.GetClassName(hwnd, name, name.Length);
        return n > 0 ? new string(name, 0, n) : string.Empty;
    }

    // One parsed sweep-log line (D00 T02 §34): the birth's main, target,
    // the handles it pinned, and every skip with its reason.
    internal sealed record SweepLine(nint Main, int TargetX, int TargetY, List<nint> Pinned, Dictionary<nint, (int X, int Y)> PinnedAt, Dictionary<nint, string> Skipped, string Raw)
    {
        // The phase (`sweep`, or `sweep-late` for the delayed pass) and the
        // construction generation (D00 T02 §41).
        internal string Phase { get; init; } = "sweep";

        internal long Generation { get; init; }
    }

    // Arms the app's test-only sweep log (the run marker plus the log path,
    // both inherited by the launched app) and restores both on dispose.
    internal sealed class SweepLogScope : IDisposable
    {
        readonly string? priorLog = Environment.GetEnvironmentVariable("SCRATCHPAD_SWEEP_LOG");
        readonly string? priorMarker = Environment.GetEnvironmentVariable(Notepad.Core.LaunchCapture.RunMarkerVariable);

        internal SweepLogScope()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"scratchpad-sweep-{Guid.NewGuid():N}.log");
            Environment.SetEnvironmentVariable("SCRATCHPAD_SWEEP_LOG", Path);
            Environment.SetEnvironmentVariable(Notepad.Core.LaunchCapture.RunMarkerVariable, "1");
        }

        internal string Path { get; }

        internal SweepLine ReadBirth(nint main) => Read(line => line.Phase == "sweep" && line.Main == main, $"no sweep line for the birth of 0x{main:X}");

        internal SweepLine ReadBirthOtherThan(nint main) => Read(line => line.Phase == "sweep" && line.Main != main, $"no sweep line for a birth other than 0x{main:X}");

        // The delayed pass's line for a birth (D00 T02 §41 item 4).
        internal SweepLine ReadLate(nint main) => Read(line => line.Phase == "sweep-late" && line.Main == main, $"no delayed-pass line for the birth of 0x{main:X}");

        // The handle the late-helper seam planted for a birth, or zero.
        internal nint ReadPlanted(nint main)
        {
            var deadline = DateTime.UtcNow.AddSeconds(10);
            string want = $"planted late-helper main=0x{(long)main:X} handle=0x";
            while (DateTime.UtcNow < deadline)
            {
                if (File.Exists(Path))
                {
                    string? line = File.ReadAllLines(Path).FirstOrDefault(l => l.StartsWith(want, StringComparison.Ordinal));
                    if (line is not null)
                    {
                        return (nint)long.Parse(line[want.Length..], System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture);
                    }
                }

                Thread.Sleep(200);
            }

            return nint.Zero;
        }

        SweepLine Read(Func<SweepLine, bool> wanted, string missing)
        {
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (DateTime.UtcNow < deadline)
            {
                if (File.Exists(Path))
                {
                    foreach (string line in File.ReadAllLines(Path))
                    {
                        SweepLine? parsed = Parse(line);
                        if (parsed is not null && wanted(parsed))
                        {
                            return parsed;
                        }
                    }
                }

                Thread.Sleep(200);
            }

            Assert.Fail($"{missing} in {Path}");
            return null!;
        }

        static SweepLine? Parse(string line)
        {
            var m = System.Text.RegularExpressions.Regex.Match(line, @"^(sweep|sweep-late) main=0x([0-9A-F]+) target=(-?\d+),(-?\d+) gen=(\d+) pinned=([^ ]*) skipped=(.*)$");
            if (!m.Success)
            {
                return null;
            }

            nint Hex(string h) => (nint)long.Parse(h, System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture);
            // Pinned entries read 0xHANDLE or 0xHANDLE@x,y (the position
            // read back right after the pin).
            var pinned = new List<nint>();
            var pinnedAt = new Dictionary<nint, (int X, int Y)>();
            foreach (System.Text.RegularExpressions.Match pm in System.Text.RegularExpressions.Regex.Matches(m.Groups[6].Value, @"0x([0-9A-F]+)(?:@(-?\d+),(-?\d+))?"))
            {
                nint h = Hex(pm.Groups[1].Value);
                pinned.Add(h);
                if (pm.Groups[2].Success)
                {
                    pinnedAt[h] = (int.Parse(pm.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture), int.Parse(pm.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture));
                }
            }
            var skipped = new Dictionary<nint, string>();
            foreach (System.Text.RegularExpressions.Match sm in System.Text.RegularExpressions.Regex.Matches(m.Groups[7].Value, @"0x([0-9A-F]+)\(([a-z-]+)\)"))
            {
                skipped[Hex(sm.Groups[1].Value)] = sm.Groups[2].Value;
            }

            return new SweepLine(Hex(m.Groups[2].Value), int.Parse(m.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture), int.Parse(m.Groups[4].Value, System.Globalization.CultureInfo.InvariantCulture), pinned, pinnedAt, skipped, line)
            {
                Phase = m.Groups[1].Value,
                Generation = long.Parse(m.Groups[5].Value, System.Globalization.CultureInfo.InvariantCulture),
            };
        }

        public void Dispose()
        {
            Environment.SetEnvironmentVariable("SCRATCHPAD_SWEEP_LOG", priorLog);
            Environment.SetEnvironmentVariable(Notepad.Core.LaunchCapture.RunMarkerVariable, priorMarker);
            try
            {
                File.Delete(Path);
            }
            catch (IOException)
            {
                // Best effort: the assertions already ran.
            }
        }
    }

    // Visible top-level windows of the process that are not a main
    // window (popups, flyouts, helpers), with their rects.
    static Dictionary<nint, HelperRect> HelperWindows(int pid)
    {
        var found = new Dictionary<nint, HelperRect>();
        _ = HelperNative.EnumWindows((hwnd, param) =>
        {
            _ = param;
            _ = HelperNative.GetWindowThreadProcessId(hwnd, out uint owner);
            if (owner == (uint)pid && HelperNative.IsWindowVisible(hwnd))
            {
                var buffer = new char[256];
                int length = HelperNative.GetClassName(hwnd, buffer, buffer.Length);
                if ((length <= 0 ? string.Empty : new string(buffer, 0, length)) != "WinUIDesktopWin32WindowClass")
                {
                    var rect = default(HelperRect);
                    if (HelperNative.GetWindowRect(hwnd, ref rect))
                    {
                        found[hwnd] = rect;
                    }
                }
            }

            return true;
        }, nint.Zero);
        return found;
    }


    // Records location changes of chosen windows through an out-of-context
    // WinEvent hook on a dedicated message-pumping thread (D00 T02 §26).
    // Stop unhooks, ends the pump, and returns each move as text.
    sealed class LocationRecorder : IDisposable
    {
        const uint EventObjectLocationChange = 0x800B;
        const uint WineventOutOfContext = 0x0000;
        const int ObjIdWindow = 0;
        const uint WmQuit = 0x0012;
        const uint WmBarrier = 0x8000 + 41;
        readonly ManualResetEventSlim barrier = new(false);
        int drainedAtBarrier = -1;
        readonly HashSet<nint> watch;
        readonly uint pid;
        readonly List<string> moves = [];
        readonly ManualResetEventSlim ready = new(false);
        readonly Thread pump;
        uint threadId;
        bool stopped;
        HelperNative.WinEventProc? proc;

        internal bool Hooked { get; private set; }

        internal LocationRecorder(uint pid, IEnumerable<nint> hwnds)
        {
            this.pid = pid;
            watch = hwnds.ToHashSet();
            pump = new Thread(Run) { IsBackground = true };
            pump.Start();
            Assert.True(ready.Wait(TimeSpan.FromSeconds(5)), "the location-change recorder thread never started");
        }

        void Run()
        {
            threadId = HelperNative.GetCurrentThreadId();
            proc = (hook, evt, hwnd, idObject, idChild, thread, time) =>
            {
                if (idObject == ObjIdWindow && watch.Contains(hwnd))
                {
                    var rect = default(HelperRect);
                    _ = HelperNative.GetWindowRect(hwnd, ref rect);
                    lock (moves)
                    {
                        moves.Add($"0x{hwnd:X} to ({rect.Left},{rect.Top})");
                    }
                }
            };
            nint hook = HelperNative.SetWinEventHook(EventObjectLocationChange, EventObjectLocationChange, nint.Zero, proc, pid, 0, WineventOutOfContext);
            Hooked = hook != nint.Zero;
            ready.Set();
            while (HelperNative.GetMessage(out HelperMsg msg, nint.Zero, 0, 0) > 0)
            {
                if (msg.Message == WmBarrier)
                {
                    lock (moves)
                    {
                        drainedAtBarrier = moves.Count;
                    }

                    barrier.Set();
                    continue;
                }

                _ = HelperNative.TranslateMessage(ref msg);
                _ = HelperNative.DispatchMessage(ref msg);
            }

            if (hook != nint.Zero)
            {
                _ = HelperNative.UnhookWinEvent(hook);
            }
        }

        // The observation barrier (D00 T02 §41 item 6): a synchronous
        // WM_NULL to each app window returns only after that window's UI
        // thread has handled everything queued before it (so every move it
        // made has raised its event), then a barrier message queued behind
        // the recorder's pending events marks the drain. Returns the event
        // count the recorder holds at the barrier; fails when a window or
        // the recorder does not answer within its bound.
        internal int DrainToBarrier(IEnumerable<nint> appWindows)
        {
            foreach (nint hwnd in appWindows)
            {
                Assert.True(HelperNative.SendMessageTimeout(hwnd, 0, nint.Zero, nint.Zero, 0x0002, 5000, out _) != nint.Zero, $"app window 0x{hwnd:X} did not answer the barrier within 5 s");
            }

            barrier.Reset();
            Assert.True(HelperNative.PostThreadMessage(threadId, WmBarrier, nint.Zero, nint.Zero), "the barrier could not reach the recorder thread");
            Assert.True(barrier.Wait(TimeSpan.FromSeconds(5)), "the recorder never reached the barrier");
            return drainedAtBarrier;
        }

        internal List<string> Stop()
        {
            if (!stopped)
            {
                stopped = true;
                _ = HelperNative.PostThreadMessage(threadId, WmQuit, nint.Zero, nint.Zero);
                _ = pump.Join(TimeSpan.FromSeconds(5));
            }

            lock (moves)
            {
                return [.. moves];
            }
        }

        public void Dispose()
        {
            _ = Stop();
            ready.Dispose();
            barrier.Dispose();
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct HelperMsg
    {
        public nint Hwnd;
        public uint Message;
        public nint WParam;
        public nint LParam;
        public uint Time;
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct HelperRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    static class HelperNative
    {
        internal delegate bool EnumWindowsProc(nint hwnd, nint param);

        internal delegate void WinEventProc(nint hook, uint evt, nint hwnd, int idObject, int idChild, uint thread, uint time);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint SetWinEventHook(uint eventMin, uint eventMax, nint module, WinEventProc proc, uint pid, uint thread, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool UnhookWinEvent(nint hook);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetMessage(out HelperMsg msg, nint hwnd, uint min, uint max);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool TranslateMessage(ref HelperMsg msg);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint DispatchMessage(ref HelperMsg msg);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool PostThreadMessage(uint thread, uint msg, nint wParam, nint lParam);

        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint SendMessageTimeout(nint hwnd, uint msg, nint wParam, nint lParam, uint flags, uint timeout, out nint result);

        [DllImport("kernel32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool EnumWindows(EnumWindowsProc callback, nint param);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint pid);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool IsWindowVisible(nint hwnd);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(nint hwnd);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetAncestor(nint hwnd, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool GetWindowRect(nint hwnd, ref HelperRect rect);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetClassName(nint hwnd, [Out] char[] name, int max);
    }

}
