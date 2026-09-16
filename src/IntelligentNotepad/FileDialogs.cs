using System.Runtime.InteropServices;

namespace IntelligentNotepad;

// Native file dialogs, owned by D01 T01 §2 item 1 (Open/Save As triggers).
// Stock's Open and Save As dialogs are the OS Common Item Dialog with an
// Encoding combo the WinUI pickers cannot host, so this file drives
// IFileOpenDialog/IFileSaveDialog through COM interop instead. Vtable
// order, GUIDs, and signatures are read off ShObjIdl_core.h (10.0.26100.0),
// not memory: IFileOpenDialog ends ...d960 and IFileDialogCustomize is
// e6fdd21a-163f-4975-9c8c-a69f1ba37034, both against common recollection.
// Show runs on the UI thread (STA with a pump); cancel returns null.
internal static class FileDialogs
{
    const int EncodingComboId = 1001;
    const int EncodingGroupId = 1002;
    const int HResultCancelled = unchecked((int)0x800704C7);

    static readonly Guid ClsOpen = new("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7");
    static readonly Guid ClsSave = new("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B");
    static readonly Guid IidDialog = new("42f85136-db7e-439c-85f1-e4075d135fc8");

    internal sealed record Choice(string Path, string? EncodingName);

    internal static Choice? ShowOpen(IntPtr owner, IReadOnlyList<string> encodings)
    {
        object? dialog = null;
        object? customize = null;
        object? item = null;
        try
        {
            dialog = Create(ClsOpen);
            var file = (IFileDialog)dialog;
            ThrowIfFailed(file.SetFileTypes(2, [
                new FilterSpec("Text documents (*.txt)", "*.txt"),
                new FilterSpec("All files (*.*)", "*.*"),
            ]));
            ThrowIfFailed(file.SetFileTypeIndex(1));
            ThrowIfFailed(file.SetOptions(0x800 | 0x8 | 0x40));
            customize = (IFileDialogCustomize)dialog;
            var custom = (IFileDialogCustomize)customize;
            ThrowIfFailed(custom.StartVisualGroup(EncodingGroupId, "Encoding:"));
            ThrowIfFailed(custom.AddComboBox(EncodingComboId));
            for (int i = 0; i < encodings.Count; i++)
            {
                ThrowIfFailed(custom.AddControlItem(EncodingComboId, (uint)i, encodings[i]));
            }

            ThrowIfFailed(custom.SetSelectedControlItem(EncodingComboId, 0));
            ThrowIfFailed(custom.EndVisualGroup());
            ThrowIfFailed(custom.MakeProminent(EncodingGroupId));
            int shown = file.Show(owner);
            if (shown == HResultCancelled)
            {
                return null;
            }

            ThrowIfFailed(shown);
            ThrowIfFailed(file.GetResult(out IntPtr result));
            item = Marshal.GetObjectForIUnknown(result);
            Marshal.Release(result);
            string path = DisplayPath((IShellItem)item);
            ThrowIfFailed(custom.GetSelectedControlItem(EncodingComboId, out uint selected));
            string? encoding = selected == 0 ? null : encodings[(int)selected];
            return new Choice(path, encoding);
        }
        finally
        {
            if (item is not null)
            {
                Marshal.ReleaseComObject(item);
            }

            if (customize is not null)
            {
                Marshal.ReleaseComObject(customize);
            }

            if (dialog is not null)
            {
                Marshal.ReleaseComObject(dialog);
            }
        }
    }

    internal static Choice? ShowSave(IntPtr owner, string fileName, IReadOnlyList<string> encodings, string currentEncoding)
    {
        object? dialog = null;
        object? customize = null;
        object? item = null;
        try
        {
            dialog = Create(ClsSave);
            var file = (IFileDialog)dialog;
            ThrowIfFailed(file.SetFileTypes(2, [
                new FilterSpec("Text documents (*.txt)", "*.txt"),
                new FilterSpec("All files (*.*)", "*.*"),
            ]));
            ThrowIfFailed(file.SetFileTypeIndex(1));
            ThrowIfFailed(file.SetFileName(fileName));
            ThrowIfFailed(file.SetDefaultExtension("txt"));
            ThrowIfFailed(file.SetOptions(0x800 | 0x2 | 0x8 | 0x40));
            customize = (IFileDialogCustomize)dialog;
            var custom = (IFileDialogCustomize)customize;
            ThrowIfFailed(custom.StartVisualGroup(EncodingGroupId, "Encoding:"));
            ThrowIfFailed(custom.AddComboBox(EncodingComboId));
            uint selected = 0;
            for (int i = 0; i < encodings.Count; i++)
            {
                ThrowIfFailed(custom.AddControlItem(EncodingComboId, (uint)i, encodings[i]));
                if (encodings[i] == currentEncoding)
                {
                    selected = (uint)i;
                }
            }

            ThrowIfFailed(custom.SetSelectedControlItem(EncodingComboId, selected));
            ThrowIfFailed(custom.EndVisualGroup());
            ThrowIfFailed(custom.MakeProminent(EncodingGroupId));
            int shown = file.Show(owner);
            if (shown == HResultCancelled)
            {
                return null;
            }

            ThrowIfFailed(shown);
            ThrowIfFailed(file.GetResult(out IntPtr result));
            item = Marshal.GetObjectForIUnknown(result);
            Marshal.Release(result);
            string path = DisplayPath((IShellItem)item);
            ThrowIfFailed(custom.GetSelectedControlItem(EncodingComboId, out uint chosen));
            return new Choice(path, encodings[(int)chosen]);
        }
        finally
        {
            if (item is not null)
            {
                Marshal.ReleaseComObject(item);
            }

            if (customize is not null)
            {
                Marshal.ReleaseComObject(customize);
            }

            if (dialog is not null)
            {
                Marshal.ReleaseComObject(dialog);
            }
        }
    }

