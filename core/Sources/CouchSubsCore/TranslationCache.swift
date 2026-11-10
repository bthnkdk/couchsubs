// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Çevrilmiş satır ve cümlelerin kalıcı önbelleği (Windows'taki `TranslationCache` ile aynı dosya biçimi).
/// Oyunlar aynı satırları oturumdan oturuma tekrarlar ("Stay close.", "Over here!"); diskte duran çeviri 0 ms sürer,
/// DeepL kotasından da yemez. Her çeviri motoru ve dil çifti kendi dosyasını kullanır: motor değişince eski motorun
/// çevirisi gösterilmez.
///
/// Dosya her satırı bir JSON dizisi (`["kaynak","çeviri"]`) olan, sonuna eklenen bir kayıttır. Bellekte en çok
/// `limit` kayıt tutulur; en uzun süredir kullanılmayanlar atılır. Dosya kayıt sınırının iki katına uzayınca
/// bellektekilerle yeniden yazılır. Disk hatası çeviriyi durdurmaz: önbellek o zaman yalnız bellekte çalışır.
public final class TranslationCache: @unchecked Sendable {
    public static let defaultLimit = 20_000
    /// Dosya adındaki biçim sürümü: çeviri öncesi temizlik kuralları değişince eski çeviriler bırakılabilsin.
    public static let formatVersion = 1

    private let file: URL?
    private let limit: Int
    private let lock = NSLock()
    private var entries: [String: (value: String, used: Int)] = [:]
    private var tick = 0
    private var loaded = false
    /// Dosyadaki satır sayısı (yinelenenler ve atılanlar dahil).
    private var fileLines = 0

    /// `file` nil ise önbellek yalnız bellekte tutulur (testler, geçici çevirmenler).
    public init(file: URL? = nil, limit: Int = TranslationCache.defaultLimit) {
        self.file = file
        self.limit = max(1, limit)
    }

    /// Motor ve dil çiftine göre dosya: `v1-apple-en-tr.jsonl`.
    public static func file(in directory: URL, engine: String, source: String, target: String) -> URL {
        let name = ["v\(formatVersion)", engine, source, target].map(safe).joined(separator: "-")
        return directory.appendingPathComponent(name + ".jsonl")
    }

    private static let openLock = NSLock()
    nonisolated(unsafe) private static var opened: [URL: TranslationCache] = [:]

    /// Aynı dosya için hep aynı önbellek döner; çevirmen her oturumda yeniden kurulsa da dosya bir kez okunur.
    public static func shared(in directory: URL, engine: String, source: String, target: String) -> TranslationCache {
        let url = file(in: directory, engine: engine, source: source, target: target)
        return openLock.withLock {
            if let cache = opened[url] { return cache }
            let cache = TranslationCache(file: url)
            opened[url] = cache
            return cache
        }
    }

    public var count: Int { lock.withLock { loadIfNeeded(); return entries.count } }

    public func value(for key: String) -> String? {
        lock.withLock {
            loadIfNeeded()
            guard let entry = entries[key] else { return nil }
            tick += 1
            entries[key] = (entry.value, tick)
            return entry.value
        }
    }

    public func store(_ value: String, for key: String) {
        guard !key.isEmpty, !value.isEmpty else { return }
        lock.withLock {
            loadIfNeeded()
            if entries[key]?.value == value {
                tick += 1
                entries[key] = (value, tick)
                return
            }
            tick += 1
            entries[key] = (value, tick)
            evictIfNeeded()
            append(key, value)
        }
    }

    /// Dosyayı ilk kullanımda okur (çeviri ana iş parçacığının dışında olduğu için arayüzü bekletmez).
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file) else { return }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            fileLines += 1
            guard let pair = try? JSONSerialization.jsonObject(with: Data(line)) as? [String], pair.count == 2,
                  !pair[0].isEmpty, !pair[1].isEmpty else { continue }
            tick += 1
            entries[pair[0]] = (pair[1], tick)
        }
        evictIfNeeded()
        if fileLines > entries.count + limit / 2 { rewrite() }
    }

    private func evictIfNeeded() {
        guard entries.count > limit else { return }
        // Her seferinde tek kayıt atmak yerine onda biri atılır; sıralama seyrek yapılır.
        let drop = entries.count - limit + limit / 10
        let oldest = entries.sorted { $0.value.used < $1.value.used }.prefix(drop)
        for (key, _) in oldest { entries[key] = nil }
    }

    private func append(_ key: String, _ value: String) {
        guard let file else { return }
        if fileLines >= limit * 2 { return rewrite() }
        guard let line = Self.line(key, value) else { return }
        do {
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try line.write(to: file)
            }
            fileLines += 1
        } catch {
            // Disk dolu ya da yazılamıyor: önbellek bellekte çalışmaya devam eder.
        }
    }

    /// Dosyayı bellektekilerle, en eski kullanılandan yeniye doğru yeniden yazar.
    private func rewrite() {
        guard let file else { return }
        var data = Data()
        for (key, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) {
            if let line = Self.line(key, entry.value) { data.append(line) }
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            fileLines = entries.count
        } catch {
            // Yazılamadıysa eski dosya yerinde kalır.
        }
    }

    private static func line(_ key: String, _ value: String) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: [key, value], options: [.withoutEscapingSlashes]) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func safe(_ part: String) -> String {
        String(part.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
    }
}
