// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Remote Play günlüğü: libchiaki'nin satırları ve PS5 eşleştirmesinin sonucu ~/Library/Logs/CouchSubs/remoteplay.log
/// dosyasına yazılır (Windows'taki %LOCALAPPDATA%\CouchSubs\remoteplay.log). Eşleştirme olmazsa kullanıcı bu dosyayı
/// gönderir. Uygulama açılışta `enable()` çağırır; çağrılmazsa (testler) hiçbir şey yazılmaz. Satırlar libchiaki'nin
/// iş parçacığını bekletmeden arka planda yazılır; dosya 1 MB'yi geçince eski yarısı silinir.
public enum RemotePlayLog {
    /// Kullanıcıya hata iletisinde gösterilen yol.
    public static let displayPath = "~/Library/Logs/CouchSubs/remoteplay.log"

    public static var defaultFile: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/CouchSubs/remoteplay.log")
    }

    static let maxBytes = 1 << 20

    private final class State: @unchecked Sendable {
        let queue = DispatchQueue(label: "remoteplay.log", qos: .utility)
        let lock = NSLock()
        var file: URL?
        let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter
        }()
    }

    private static let state = State()

    public static func enable(file: URL = defaultFile) {
        state.lock.lock()
        state.file = file
        state.lock.unlock()
    }

    public static func disable() {
        flush()
        state.lock.lock()
        state.file = nil
        state.lock.unlock()
    }

    /// Bekleyen satırlar yazılana kadar bekler (testler ve kapanış için).
    public static func flush() { state.queue.sync {} }

    public static func write(_ line: String) {
        state.lock.lock()
        let file = state.file
        state.lock.unlock()
        guard let file else { return }
        let date = Date()
        state.queue.async {
            let text = "[\(state.formatter.string(from: date))] \(line)\n"
            append(Data(text.utf8), to: file)
        }
    }

    private static func append(_ data: Data, to file: URL) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: file.path)[.size]) as? Int, size > maxBytes {
                let old = try Data(contentsOf: file)
                // Eski yarı silinir; kalan kısım satır başından başlar.
                var start = old.count / 2
                if let newline = old[start...].firstIndex(of: UInt8(ascii: "\n")) { start = newline + 1 }
                try old[start...].write(to: file, options: .atomic)
            }
            if !manager.fileExists(atPath: file.path) {
                try data.write(to: file)
                return
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Günlük yazılamasa da uygulama sürer.
        }
    }
}
