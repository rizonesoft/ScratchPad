using System;
using System.Drawing;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System.Threading;
using Notepad.Core;

namespace ScratchPad;

// Print engine, owned by D01 T02 §5. Renders the active document through
// System.Drawing.Printing: the silent path (print-to-PDF, /p, /pt) runs
// PrintDocument directly; the interactive path shows the OS Print and Page
// Setup dialogs through raw comdlg32 interop (PrintDlgEx, PageSetupDlg),
// following the §1 IFileDialog precedent instead of WinForms (no SDK
// change, HWND owner direct, UIA-visible common dialogs). Absorbs
// PrintSeam.cs: the /p /pt flags now print-then-close for real.
// Header/footer codes expand through PrintCodes; line-breaking through
// PrintWrap over Graphics-measured widths. The print font follows the
// configured editor font (documented stock behavior).
internal static class PrintService
{
    public const string PdfPrinter = "Microsoft Print to PDF";

    internal sealed record PrintOutcome(bool Printed, string? Error);

    // Silent print of in-memory text to a PDF file. now fixes &d &t for
    // deterministic goldens; callers pass DateTime.Now for live prints.
    public static PrintOutcome PrintToPdf(
        string text, string fileName, string pdfPath, ShellSettings settings, DateTime now)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(fileName);
        ArgumentNullException.ThrowIfNull(pdfPath);
        ArgumentNullException.ThrowIfNull(settings);
        if (!IsPrinterInstalled(PdfPrinter))
        {
            return new PrintOutcome(false, $"Printer '{PdfPrinter}' is not installed.");
        }

