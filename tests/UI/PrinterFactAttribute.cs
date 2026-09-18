using System.Drawing.Printing;
using Xunit;

namespace UI;

// Discovery-time skip for spooler-dependent tests: contexts whose spooler
// enumerates zero printers (the agent context is printer-blind: .NET sees
// zero while raw EnumPrinters sees 8) report Skipped naming the blind
// context, so the suite neither passes vacuously nor fails environmentally.
// No Interactive fence: /pt runs headless with no window and no foreground.
sealed class PrinterFactAttribute : FactAttribute
{
    public PrinterFactAttribute()
    {
        if (PrinterSettings.InstalledPrinters.Count == 0)
        {
            Skip = "No printers enumerated in this context (agent context is printer-blind); run where the spooler is visible.";
        }
    }
}
