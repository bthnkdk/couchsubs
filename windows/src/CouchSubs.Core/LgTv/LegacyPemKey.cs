// SPDX-License-Identifier: AGPL-3.0-only

using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace CouchSubs.Core.LgTv;

/// <summary>
/// LG Key Server'ın verdiği parolalı anahtarı (eski PEM biçimi: "Proc-Type: 4,ENCRYPTED") uygulamanın içinde çözer.
/// Eskiden bu iş Windows'un ssh-keygen'ine yaptırılıyordu; ssh-keygen geçici dosyanın izinlerini beğenmeyince de
/// başarısız oluyor ve kullanıcı doğru parolayı yazdığı hâlde "parola yanlış" görüyordu.
/// </summary>
public static partial class LegacyPemKey
{
    /// <summary>Anahtar bu biçimde değilse false döner (çağıran başka yolu dener).</summary>
    public static bool IsLegacyEncrypted(string pem) => pem.Contains("Proc-Type: 4,ENCRYPTED", StringComparison.Ordinal);

    /// <summary>Anahtarı çözer ve parolasız PEM olarak döner. Parola yanlışsa <see cref="DevModeError.WrongPassphrase"/> atar.</summary>
    public static string Decrypt(string pem, string passphrase)
    {
        var header = HeaderPattern().Match(pem);
        var info = DekInfo().Match(pem);
        if (!header.Success || !info.Success) throw new DevModeException(DevModeError.InstallFailed, "PEM başlığı okunamadı");
        var kind = header.Groups[1].Value;
        var cipher = info.Groups[1].Value.ToUpperInvariant();
        var iv = Convert.FromHexString(info.Groups[2].Value);
        var body = pem[(info.Index + info.Length)..];
        var end = body.IndexOf("-----END", StringComparison.Ordinal);
        if (end < 0) throw new DevModeException(DevModeError.InstallFailed, "PEM sonu bulunamadı");
        var encrypted = Convert.FromBase64String(string.Concat(body[..end].Where(c => !char.IsWhiteSpace(c))));

        using SymmetricAlgorithm algorithm = cipher switch
        {
            "DES-EDE3-CBC" => TripleDES.Create(),
            "AES-128-CBC" or "AES-192-CBC" or "AES-256-CBC" => Aes.Create(),
            _ => throw new DevModeException(DevModeError.InstallFailed, "Desteklenmeyen şifre: " + cipher),
        };
        var keyLength = cipher switch { "DES-EDE3-CBC" => 24, "AES-128-CBC" => 16, "AES-192-CBC" => 24, _ => 32 };
        algorithm.Key = DeriveKey(Encoding.UTF8.GetBytes(passphrase), iv.AsSpan(0, 8), keyLength);
        algorithm.IV = iv;
        algorithm.Mode = CipherMode.CBC;
        algorithm.Padding = PaddingMode.PKCS7;

        byte[] plain;
        try
        {
            using var decryptor = algorithm.CreateDecryptor();
            plain = decryptor.TransformFinalBlock(encrypted, 0, encrypted.Length);
        }
        catch (CryptographicException)
        {
            // Yanlış parolada dolgu (padding) hemen hemen her zaman bozuk çıkar.
            throw new DevModeException(DevModeError.WrongPassphrase);
        }
        // Dolgu tesadüfen tutsa bile çözülen veri bir ASN.1 dizisi (0x30) olmalı ve uzunluğu tutmalı.
        if (!LooksLikeDer(plain)) throw new DevModeException(DevModeError.WrongPassphrase);

        var builder = new StringBuilder();
        builder.Append("-----BEGIN ").Append(kind).Append(" PRIVATE KEY-----\n");
        var base64 = Convert.ToBase64String(plain);
        for (var i = 0; i < base64.Length; i += 64) builder.Append(base64, i, Math.Min(64, base64.Length - i)).Append('\n');
        builder.Append("-----END ").Append(kind).Append(" PRIVATE KEY-----\n");
        return builder.ToString();
    }

    /// <summary>OpenSSL'in EVP_BytesToKey'i (MD5, tek tur): eski PEM anahtarlarının parola türetmesi.</summary>
    private static byte[] DeriveKey(byte[] password, ReadOnlySpan<byte> salt, int length)
    {
        var key = new List<byte>(length + 16);
        var previous = Array.Empty<byte>();
        while (key.Count < length)
        {
            var input = new byte[previous.Length + password.Length + salt.Length];
            previous.CopyTo(input, 0);
            password.CopyTo(input, previous.Length);
            salt.CopyTo(input.AsSpan(previous.Length + password.Length));
            previous = MD5.HashData(input);
            key.AddRange(previous);
        }
        return [.. key.Take(length)];
    }

    private static bool LooksLikeDer(byte[] data)
    {
        if (data.Length < 4 || data[0] != 0x30) return false;
        int length, offset;
        if (data[1] < 0x80) { length = data[1]; offset = 2; }
        else
        {
            var bytes = data[1] & 0x7F;
            if (bytes is 0 or > 3 || data.Length < 2 + bytes) return false;
            length = 0;
            for (var i = 0; i < bytes; i++) length = (length << 8) | data[2 + i];
            offset = 2 + bytes;
        }
        return offset + length == data.Length;
    }

    [GeneratedRegex(@"-----BEGIN ([A-Z ]+?) PRIVATE KEY-----")]
    private static partial Regex HeaderPattern();

    [GeneratedRegex(@"DEK-Info:\s*([A-Za-z0-9-]+),([0-9A-Fa-f]+)\s*")]
    private static partial Regex DekInfo();
}