        try
        {
            using var document = BuildDocument(text, fileName, settings, now);
            document.PrinterSettings.PrinterName = PdfPrinter;
            document.PrinterSettings.PrintToFile = true;
            document.PrinterSettings.PrintFileName = pdfPath;
            document.PrintController = new StandardPrintController();
            RunOnStaThread(document.Print);
            return new PrintOutcome(true, null);
        }
        catch (Exception ex) when (ex is InvalidPrinterException or System.ComponentModel.Win32Exception)
        {
            return new PrintOutcome(false, ex.Message);
        }
    }

    // /p /pt entry: prints a file to the named printer (or the OS default)
    // with no dialogs, then the caller closes. A file printer (Print to
    // PDF) writes next-to-source (default: stock would prompt for the name,
    // impossible headless; cost: one behavior note in the §5 review).
    public static PrintOutcome PrintFile(string file, string? printer)
    {
        ArgumentException.ThrowIfNullOrEmpty(file);
        string target = printer ?? new PrinterSettings().PrinterName;
        if (!IsPrinterInstalled(target))
        {
            return new PrintOutcome(false, $"Printer '{target}' is not installed.");
        }

        string text;
        try
        {
            text = System.IO.File.ReadAllText(file);
        }
        catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException)
        {
            return new PrintOutcome(false, ex.Message);
        }

        ShellSettings settings = ShellSettings.Load();
        DateTime now = DateTime.Now;
        try
        {
            using var document = BuildDocument(text, System.IO.Path.GetFileName(file), settings, now);
            document.PrinterSettings.PrinterName = target;
            if (string.Equals(target, PdfPrinter, StringComparison.OrdinalIgnoreCase))
            {
                document.PrinterSettings.PrintToFile = true;
                document.PrinterSettings.PrintFileName = System.IO.Path.ChangeExtension(file, ".pdf");
            }

            document.PrintController = new StandardPrintController();
            RunOnStaThread(document.Print);
            return new PrintOutcome(true, null);
        }
        catch (Exception ex) when (ex is InvalidPrinterException or System.ComponentModel.Win32Exception)
        {
            return new PrintOutcome(false, ex.Message);
        }
    }

    // Interactive File > Print: OS print dialog, then print on OK. Runs on
    // the UI thread (common dialogs are modal and pump).
    public static PrintOutcome PrintInteractive(nint hwnd, string text, string fileName, ShellSettings settings)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(fileName);
        ArgumentNullException.ThrowIfNull(settings);
        if (!ShowPrintDialog(hwnd, out string printer, out short copies, out bool collate))
        {
            return new PrintOutcome(false, null);
        }

        if (!IsPrinterInstalled(printer))
        {
            return new PrintOutcome(false, $"Printer '{printer}' is not installed.");
        }

        try
        {
            using var document = BuildDocument(text, fileName, settings, DateTime.Now);
            document.PrinterSettings.PrinterName = printer;
            document.PrinterSettings.Copies = copies;
            document.PrinterSettings.Collate = collate;
            document.PrintController = new StandardPrintController();
            document.Print();
            return new PrintOutcome(true, null);
        }
        catch (Exception ex) when (ex is InvalidPrinterException or System.ComponentModel.Win32Exception)
        {
            return new PrintOutcome(false, ex.Message);
        }
    }

    // Interactive File > Page Setup: OS page-setup dialog, applied to the
    // §2 store on OK. Returns false on cancel (store untouched).
    public static bool ShowPageSetup(nint hwnd)
    {
        ShellSettings current = SettingsStore.Shared.Current;
        var margins = new Margins(current.PrintMarginLeft, current.PrintMarginRight, current.PrintMarginTop, current.PrintMarginBottom);
        if (!ShowPageSetupDialog(hwnd, ref margins, out bool? landscape, out int paperRawKind))
        {
            return false;
        }

        SettingsStore.Shared.Update(s =>
        {
            s.PrintMarginLeft = margins.Left;
            s.PrintMarginRight = margins.Right;
            s.PrintMarginTop = margins.Top;
            s.PrintMarginBottom = margins.Bottom;
            if (landscape.HasValue)
            {
                s.PrintLandscape = landscape.Value;
            }

            if (paperRawKind != 0)
            {
                s.PrintPaperRawKind = paperRawKind;
            }
        });
        return true;
    }

    public static bool IsPrinterInstalled(string printer)
    {
        foreach (string installed in PrinterSettings.InstalledPrinters)
        {
            if (string.Equals(installed, printer, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    static PrintDocument BuildDocument(string text, string fileName, ShellSettings settings, DateTime now)
    {
        var document = new PrintDocument
        {
            DocumentName = fileName,
            DefaultPageSettings =
            {
                Margins = new Margins(
                    settings.PrintMarginLeft,
                    settings.PrintMarginRight,
                    settings.PrintMarginTop,
                    settings.PrintMarginBottom),
                Landscape = settings.PrintLandscape,
            },
        };
        if (settings.PrintPaperRawKind != 0)
        {
            foreach (PaperSize paper in document.PrinterSettings.PaperSizes)
            {
                if (paper.RawKind == settings.PrintPaperRawKind)
                {
                    document.DefaultPageSettings.PaperSize = paper;
                    break;
                }
            }
        }

        var state = new Pagination(text.Split(["\r\n", "\r", "\n"], StringSplitOptions.None));
        FontStyle style = settings.FontStyle switch
        {
            "Bold" => FontStyle.Bold,
            "Italic" => FontStyle.Italic,
            "BoldItalic" => FontStyle.Bold | FontStyle.Italic,
            _ => FontStyle.Regular,
        };
        var context = new PrintContext(
            now.ToShortDateString(), now.ToShortTimeString(), fileName, 0);
        document.PrintPage += (sender, e) =>
        {
            ArgumentNullException.ThrowIfNull(e);
            if (e.Graphics is null)
            {
                e.HasMorePages = false;
                e.Cancel = true;
                return;
            }

            using var font = new Font(settings.FontFamily, settings.FontSize, style);
            RenderPage(e.Graphics, e.MarginBounds, font, settings, state, context with { Page = state.Page + 1 });
            state.Page++;
            e.HasMorePages = !state.Finished;
        };
        return document;
    }

    static void RenderPage(
        Graphics g, Rectangle bounds, Font font, ShellSettings settings,
        Pagination state, PrintContext context)
    {
        float lineHeight = font.GetHeight(g);
        var brush = Brushes.Black;
        var format = StringFormat.GenericTypographic;
        float y = bounds.Top;

        (string headLeft, string headCenter, string headRight) =
            PrintCodes.ExpandParts(settings.PrintHeader, context);
        DrawPart(g, headLeft, font, brush, bounds.Left, y, bounds.Width, format, StringAlignment.Near);
        DrawPart(g, headCenter, font, brush, bounds.Left, y, bounds.Width, format, StringAlignment.Center);
        DrawPart(g, headRight, font, brush, bounds.Left, y, bounds.Width, format, StringAlignment.Far);
        y += lineHeight * 2;

        float bodyBottom = bounds.Bottom - (lineHeight * 2);
        while (!state.Finished && y + lineHeight <= bodyBottom + 1)
        {
            string line = state.NextLine(g, font, format, bounds.Width);
            g.DrawString(line, font, brush, bounds.Left, y, format);
            y += lineHeight;
        }

        (string footLeft, string footCenter, string footRight) =
            PrintCodes.ExpandParts(settings.PrintFooter, context);
        float footY = bounds.Bottom - lineHeight;
        DrawPart(g, footLeft, font, brush, bounds.Left, footY, bounds.Width, format, StringAlignment.Near);
        DrawPart(g, footCenter, font, brush, bounds.Left, footY, bounds.Width, format, StringAlignment.Center);
        DrawPart(g, footRight, font, brush, bounds.Left, footY, bounds.Width, format, StringAlignment.Far);
    }

    static void DrawPart(
        Graphics g, string text, Font font, Brush brush,
        float x, float y, float width, StringFormat format, StringAlignment align)
    {
        if (text.Length == 0)
        {
            return;
        }

        using var part = (StringFormat)format.Clone();
        part.Alignment = align;
        g.DrawString(text, font, brush, new RectangleF(x, y, width, font.GetHeight(g)), part);
    }

    static void RunOnStaThread(Action action)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
        {
            action();
            return;
        }

        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
#pragma warning disable CA1031 // STA shuttle must marshal any print failure back; rethrown below with its stack.
            catch (Exception ex)
            {
                failure = ex;
            }
#pragma warning restore CA1031
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }

    sealed class Pagination
    {
        readonly string[] paragraphs;
        int paragraph;
        int lineInParagraph;
        List<(int Start, int Count)>? wrapped;

        public Pagination(string[] paragraphs)
        {
            this.paragraphs = paragraphs;
        }

        public int Page { get; set; }

        public bool Finished => paragraph >= paragraphs.Length;

        public string NextLine(Graphics g, Font font, StringFormat format, float width)
        {
            while (paragraph < paragraphs.Length)
            {
                wrapped ??= WrapParagraph(g, font, format, paragraphs[paragraph], width);
                if (lineInParagraph < wrapped.Count)
                {
                    (int start, int count) = wrapped[lineInParagraph];
                    lineInParagraph++;
                    string[] words = paragraphs[paragraph].Split(' ');
                    return string.Join(" ", words, start, count);
                }

                paragraph++;
                lineInParagraph = 0;
                wrapped = null;
            }

            return string.Empty;
        }

        static List<(int Start, int Count)> WrapParagraph(
            Graphics g, Font font, StringFormat format, string text, float width)
        {
            string[] words = text.Split(' ');
            var widths = new float[words.Length];
            for (int i = 0; i < words.Length; i++)
            {
                widths[i] = g.MeasureString(words[i], font, int.MaxValue, format).Width;
            }

            float space = g.MeasureString(" ", font, int.MaxValue, format).Width;
            var lines = PrintWrap.WrapWords(words, widths, space, width);
            return new List<(int Start, int Count)>(lines);
        }
    }

    #region comdlg32 interop

    const uint PD_RETURNDC = 0x100;
    const uint PD_COLLATE = 0x10;
    const uint PD_RESULT_PRINT = 1;
    const uint PSD_MARGINS = 0x2;
    const uint PSD_INTHOUSANDTHSOFINCHES = 0x8;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct PrintDlgExData
    {
        public uint LStructSize;
        public nint HwndOwner;
        public nint HDevMode;
        public nint HDevNames;
        public nint HDC;
        public uint Flags;
        public uint Flags2;
        public uint ExclusionFlags;
        public uint NPageRanges;
        public uint NMaxPageRanges;
        public nint PageRanges;
        public uint NMinPage;
        public uint NMaxPage;
        public uint NCopies;
        public nint HInstance;
        public nint LpPrintTemplateName;
        public nint LpCallback;
        public uint NPropertyPages;
        public nint PropertyPages;
        public uint NStartPage;
        public uint DwResultAction;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct PageSetupDlgData
    {
        public uint LStructSize;
        public nint HwndOwner;
        public nint HDevMode;
        public nint HDevNames;
        public uint Flags;
        public Point PtPaperSize;
        public Rect RtMinMargin;
        public Rect RtMargin;
        public nint HInstance;
        public nint LCustData;
        public nint LpfnPageSetupHook;
        public nint LpfnPagePaintHook;
        public nint LpPageSetupTemplateName;
        public nint HPageSetupTemplate;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct DevNames
    {
        public ushort WDriverOffset;
        public ushort WDeviceOffset;
        public ushort WOutputOffset;
        public ushort BDefault;
    }

    [DllImport("comdlg32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern int PrintDlgEx(ref PrintDlgExData data);

    [DllImport("comdlg32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern bool PageSetupDlg(ref PageSetupDlgData data);

    [DllImport("gdi32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern bool DeleteDC(nint hdc);

    [DllImport("kernel32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern nint GlobalLock(nint hMem);

    [DllImport("kernel32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern bool GlobalUnlock(nint hMem);

    [DllImport("kernel32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern nint GlobalFree(nint hMem);

    static bool ShowPrintDialog(nint hwnd, out string printer, out short copies, out bool collate)
    {
        printer = string.Empty;
        copies = 1;
        collate = false;
        var data = new PrintDlgExData
        {
            LStructSize = (uint)Marshal.SizeOf<PrintDlgExData>(),
            HwndOwner = hwnd,
            Flags = PD_RETURNDC | PD_COLLATE,
            NStartPage = 0xFFFFFFFF,
        };
        try
        {
            int hr = PrintDlgEx(ref data);
            if (hr != 0 || data.DwResultAction != PD_RESULT_PRINT)
            {
                return false;
            }

            printer = ReadDevName(data.HDevNames);
            copies = (short)Math.Max(1, Math.Min(short.MaxValue, data.NCopies));
            collate = (data.Flags & PD_COLLATE) != 0;
            return true;
        }
        finally
        {
            if (data.HDC != nint.Zero)
            {
                DeleteDC(data.HDC);
            }

            if (data.HDevMode != nint.Zero)
            {
                GlobalFree(data.HDevMode);
            }

            if (data.HDevNames != nint.Zero)
            {
                GlobalFree(data.HDevNames);
            }
        }
    }

    // Unicode DEVMODE field offsets: dmDeviceName is 32 WCHAR (64 bytes),
    // then four WORDs and the dmFields DWORD, so dmOrientation sits at 76
    // and dmPaperSize at 78. Guarded by dmSize; absent fields keep the
    // incoming settings (the dialog only writes what it shows).
    static (bool? Landscape, int PaperRawKind) ReadOrientationPaper(nint hDevMode)
    {
        nint locked = GlobalLock(hDevMode);
        if (locked == nint.Zero)
        {
            return (null, 0);
        }

        try
        {
            if (Marshal.ReadInt16(locked, 68) < 80)
            {
                return (null, 0);
            }

            int fields = Marshal.ReadInt32(locked, 72);
            bool? landscape = (fields & 0x1) != 0 ? Marshal.ReadInt16(locked, 76) == 2 : null;
            int paper = (fields & 0x2) != 0 ? Marshal.ReadInt16(locked, 78) : 0;
            return (landscape, paper);
        }
        finally
        {
            GlobalUnlock(hDevMode);
        }
    }

    static string ReadDevName(nint hDevNames)
    {
        nint locked = GlobalLock(hDevNames);
        if (locked == nint.Zero)
        {
            return string.Empty;
        }

        try
        {
            var names = Marshal.PtrToStructure<DevNames>(locked);
            nint device = locked + (names.WDeviceOffset * Marshal.SystemDefaultCharSize);
            return Marshal.PtrToStringAuto(device) ?? string.Empty;
        }
        finally
        {
            GlobalUnlock(hDevNames);
        }
    }

    static bool ShowPageSetupDialog(nint hwnd, ref Margins margins, out bool? landscape, out int paperRawKind)
    {
        landscape = null;
        paperRawKind = 0;
        var data = new PageSetupDlgData
        {
            LStructSize = (uint)Marshal.SizeOf<PageSetupDlgData>(),
            HwndOwner = hwnd,
            Flags = PSD_MARGINS | PSD_INTHOUSANDTHSOFINCHES,
            RtMargin = new Rect
            {
                Left = margins.Left * 10,
                Top = margins.Top * 10,
                Right = margins.Right * 10,
                Bottom = margins.Bottom * 10,
            },
        };
        try
        {
            if (!PageSetupDlg(ref data))
            {
                return false;
            }

            margins = new Margins(
                data.RtMargin.Left / 10,
                data.RtMargin.Right / 10,
                data.RtMargin.Top / 10,
                data.RtMargin.Bottom / 10);
            (landscape, paperRawKind) = ReadOrientationPaper(data.HDevMode);
            return true;
        }
        finally
        {
            if (data.HDevMode != nint.Zero)
            {
                GlobalFree(data.HDevMode);
            }

            if (data.HDevNames != nint.Zero)
            {
                GlobalFree(data.HDevNames);
            }
        }
    }

    #endregion
}
