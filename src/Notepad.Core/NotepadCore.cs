using System.Reflection;

namespace Notepad.Core;

public sealed class NotepadCore
{
    public string Version { get; } = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()!.InformationalVersion;
}
