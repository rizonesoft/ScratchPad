using System.Diagnostics.CodeAnalysis;
using Xunit;

namespace UI;

[CollectionDefinition("UI tests", DisableParallelization = true)]
[SuppressMessage("Design", "CA1515", Justification = "xUnit requires public collection definitions.")]
[SuppressMessage("Naming", "CA1711", Justification = "xUnit names collection definitions *Collection.")]
public sealed class UiTestCollection
{
}
