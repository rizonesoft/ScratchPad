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

                var moved = moves.Stop();
                Assert.True(moves.Hooked, "the location-change recorder never hooked; the proof would read vacuous");
                Assert.True(moved.Count == 0, $"another window's birth moved this window's live helpers: {string.Join("; ", moved)}");
                var after = HelperWindows(first.ProcessId);
                foreach (var (hwnd, rect) in helpers)
                {
                    Assert.True(after.TryGetValue(hwnd, out HelperRect now), $"helper 0x{hwnd:X} closed before the birth settled; the premise needs it live");
                    Assert.True(rect.Left == now.Left && rect.Top == now.Top, $"helper 0x{hwnd:X} moved from ({rect.Left},{rect.Top}) to ({now.Left},{now.Top}) when another window was born");
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
                _ = HelperNative.TranslateMessage(ref msg);
                _ = HelperNative.DispatchMessage(ref msg);
            }

            if (hook != nint.Zero)
            {
                _ = HelperNative.UnhookWinEvent(hook);
            }
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
        internal static extern bool GetWindowRect(nint hwnd, ref HelperRect rect);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetClassName(nint hwnd, [Out] char[] name, int max);
    }

}
