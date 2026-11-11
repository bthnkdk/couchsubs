// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Foundation

/// Oyun paketinin anahtarı: ekranda okunan İngilizce satırın sadeleştirilmiş hâlinin SHA-256'sının ilk 8 baytı (hex).
/// Paketlerde İngilizce metin yoktur, yalnız bu anahtar ve Türkçesi. Windows'taki CouchSubs.Core/GamePacks.cs ile
/// birebir aynı adımlar; ortak deneme verisi Tests/CouchSubsCoreTests/Fixtures/golden-vectors.json.
public enum PackKey {
    /// Biçim etiketi: en çok 40 karakterlik `<…>` ("<b>", "<h>", "</>").
    static let maxTagLength = 40

    /// 1. etiketler boşluk olur, 2. NFKC, 3. küçük harf, 4. NFD ile aksan ve işaretler atılır,
    /// 5. harf ve rakam dışındaki her şey boşluk olur, 6. boşluklar teklenir, baş ve son kırpılır.
    public static func canon(_ text: String) -> String {
        let lowered = stripTags(text).precomposedStringWithCompatibilityMapping.lowercased()
        var output = String.UnicodeScalarView()
        var gap = false
        for scalar in lowered.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                if gap, !output.isEmpty { output.append(" ") }
                gap = false
                output.append(scalar)
            default:
                gap = true
            }
        }
        return String(output)
    }

    /// 16 haneli küçük harf hex anahtar; satırda harf ya da rakam yoksa nil.
    public static func key(_ text: String) -> String? {
        let canon = canon(text)
        guard !canon.isEmpty else { return nil }
        return SHA256.hash(data: Data(canon.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Anahtarın sayı hâli (sözlükte daha az yer tutar); geçersizse nil.
    public static func number(_ key: String) -> UInt64? {
        guard key.utf8.count == 16 else { return nil }
        return UInt64(key, radix: 16)
    }

    /// `<…>` etiketlerini (en çok 40 karakter, içinde `<` ya da `>` yok) `replacement` ile değiştirir.
    /// Python'daki `re.sub(r"<[^<>]{0,40}>", " ", s)` ile aynı: kod noktası sayılır.
    public static func stripTags(_ text: String, replacement: String = " ") -> String {
        guard text.contains("<") else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "<" {
                var end = index + 1
                while end < scalars.count, end - index - 1 <= maxTagLength, scalars[end] != "<", scalars[end] != ">" { end += 1 }
                if end < scalars.count, scalars[end] == ">", end - index - 1 <= maxTagLength {
                    output.append(contentsOf: replacement.unicodeScalars)
                    index = end + 1
                    continue
                }
            }
            output.append(scalars[index])
            index += 1
        }
        return String(output)
    }
}

/// Bir oyunun çeviri paketi. Dosya gzip'li JSON'dur: `{"format":1,"id":…,"title":…,"entries":{anahtar: Türkçe}}`;
/// yalnız `{anahtar: Türkçe}` nesnesi de kabul edilir (adı dosya adından gelir).
public struct GamePack: Sendable {
    public let id: String
    public let title: String
    public let entries: [UInt64: String]

    public enum LoadError: Error { case notJSON, unsupportedFormat, empty }

    public init(id: String, title: String, entries: [UInt64: String]) {
        self.id = id
        self.title = title
        self.entries = entries
    }

    /// `name`: dosya adı uzantısız ("mafia-the-old-country"); düz biçimde kimlik ve başlık olur.
    public static func decode(_ data: Data, name: String) throws -> GamePack {
        let json = try Gzip.isCompressed(data) ? Gzip.decompress(data) : data
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw LoadError.notJSON }
        let raw: [String: Any]
        var id = name
        var title = name
        if let wrapped = object["entries"] as? [String: Any] {
            if let format = object["format"] as? Int, format != 1 { throw LoadError.unsupportedFormat }
            raw = wrapped
            if let value = object["id"] as? String, !value.isEmpty { id = value }
            if let value = object["title"] as? String, !value.isEmpty { title = value } else { title = id }
        } else {
            raw = object
        }
        var entries: [UInt64: String] = [:]
        entries.reserveCapacity(raw.count)
        for (key, value) in raw {
            guard let number = PackKey.number(key.lowercased()), let turkish = value as? String else { continue }
            let text = cleaned(turkish)
            if !text.isEmpty { entries[number] = text }
        }
        guard !entries.isEmpty else { throw LoadError.empty }
        return GamePack(id: id, title: title, entries: entries)
    }

    /// Paketteki Türkçede de oyunun biçim etiketleri kalmış olabilir ("<b><h>…</></>"); TV'de görünmesinler.
    static func cleaned(_ text: String) -> String {
        guard text.contains("<") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return PackKey.stripTags(text, replacement: "")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pakette bulunan satırın Türkçesi ve seslendirilecek cümleleri.
public struct PackMatch: Equatable, Sendable {
    public var text: String
    public var spoken: [SpokenLine]

    public init(text: String, spoken: [SpokenLine]) {
        self.text = text
        self.spoken = spoken
    }
}

/// Uygulamayla gelen ve kullanıcının klasörüne bırakılan paketler; hepsi tek bir sözlükte birleşir.
/// Sıra: uygulamanınkiler, sonra kullanıcınınkiler (dosya adına göre); aynı anahtarda sonraki kazanır,
/// aynı kimlikli pakette kullanıcının dosyası uygulamanınkinin yerine geçer.
public final class GamePackLibrary: @unchecked Sendable {
    public struct Info: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let entries: Int
        /// Kullanıcının klasöründen geldiyse false.
        public let builtIn: Bool
    }

    /// Uygulamayla gelen paketler (core/Sources/CouchSubsCore/Resources/packs).
    public static var bundledDirectory: URL? { Bundle.module.url(forResource: "packs", withExtension: nil) }

    /// ~/Library/Application Support/CouchSubs/packs: denemeciler yeni paketi buraya bırakır.
    public static var userDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CouchSubs", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true)
    }

    private let directories: [(url: URL, builtIn: Bool)]
    private let lock = NSLock()
    private var loaded = false
    private var entries: [UInt64: String] = [:]
    private var infos: [Info] = []

    public init(bundled: URL?, user: URL?) {
        directories = [bundled.map { (url: $0, builtIn: true) }, user.map { (url: $0, builtIn: false) }].compactMap { $0 }
    }

    /// Kurulu paketler; ilk çağrıda yüklenir.
    public var packs: [Info] {
        lock.withLock {
            loadIfNeeded()
            return infos
        }
    }

    /// Paketleri (yeniden) okur. Bozuk dosya sessizce atlanır.
    public func reload() {
        lock.withLock {
            loaded = false
            loadIfNeeded()
        }
    }

    /// Yüklemeyi şimdi yapar (açılışta arka planda çağrılır; ilk altyazı beklemesin).
    public func warmUp() { _ = packs }

    /// Anahtarın Türkçesi.
    public func translation(forKey key: String) -> String? {
        guard let number = PackKey.number(key) else { return nil }
        return lock.withLock {
            loadIfNeeded()
            return entries[number]
        }
    }

    /// Satırın paketteki Türkçesi (bkz. `PackLookup`); yoksa nil.
    public func match(_ text: String) -> PackMatch? {
        let entries = lock.withLock {
            loadIfNeeded()
            return self.entries
        }
        guard !entries.isEmpty else { return nil }
        return PackLookup.match(text) { line in PackKey.key(line).flatMap(PackKey.number).flatMap { entries[$0] } }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var packs: [(pack: GamePack, builtIn: Bool)] = []
        for (directory, builtIn) in directories {
            for file in Self.packFiles(in: directory) {
                guard let data = try? Data(contentsOf: file),
                      let pack = try? GamePack.decode(data, name: Self.baseName(file)) else { continue }
                packs.removeAll { $0.pack.id == pack.id }
                packs.append((pack, builtIn))
            }
        }
        var merged: [UInt64: String] = [:]
        merged.reserveCapacity(packs.reduce(0) { $0 + $1.pack.entries.count })
        for (pack, _) in packs { merged.merge(pack.entries) { _, later in later } }
        entries = merged
        infos = packs.map { Info(id: $0.pack.id, title: $0.pack.title, entries: $0.pack.entries.count, builtIn: $0.builtIn) }
    }

    static func packFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(".json.gz") || $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// "mafia.json.gz" → "mafia"
    static func baseName(_ file: URL) -> String {
        var name = file.lastPathComponent
        for suffix in [".gz", ".json"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        return name
    }
}

/// Satırı pakette arar. Sırayla: satırın tamamı; konuşmacı etiketi ("ENZO: ") varsa etiketsiz hâli (etiket çeviriye
/// eklenir); birden çok satırsa her satır ayrı ayrı; birden çok cümleyse her cümle ayrı ayrı. Parçalı aramada parçaların
/// hepsi bulunmalıdır, yoksa satır motorla çevrilir. Etiket ve ayraçlar ücretli motorlardaki gibi korunur
/// (`SubtitleSegmenter`).
public enum PackLookup {
    public static func match(_ text: String, find: (String) -> String?) -> PackMatch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let found = single(trimmed, find: find) { return found.match }

        // Her satır ayrı bir altyazı olabilir (iki konuşmacı alt alta).
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 {
            var pieces: [SubtitleSegmenter.Piece] = []
            var translations: [String?] = []
            var all = true
            for (index, line) in lines.enumerated() {
                guard let found = single(line, find: find) else { all = false; break }
                if index > 0 {
                    pieces.append(SubtitleSegmenter.Piece("\n", translate: false))
                    translations.append(nil)
                }
                pieces += found.pieces
                translations += found.translations
            }
            if all { return result(pieces, translations) }
        }

        // Cümle cümle (etiket, tire ve ayraçlar olduğu gibi kalır).
        let pieces = SubtitleSegmenter.split(trimmed)
        guard pieces.filter(\.translate).count > 1 else { return nil }
        var translations: [String?] = []
        for piece in pieces {
            guard piece.translate else { translations.append(nil); continue }
            guard let turkish = find(piece.text) else { return nil }
            translations.append(turkish)
        }
        return result(pieces, translations)
    }

    /// Tek satır: başında konuşmacı etiketi ya da diyalog tiresi varsa önce onsuz hâli (etiket/tire çeviriye eklenir),
    /// sonra tamamı.
    private static func single(_ line: String, find: (String) -> String?)
        -> (match: PackMatch, pieces: [SubtitleSegmenter.Piece], translations: [String?])? {
        let split = SubtitleSegmenter.split(line)
        if let first = split.first, !first.translate, split.count > 1, !split.contains(where: { $0.text == "\n" }) {
            let body = split.dropFirst().map(\.text).joined()
            if let turkish = find(body) {
                let pieces = [first, SubtitleSegmenter.Piece(body, translate: true)]
                return (result(pieces, [nil, turkish]), pieces, [nil, turkish])
            }
        }
        guard let turkish = find(line) else { return nil }
        let pieces = [SubtitleSegmenter.Piece(line, translate: true)]
        return (result(pieces, [turkish]), pieces, [turkish])
    }

    private static func result(_ pieces: [SubtitleSegmenter.Piece], _ translations: [String?]) -> PackMatch {
        var text = ""
        for (index, piece) in pieces.enumerated() { text += translations[index] ?? piece.text }
        return PackMatch(text: text, spoken: SpeechScript.lines(pieces: pieces, translations: translations))
    }
}

/// gzip dosyasını açar (RFC 1952 başlığı elle okunur, gövde Foundation'ın DEFLATE açıcısıyla açılır).
enum Gzip {
    enum Failure: Error { case corrupt }

    static func isCompressed(_ data: Data) -> Bool {
        data.count >= 18 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { throw Failure.corrupt }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.corrupt }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT: sıfırla biten metin
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC
        guard offset < bytes.count - 8 else { throw Failure.corrupt }
        let body = Data(bytes[offset..<(bytes.count - 8)])
        guard let output = try? (body as NSData).decompressed(using: .zlib) as Data else { throw Failure.corrupt }
        let size = bytes[(bytes.count - 4)...].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard UInt32(truncatingIfNeeded: output.count) == size else { throw Failure.corrupt }
        return output
    }
}
