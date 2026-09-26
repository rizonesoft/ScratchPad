using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace CaseIdentity;

// A value no encoding rule covers, or a data source that cannot be read.
internal sealed class UnsupportedArgumentException : Exception
{
    public UnsupportedArgumentException()
    {
    }

    public UnsupportedArgumentException(string message)
        : base(message)
    {
    }

    public UnsupportedArgumentException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

// The canonical case-identity encoding (D00 T02 §52 item 3). A Theory
// case's identity comes from its data values, never from xunit's display
// name, which cuts every argument at 50 characters: an InlineData row
// reads its compile-time constants from metadata (so a value held in a
// `const` or a computed constant counts exactly), and a MemberData or
// ClassData row reads the values its source yields. Each value encodes by
// one rule per kind, and a value no rule covers refuses by name instead of
// guessing. Identical rows of one method stay distinct by occurrence
// (`#2`, `#3`), so duplicates count.
internal static class CaseIdentityEncoder
{
    // Strings encode as JSON with only the escapes JSON requires, so a
    // row reads as its source wrote it and one value has one encoding.
    static readonly JsonSerializerOptions Json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    // One value by rule. Culture-sensitive kinds encode invariantly.
    public static string Encode(object? value)
    {
        switch (value)
        {
            case null:
                return "null";
            case string s:
                return JsonSerializer.Serialize(s, Json);
            case char c:
                return "char:" + JsonSerializer.Serialize(c.ToString(), Json);
            case bool b:
                return b ? "true" : "false";
            case Enum e:
                {
                    Type t = e.GetType();
                    string? name = Enum.GetName(t, e);
                    return $"enum:{t.FullName}.{name ?? Convert.ToString(Convert.ChangeType(e, Enum.GetUnderlyingType(t), CultureInfo.InvariantCulture), CultureInfo.InvariantCulture)}";
                }

            case sbyte or byte or short or ushort or int or uint or long or ulong:
                return $"{IntegerKind(value)}:{Convert.ToString(value, CultureInfo.InvariantCulture)}";
            case float f:
                return "single:" + f.ToString("R", CultureInfo.InvariantCulture);
            case double d:
                return "double:" + d.ToString("R", CultureInfo.InvariantCulture);
            case decimal m:
                return "decimal:" + m.ToString(CultureInfo.InvariantCulture);
            case Type t:
                return "type:" + (t.FullName ?? t.Name);
            case DateTime dt:
                return "datetime:" + dt.ToString("O", CultureInfo.InvariantCulture);
            case DateTimeOffset dto:
                return "datetimeoffset:" + dto.ToString("O", CultureInfo.InvariantCulture);
            case TimeSpan ts:
                return "timespan:" + ts.ToString("c", CultureInfo.InvariantCulture);
            case Guid g:
                return "guid:" + g.ToString("D");
            case Array a:
                return "[" + string.Join(",", a.Cast<object?>().Select(Encode)) + "]";
            default:
                throw new UnsupportedArgumentException($"unsupported argument type {value.GetType().FullName} (no encoding rule; give the case a supported value or a stable display override)");
        }
    }

    // A metadata constant (an InlineData argument): enums come back as
    // their underlying value with the enum as the argument type, and
    // arrays as a collection of typed arguments.
    public static string EncodeTyped(CustomAttributeTypedArgument arg)
    {
        if (arg.Value is IReadOnlyCollection<CustomAttributeTypedArgument> items)
        {
            return "[" + string.Join(",", items.Select(EncodeTyped)) + "]";
        }

        if (arg.Value is not null && arg.ArgumentType.IsEnum)
        {
            return Encode(Enum.ToObject(arg.ArgumentType, arg.Value));
        }

        return Encode(arg.Value);
    }

    // Every case row of one Theory method, `<Type.Method>(<arg>, ...)`,
    // occurrences numbered. Returns the rows, or throws
    // UnsupportedArgumentException naming the method and the value.
    public static IReadOnlyList<string> RowsFor(MethodInfo method)
    {
        ArgumentNullException.ThrowIfNull(method);
        string name = $"{method.DeclaringType?.FullName}.{method.Name}";
        var raw = new List<string>();
        foreach (CustomAttributeData data in method.GetCustomAttributesData())
        {
            if (IsA(data.AttributeType, "Xunit.InlineDataAttribute"))
            {
                var args = data.ConstructorArguments.Count == 1 && data.ConstructorArguments[0].Value is IReadOnlyCollection<CustomAttributeTypedArgument> list
                    ? list.Select(EncodeTyped)
                    : data.ConstructorArguments.Select(EncodeTyped);
                raw.Add($"{name}({string.Join(", ", args)})");
            }
        }

        foreach (object attr in method.GetCustomAttributes(inherit: true))
        {
            Type t = attr.GetType();
            if (!IsA(t, "Xunit.Sdk.DataAttribute") || IsA(t, "Xunit.InlineDataAttribute"))
            {
                continue;
            }

            MethodInfo? getData = t.GetMethod("GetData", [typeof(MethodInfo)]);
            if (getData is null)
            {
                throw new UnsupportedArgumentException($"{name}: data source {t.Name} has no GetData(MethodInfo)");
            }

            object? result;
            try
            {
                result = getData.Invoke(attr, [method]);
            }
            catch (TargetInvocationException ex)
            {
                throw new UnsupportedArgumentException($"{name}: data source {t.Name} threw {ex.InnerException?.GetType().Name}: {ex.InnerException?.Message}");
            }

            foreach (object? row in (result as IEnumerable) ?? Array.Empty<object>())
            {
                if (row is not object?[] values)
                {
                    throw new UnsupportedArgumentException($"{name}: data source {t.Name} yielded a row that is not object[]");
                }

                try
                {
                    raw.Add($"{name}({string.Join(", ", values.Select(Encode))})");
                }
                catch (UnsupportedArgumentException ex)
                {
                    throw new UnsupportedArgumentException($"{name}: {ex.Message}");
                }
            }
        }

        var rows = new List<string>();
        var seen = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string r in raw)
        {
            int n = seen.TryGetValue(r, out int k) ? k + 1 : 1;
            seen[r] = n;
            rows.Add(n > 1 ? $"{r}#{n.ToString(CultureInfo.InvariantCulture)}" : r);
        }

        return rows;
    }

    static string IntegerKind(object value) => value switch
    {
        sbyte => "sbyte",
        byte => "byte",
        short => "int16",
        ushort => "uint16",
        int => "int32",
        uint => "uint32",
        long => "int64",
        _ => "uint64",
    };

    static bool IsA(Type? t, string fullName)
    {
        for (; t is not null; t = t.BaseType)
        {
            if (t.FullName == fullName)
            {
                return true;
            }
        }

        return false;
    }
}
