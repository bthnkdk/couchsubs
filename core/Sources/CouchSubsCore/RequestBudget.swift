// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kayan bir dakikalık pencerede en çok `perMinute` istek hakkı (Windows'taki CouchSubs.Core/RequestBudget.cs ile aynı).
/// Gemini'nin ücretsiz katmanı dakikadaki istek sayısını sınırlar; sınırın üstüne çıkan istek 429 alır ve beklemek
/// gerekir. Hak önceden sayılınca istek hiç gönderilmez, o satır hemen yerel çeviriyle çevrilir; böylece hem gecikme hem
/// hata uyarısı olmaz ve pencere boşaldıkça hizmete kendiliğinden dönülür.
public final class RequestBudget: @unchecked Sendable {
    /// Pencerenin uzunluğu.
    public static let window: TimeInterval = 60

    private let lock = NSLock()
    private let now: () -> Date
    private var limit: Int
    /// Penceredeki isteklerin zamanları, eskiden yeniye.
    private var sent: [Date] = []

    public init(perMinute: Int, now: @escaping () -> Date = Date.init) {
        limit = max(1, perMinute)
        self.now = now
    }

    /// Şu anki dakikalık sınır.
    public var perMinute: Int { lock.withLock { limit } }

    /// Hak varsa bir istek hakkı kullanır ve true döner; yoksa false (istek gönderilmemeli).
    public func take() -> Bool {
        lock.withLock {
            let time = now()
            sent.removeAll { time.timeIntervalSince($0) >= Self.window }
            guard sent.count < limit else { return false }
            sent.append(time)
            return true
        }
    }

    /// Hizmet daha düşük bir sınır bildirdi (429 yanıtındaki "quotaValue"); yükseltmez.
    public func lower(to perMinute: Int) {
        lock.withLock { limit = max(1, min(limit, perMinute)) }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: RequestBudget] = [:]

    /// Modelin uygulama genelindeki ortak hakkı (Google sınırı proje ve model başına sayar); modelin sınırı yoksa nil.
    public static func shared(provider: AIProvider, model: AIModel) -> RequestBudget? {
        guard let perMinute = model.requestsPerMinute else { return nil }
        return registryLock.withLock {
            let id = provider.engineID(model: model.id)
            if let budget = registry[id] { return budget }
            let budget = RequestBudget(perMinute: perMinute)
            registry[id] = budget
            return budget
        }
    }
}
