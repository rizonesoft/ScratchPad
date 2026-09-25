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
// Each skip names its owner and the host that owes the run (D00 T02 §44
// item 3).
sealed class PrinterFactAttribute : FactAttribute
{
    public PrinterFactAttribute(string owner)
    {
        Owner = owner;
        if (PrinterSettings.InstalledPrinters.Count == 0)
        {
            Skip = $"CAPABILITY: No printers enumerated in this context (agent context is printer-blind); owner {owner}; owed on a session where the spooler is visible.";
        }
        else
        {
            string def = new PrinterSettings().PrinterName;
            if (!string.IsNullOrEmpty(def) && !IsVirtualPrinter(def))
            {
                Skip = $"CAPABILITY: Default printer is hardware ({def}); owner {owner}; owed on a host whose default printer is virtual (PDF or XPS).";
            }
        }
    }

    public string Owner { get; }

    static bool IsVirtualPrinter(string name) =>
        name.Contains("PDF", StringComparison.OrdinalIgnoreCase)
        || name.Contains("XPS", StringComparison.OrdinalIgnoreCase);
}
