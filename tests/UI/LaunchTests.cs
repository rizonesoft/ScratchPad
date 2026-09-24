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
}
