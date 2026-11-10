// SPDX-License-Identifier: AGPL-3.0-only

using System.Security.Cryptography;
using CouchSubs.Core.LgTv;

namespace CouchSubs.Core.Tests;

/// LG Key Server'ın parolalı anahtarı uygulamanın içinde çözülür (Windows'ta ssh-keygen dosya iznine takılıyordu).
/// Anahtarlar yalnız test için üretildi (openssl genrsa -aes128 / -des3, parola 2FEEB2).
public class LegacyPemKeyTests
{
    private const string AesKey = """
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-128-CBC,AA662CDF46D1C77EFDF879AD733AD05F

minEkIZFLzDW4MKhHMm78YLlU5juIDfzxlukiHY8Hjj4zaGg44p2SNkAiEPqaELS
OxbsKzqZLnbH6NtvnadfaQFwx5os5WXZ/2jCBpuxPGlEpR/EN9ov9TxEWchKN06/
7Lpl6wDfxTlkkzLC/+K0FHPvi5mkrRPAjUAXKHNqVhhpL8SBHJZfyqafOifo+2Gb
o+oRR0pSiu6GtFePiBJu3vx37l4fADiRsYiEunauxZqWUDmhUc08oPL5Xvjkt7Ta
nMdTJwKOjK1raQv/EMnLbn7RompTcJ4z/sz14TBD4794mNXdFRjBEiPxJPXvwz5N
E7hMLryyy+2k5wuLuHYmpEmYLeVD8Z7aYuL0HduSjH2gqKJjh9eHNWU3RWqET0uL
9h62yOzX6tmGIOFIyykq6vrZaaCGQ0sfrPj1amAv2dpqn+yiTxjRcsOs/TzDnb2X
TS17jDKAF4lsIjNwLZQBE/apHk2ve69vUYgJ8wNRkw+Hj1a+r9hsuBeByv8o2th8
NW5o5y8buwBjHyVYaDUgaYGeBMJx9Zz7gVW9D4ai4LaJyI8nFTw61rEb9VooGjo7
w/rwvV6bmJMS9GSOfIrpvYp+ThGUO+yyj6wSyPGRrgH7o9atTikaSyMHIXsMgt9c
BenxGs0tYWsGSyYO2wreH4EFLXzOmaDNa3KiS1aeCmBbPDxj34XVYWcHh/mMAqZb
MrqK8gEmwCfNjv4YYiHFywQk+v7GYHIySCHe5v0Y6HGXBXD1ZUwb0Qh/v/Vf3fxu
ewX+DaXdj5u+qGmPtNGCxpuwEiv9w6G2dhP/VCTjU9HCqJ10r4Jf6XQxX439Ha2T
-----END RSA PRIVATE KEY-----
""";

    private const string DesKey = """
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: DES-EDE3-CBC,7C4E75EE9CCC14BA

GoQI3C3wNYZmACNrWBLIepmueNP2095KkjB2XOu/dIbRVNwLVK52lfEUR5Yh/6kc
u1FnbFAkui4oaqiYzEJ+nJJo2Wi1iSHq+TVposM+MC2JLfnXaIYp09226owmKH9G
Th841RUYwubP+lDjoe8BbUflbzmrdkXqfcXzVxmwHRrI3AahJyx1wXBERyW6D6WT
SszipsrbJovzFD5oMm06WSPsyeB1XqCaMFxlrT2TMmHH9Gq09KMFmuKGnrTYei0y
11Aep9rCKp2uex+RYhu3lUalV4HEXAbi4QpqxBy4Urln318/ZlfKSkDM/I7e8qU9
+CqtCWWxkr8ushM1k5t5FQtNEdOutXy13kaF8aG32sJwv9lQJLEmpW8s1rYZuXT8
90B4q99z5AFzn26658e4ArjTMxQYTl6Axic4qb2qJ3DggZezv4QL9t5lkaNx2Y3X
gpIxMFY1fWUmKq3CaAnboFIsCHMfdgkZFPoHFTjDlsoBdVVVoI1m7NLVTqDweuCa
LbfUsSNFqMwAS3VNULDT1qc5eLt45jyard45oC51b1ilfGKbstHYxo3acLGZfbiF
07dPUIW0ujRL8IbD7kQ9mJyN12IYHTYNG/1O6j/UFqSSqFzgY0Wxv3Hm67lt9Pg3
rJbeb9zmwOSHoCJAF8bg1Fpi0mkNhMueYqoIjPeMeZsMZ/eJ4NLxfIz2j9QDiux4
98/d4E4d3HLtoes+ayQ+w1yUiQO43+BpWqEebHiGwIe/1e+3nVQTA7OKGhKygg7U
+/yzTtqWwr+me8RfhjAfAupYx+cUZ+0iBc/XBmrwbkI7Bfn2YcIcUQ==
-----END RSA PRIVATE KEY-----
""";

    [Theory]
    [InlineData(AesKey, "7924a944e4baf8734c2f9f9e9787edac")]
    [InlineData(DesKey, "0ad305359ea07357d79b39fc083242fd")]
    public void DecryptsWithTheTvPassphrase(string pem, string derMd5)
    {
        Assert.True(LegacyPemKey.IsLegacyEncrypted(pem));
        var plain = LegacyPemKey.Decrypt(pem, "2FEEB2");
        Assert.StartsWith("-----BEGIN RSA PRIVATE KEY-----\n", plain);
        Assert.DoesNotContain("ENCRYPTED", plain);
        var body = string.Concat(plain.Split('\n').Where(l => !l.StartsWith("-----")));
        Assert.Equal(derMd5, Convert.ToHexString(MD5.HashData(Convert.FromBase64String(body))).ToLowerInvariant());
        using var rsa = RSA.Create();
        rsa.ImportFromPem(plain);
        Assert.Equal(1024, rsa.KeySize);
    }

    [Theory]
    [InlineData(AesKey)]
    [InlineData(DesKey)]
    public void WrongPassphraseIsReportedAsWrong(string pem)
    {
        var error = Assert.Throws<DevModeException>(() => LegacyPemKey.Decrypt(pem, "2FEEB3"));
        Assert.Equal(DevModeError.WrongPassphrase, error.Error);
    }

    [Fact]
    public void UnencryptedKeyIsNotLegacyEncrypted() =>
        Assert.False(LegacyPemKey.IsLegacyEncrypted("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n"));
}
