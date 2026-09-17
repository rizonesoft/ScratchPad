using System.Diagnostics;
using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// TEMPORARY golden bootstrap for D01 T02 §5. Prints a fixed document via
// /pt on CI (the dev session cannot reach the spooler), stages the PDF as
// a golden-failure artifact, and fails deliberately so CI uploads it.
// Deleted before the section ships; the committed golden plus PrintTests
// are the standing artifacts.
[Collection("UI tests")]
public sealed class PrintGoldenBootstrapTemp
{
    readonly ITestOutputHelper output;

    public PrintGoldenBootstrapTemp(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void BootstrapPrintGolden()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string file = Path.Combine(dir, "print-golden.txt");
        File.WriteAllText(file, "alpha bravo\nthis is a long line that must wrap across the printable width several times over\n\ndelta");
        new ShellSettings
        {
            WhatsNewSeen = true,
            WhenStarts = WhenStartsRouting.Fresh,
            PrintHeader = "GOLDEN &f",
            PrintFooter = "Page &p",
        }.Save();
        SessionData.Delete();
        try
        {
            string exe = AppExe();
            using var print = Process.Start(new ProcessStartInfo(exe, $"/pt \"{file}\" \"Microsoft Print to PDF\"") { UseShellExecute = false });
            Assert.NotNull(print);
            Assert.True(print.WaitForExit(TimeSpan.FromMinutes(2)), "print timed out");
            Assert.Equal(0, print.ExitCode);
            string pdf = Path.ChangeExtension(file, ".pdf");
            Assert.True(File.Exists(pdf), "bootstrap PDF missing");
            output.WriteLine($"bootstrap PDF bytes: {new FileInfo(pdf).Length}");
            File.Copy(pdf, Path.Combine(AppContext.BaseDirectory, "golden-failure-print-bootstrap.pdf"), overwrite: true);
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
            }
        }

        Assert.Fail("bootstrap: PDF staged as golden-failure-print-bootstrap.pdf; delete this test after committing the golden");
    }

    static string AppExe()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return appPath;
    }
}
