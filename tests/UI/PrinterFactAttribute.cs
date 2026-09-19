using System.Drawing.Printing;
using Xunit;

namespace UI;

// Discovery-time skip for spooler-dependent tests: contexts whose spooler
// enumerates zero printers (the agent context is printer-blind: .NET sees
// zero while raw EnumPrinters sees 8) report Skipped naming the blind
// context, so the suite neither passes vacuously nor fails environmentally.
// Print coverage never targets hardware (operator rule 2026-09-18): when a
// default printer exists and is not virtual (PDF/XPS), the test reports
// Skipped naming the hardware default instead of spooling a page to it.
// No Interactive fence: /pt runs headless with no window and no foreground.
sealed class PrinterFactAttribute : FactAttribute
{
    public PrinterFactAttribute()
    {
        if (PrinterSettings.InstalledPrinters.Count == 0)
        {
            Skip = "No printers enumerated in this context (agent context is printer-blind); run where the spooler is visible.";
        }
        else
        {
            string def = new PrinterSettings().PrinterName;
            if (!string.IsNullOrEmpty(def) && !IsVirtualPrinter(def))
            {
                Skip = $"Default printer is hardware ({def}); real-print tests run only against virtual (PDF/XPS) printers.";
            }
        }
    }

    static bool IsVirtualPrinter(string name) =>
        name.Contains("PDF", StringComparison.OrdinalIgnoreCase)
        || name.Contains("XPS", StringComparison.OrdinalIgnoreCase);
}
