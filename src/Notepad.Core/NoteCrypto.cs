using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Notepad.Core;

// Password file locking, owned by D01 T01 §19. UI-free: AES-256-GCM with a
// PBKDF2-HMAC-SHA256 key, parameters stated in docs/encrypted-notes.md.
// Layout: `IntelligentNotepad-Encrypted-1` plus LF, one JSON header line,
// then the ciphertext. The magic keeps the pre-rename product name on
// purpose: it is a persisted format marker, and renaming it would orphan
// every locked note with zero user benefit.
// LF, then raw ciphertext plus the 16-byte tag. The header line is bound as
// associated data, so tampered parameters fail authentication exactly like
// a wrong password: loud, with no oracle detail and no partial output.
public sealed class WrongPasswordException : Exception
{
    public WrongPasswordException()
        : base("Wrong password.")
    {
    }

    public WrongPasswordException(string message)
        : base(message)
    {
    }

    public WrongPasswordException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public static class NoteCrypto
{
    public const string Magic = "IntelligentNotepad-Encrypted-1";
    public const string Algorithm = "AES-256-GCM";
    public const string Kdf = "PBKDF2-SHA256";
    public const int Iterations = 600000;
    public const int SaltBytes = 16;
    public const int NonceBytes = 12;
    public const int TagBytes = 16;
    public const int KeyBytes = 32;

    public static bool IsLocked(byte[] bytes)
    {
        ArgumentNullException.ThrowIfNull(bytes);
        byte[] prefix = Encoding.ASCII.GetBytes(Magic + "\n");
        return bytes.Length >= prefix.Length && bytes.AsSpan(0, prefix.Length).SequenceEqual(prefix);
    }

    public static byte[] Lock(byte[] plaintext, string password)
    {
        ArgumentNullException.ThrowIfNull(plaintext);
        ArgumentNullException.ThrowIfNull(password);
        byte[] salt = RandomNumberGenerator.GetBytes(SaltBytes);
        byte[] nonce = RandomNumberGenerator.GetBytes(NonceBytes);
        return LockWith(plaintext, password, salt, nonce);
    }

    // Deterministic seam for the documented test vector; production callers
    // use Lock, which draws fresh salt and nonce per file.
    public static byte[] LockWith(byte[] plaintext, string password, byte[] salt, byte[] nonce)
    {
        ArgumentNullException.ThrowIfNull(plaintext);
        ArgumentNullException.ThrowIfNull(password);
        ArgumentNullException.ThrowIfNull(salt);
        ArgumentNullException.ThrowIfNull(nonce);
        if (salt.Length != SaltBytes)
        {
            throw new ArgumentException($"Salt must be {SaltBytes} bytes.", nameof(salt));
        }

        if (nonce.Length != NonceBytes)
        {
            throw new ArgumentException($"Nonce must be {NonceBytes} bytes.", nameof(nonce));
        }

        string header = JsonSerializer.Serialize(new LockHeader(
            Algorithm, Kdf, Iterations,
            Convert.ToBase64String(salt), Convert.ToBase64String(nonce)));
        byte[] associated = Encoding.ASCII.GetBytes(header);
        byte[] key = DeriveKey(password, salt, Iterations);
        try
        {
            byte[] ciphertext = new byte[plaintext.Length];
            byte[] tag = new byte[TagBytes];
            using (var gcm = new AesGcm(key, TagBytes))
            {
                gcm.Encrypt(nonce, plaintext, ciphertext, tag, associated);
            }

            byte[] magic = Encoding.ASCII.GetBytes(Magic + "\n");
            byte[] locked = new byte[magic.Length + associated.Length + 1 + ciphertext.Length + tag.Length];
            magic.CopyTo(locked, 0);
            associated.CopyTo(locked, magic.Length);
            locked[magic.Length + associated.Length] = (byte)'\n';
            ciphertext.CopyTo(locked, magic.Length + associated.Length + 1);
            tag.CopyTo(locked, magic.Length + associated.Length + 1 + ciphertext.Length);
            return locked;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public static byte[] Unlock(byte[] locked, string password)
    {
        ArgumentNullException.ThrowIfNull(locked);
        ArgumentNullException.ThrowIfNull(password);
        if (!IsLocked(locked))
        {
            throw new InvalidDataException("Not an encrypted note.");
        }

        int headerStart = Magic.Length + 1;
        int headerEnd = Array.IndexOf(locked, (byte)'\n', headerStart);
        if (headerEnd < 0)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        string headerJson = Encoding.ASCII.GetString(locked, headerStart, headerEnd - headerStart);
        LockHeader? header;
        try
        {
            header = JsonSerializer.Deserialize<LockHeader>(headerJson);
        }
        catch (JsonException)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        if (header is null || header.Alg != Algorithm || header.Kdf != Kdf || header.Iter <= 0)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        byte[] salt;
        byte[] nonce;
        try
        {
            salt = Convert.FromBase64String(header.Salt);
            nonce = Convert.FromBase64String(header.Nonce);
        }
        catch (FormatException)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        if (salt.Length != SaltBytes || nonce.Length != NonceBytes)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        byte[] associated = Encoding.ASCII.GetBytes(headerJson);
        int bodyStart = headerEnd + 1;
        if (locked.Length - bodyStart < TagBytes)
        {
            throw new InvalidDataException("Not a valid encrypted note.");
        }

        int cipherLength = locked.Length - bodyStart - TagBytes;
        byte[] key = DeriveKey(password, salt, header.Iter);
        try
        {
            byte[] plaintext = new byte[cipherLength];
            try
            {
                using (var gcm = new AesGcm(key, TagBytes))
                {
                    gcm.Decrypt(
                        nonce,
                        locked.AsSpan(bodyStart, cipherLength),
                        locked.AsSpan(bodyStart + cipherLength, TagBytes),
                        plaintext,
                        associated);
                }
            }
            catch (AuthenticationTagMismatchException)
            {
                CryptographicOperations.ZeroMemory(plaintext);
                throw new WrongPasswordException();
            }

            return plaintext;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    static byte[] DeriveKey(string password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, KeyBytes);

    // Single-homed re-lock: encodes the buffer under the tab's spec, locks,
    // and commits through the §5 atomic bytes writer. On success the tab is
    // marked locked and clean; on failure nothing is marked and the caller
    // reports the SaveResult. The password never leaves this call.
    public static SaveResult Relock(Tab tab, string text, string password)
    {
        ArgumentNullException.ThrowIfNull(tab);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(password);
        if (tab.FilePath is null)
        {
            return new SaveFailed("No file path.");
        }

        var spec = new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding);
        byte[] locked = Lock(FileSave.Encode(text, spec.EncodingName, spec.HasBom, spec.LineEnding), password);
        SaveResult result = FileSave.SaveBytes(tab.FilePath, locked);
        if (result is SaveSuccess)
        {
            tab.IsLocked = true;
            tab.ApplySave(tab.FilePath, spec);
        }

        return result;
    }

    // Throwing twin for dialog callbacks: success returns, anything else
    // throws with the detail the dialog surfaces inline.
    public static void RelockOrThrow(Tab tab, string text, string password)
    {
        switch (Relock(tab, text, password))
        {
            case SaveSuccess:
                break;
            case SaveRedirect redirect:
                throw new IOException($"Lock redirected: {redirect.Detail}");
            case SaveFailed failed:
                throw new IOException($"Lock failed: {failed.Detail}");
            default:
                throw new IOException("Lock failed.");
        }
    }

}

internal sealed record LockHeader(string Alg, string Kdf, int Iter, string Salt, string Nonce);