    static object Create(Guid clsid)
    {
        Guid iid = IidDialog;
        Guid cls = clsid;
        ThrowIfFailed(CoCreateInstance(ref cls, IntPtr.Zero, 1, ref iid, out IntPtr raw));
        try
        {
            return Marshal.GetObjectForIUnknown(raw);
        }
        finally
        {
            Marshal.Release(raw);
        }
    }

    static string DisplayPath(IShellItem item)
    {
        ThrowIfFailed(item.GetDisplayName(unchecked((int)0x80058000), out IntPtr text));
        try
        {
            return Marshal.PtrToStringUni(text) ?? string.Empty;
        }
        finally
        {
            Marshal.FreeCoTaskMem(text);
        }
    }

    static void ThrowIfFailed(int hresult)
    {
        if (hresult < 0)
        {
            Marshal.ThrowExceptionForHR(hresult);
        }
    }

    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("ole32.dll", ExactSpelling = true)]
    static extern int CoCreateInstance(ref Guid rclsid, IntPtr pUnkOuter, uint dwClsContext, ref Guid riid, out IntPtr ppv);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FilterSpec(string name, string spec)
    {
        public string Name = name;
        public string Spec = spec;
    }

    [ComImport]
    [Guid("b4db1657-70d7-485e-8e3e-6fcb5a5c1802")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IModalWindow
    {
        [PreserveSig]
        int Show(IntPtr hwndOwner);
    }

    // Slots in header order; unused ones are never called. SetFileTypes 0,
    // SetFileTypeIndex 1, SetOptions 5, SetFileName 11, GetResult 16,
    // SetDefaultExtension 18.
    [ComImport]
    [Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFileDialog : IModalWindow
    {
        [PreserveSig]
        new int Show(IntPtr hwndOwner);

        [PreserveSig]
        int SetFileTypes(uint cFileTypes, [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] FilterSpec[] rgFilterSpec);

        [PreserveSig]
        int SetFileTypeIndex(uint iFileType);

        [PreserveSig]
        int ReservedGetFileTypeIndex();

        [PreserveSig]
        int ReservedAdvise();

        [PreserveSig]
        int ReservedUnadvise();

        [PreserveSig]
        int SetOptions(uint fos);

        [PreserveSig]
        int ReservedGetOptions();

        [PreserveSig]
        int ReservedSetDefaultFolder();

        [PreserveSig]
        int ReservedSetFolder();

        [PreserveSig]
        int ReservedGetFolder();

        [PreserveSig]
        int ReservedGetCurrentSelection();

        [PreserveSig]
        int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);

        [PreserveSig]
        int ReservedGetFileName();

        [PreserveSig]
        int ReservedSetTitle();

        [PreserveSig]
        int ReservedSetOkButtonLabel();

        [PreserveSig]
        int ReservedSetFileNameLabel();

        [PreserveSig]
        int GetResult(out IntPtr ppsi);

        [PreserveSig]
        int ReservedAddPlace();

        [PreserveSig]
        int SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
    }

    // Slots in header order; unused ones are never called. AddComboBox 3,
    // AddText 8, AddControlItem 16, GetSelectedControlItem 21,
    // SetSelectedControlItem 22, MakeProminent 25.
    [ComImport]
    [Guid("e6fdd21a-163f-4975-9c8c-a69f1ba37034")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFileDialogCustomize
    {
        [PreserveSig]
        int ReservedEnableOpenDropDown();

        [PreserveSig]
        int ReservedAddMenu();

        [PreserveSig]
        int ReservedAddPushButton();

        [PreserveSig]
        int AddComboBox(uint dwIDCtl);

        [PreserveSig]
        int ReservedAddRadioButtonList();

        [PreserveSig]
        int ReservedAddCheckButton();

        [PreserveSig]
        int ReservedAddEditBox();

        [PreserveSig]
        int ReservedAddSeparator();

        [PreserveSig]
        int AddText(uint dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszText);

        [PreserveSig]
        int SetControlLabel(uint dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);

        [PreserveSig]
        int ReservedGetControlState();

        [PreserveSig]
        int ReservedSetControlState();

        [PreserveSig]
        int ReservedGetEditBoxText();

        [PreserveSig]
        int ReservedSetEditBoxText();

        [PreserveSig]
        int ReservedGetCheckButtonState();

        [PreserveSig]
        int ReservedSetCheckButtonState();

        [PreserveSig]
        int AddControlItem(uint dwIDCtl, uint dwIDItem, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);

        [PreserveSig]
        int ReservedRemoveControlItem();

        [PreserveSig]
        int ReservedRemoveAllControlItems();

        [PreserveSig]
        int ReservedGetControlItemState();

        [PreserveSig]
        int ReservedSetControlItemState();

        [PreserveSig]
        int GetSelectedControlItem(uint dwIDCtl, out uint pdwIDItem);

        [PreserveSig]
        int SetSelectedControlItem(uint dwIDCtl, uint dwIDItem);

        [PreserveSig]
        int StartVisualGroup(uint dwIDCtl, [MarshalAs(UnmanagedType.LPWStr)] string pszLabel);

        [PreserveSig]
        int EndVisualGroup();

        [PreserveSig]
        int MakeProminent(uint dwIDCtl);
    }

    [ComImport]
    [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItem
    {
        [PreserveSig]
        int ReservedBindToHandler();

        [PreserveSig]
        int ReservedGetParent();

        [PreserveSig]
        int GetDisplayName(int sigdnName, out IntPtr ppszName);
    }
}
