using Windows.UI.StartScreen;
using Xunit;

namespace UI;

// D01 T01 §8 spike: does the WinRT JumpList API work unpackaged? The
// classic ICustomDestinationList builder coclass is unregistered on this
// Windows (all registered destination classes fail QI), so this decides
// the implementation: green keeps this file as the integration drive,
// red deletes it for the next approach.
public sealed class JumpListSpikeTests
{
    [Fact]
    public async Task JumpListApiWorksUnpackaged()
    {
        JumpList list = await JumpList.LoadCurrentAsync();
        list.Items.Clear();
        list.Items.Add(JumpListItem.CreateWithArguments("spike-arg-8", "spike8.txt"));
        await list.SaveAsync();
    }
}
