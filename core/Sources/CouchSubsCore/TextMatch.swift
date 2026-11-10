// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// OCR çıktılarını karşılaştırmak için sadeleştirme ve gürültüye dayanıklı benzerlik.
public enum TextMatch {
    /// Küçük harf, yalnız harf/rakam, tek boşluk.
    public static func normalize(_ s: String) -> String {
        let scalars = s.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Levenshtein oranı `threshold` ve üstündeyse benzer sayılır. Boş metin hiçbir metne benzemez.
    public static func isSimilar(_ a: String, _ b: String, threshold: Double = 0.85) -> Bool {
        if a == b { return !a.isEmpty }
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return false }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var row = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count)) >= threshold
    }

    /// Satırları ayrı ayrı sadeleştirip alt alta birleştirir; `isSameSubtitle` kaçırılan satırı bundan anlar.
    public static func normalizeRows(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalize(String($0)) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Yeni okuma, gönderilmiş altyazının yeniden okuması mı (sadeleştirilmiş metinler; `sent` satırları
    /// `normalizeRows` ile alt alta verilebilir). Süslü yazı tipinde ya da solarken OCR bir iki sözcüğü her
    /// karede başka çöpe çevirir ("ou$3e", "waters2aljd") ya da iki satırlık altyazının bir satırını kaçırır; karakter
    /// benzerliği düşse de sözcükler aynı kalır. Rakam karışmış sözcükler ve tek harfler çöp sayılıp karşılaştırmaya girmez.
    /// Başına ya da sonuna sözcük eklenmiş metin (daktilo efekti, "Nereye gidiyorsun?" / "Nereye gidiyorsun evlat?") yenidir;
    /// sondan kısalmış metin ise ancak tam bir satırı eksikse aynı altyazıdır.
    public static func isSameSubtitle(_ reread: String, _ sent: String) -> Bool {
        let rows = sent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let flat = rows.joined(separator: " ")
        let x = cleanWords(reread), y = cleanWords(flat)
        // Uzayan metin (daktilo efekti ya da aynı sözlerle başlayan yeni satır) karakterce benzese de yenidir.
        if !y.isEmpty, x.count > y.count, x.starts(with: y) || x.suffix(y.count).elementsEqual(y) { return false }
        if isSimilar(reread, flat) { return true }
        // Baştan ya da sondan kesilmiş okuma: altyazının yalnız tam satırları okunduysa aynıdır, yoksa başka bir cümledir.
        if !x.isEmpty, x.count < y.count, y.starts(with: x) || y.suffix(x.count).elementsEqual(x) {
            return isWholeRows(x.count, rows: rows, fromStart: y.starts(with: x))
        }
        var remaining = y
        var shared = 0
        for word in x {
            if let index = remaining.firstIndex(of: word) {
                remaining.remove(at: index)
                shared += 1
            }
        }
        // Arasından çöp sözcükler düşmüş okuma: yeni okumanın sözcüklerinin hemen hepsi gönderilende var.
        if x.count >= 4, x.count <= y.count, Double(shared) >= Double(x.count) * 0.85 { return true }
        // Kısa satırda tek sözcük anlamı değiştirir ("where is the boy" / "ship"); orada yalnız karakter benzerliği geçerli.
        let longer = max(x.count, y.count), shorter = min(x.count, y.count)
        guard shorter >= 6, Double(shorter) / Double(longer) >= 0.75 else { return false }
        return Double(shared) / Double(longer) >= 0.75
    }

    /// Baştan (ya da sondan) `count` sözcük tam satırlara denk geliyor mu.
    private static func isWholeRows(_ count: Int, rows: [String], fromStart: Bool) -> Bool {
        var total = 0
        for row in fromStart ? rows : rows.reversed() {
            total += cleanWords(row).count
            if total == count { return true }
            if total > count { return false }
        }
        return false
    }

    private static func cleanWords(_ normalized: String) -> [Substring] {
        // Tek harfler ("a", "I" ya da OCR'ın uydurduğu "O") karşılaştırmaya bir şey katmaz.
        normalized.split(separator: " ").filter { $0.count > 1 && !$0.contains(where: \.isNumber) }
    }
}
