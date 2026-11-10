// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation

/// İsteğe bağlı yapay zekâ çevirisi: kullanıcının kendi Gemini, OpenAI ya da Claude anahtarıyla (Windows'taki
/// `AiTranslator` ile aynı). İstek kurma, bağlam, önbellek ve hata sonrası bekleme `AITranslationCore`'da; hizmete
/// ulaşılamazsa ya da kota biterse o satır Apple'ın cihaz üstü çevirisiyle çevrilir, oyun altyazısız kalmaz.
final class AITranslator: TextTranslator, OnlineTranslating {
    private let core: AITranslationCore
    private let fallback: TextTranslator

    var onFailureChanged: ((OnlineKeyState?) -> Void)? {
        didSet {
            let report = onFailureChanged
            core.onFailureChanged = { failure in report?(failure.map(OnlineKeyState.init)) }
        }
    }

    init(provider: AIProvider, key: String, model: String?, fallback: TextTranslator,
         session: URLSession = AITranslationCore.makeSession(), cache: TranslationCache = TranslationCache()) {
        core = AITranslationCore(provider: provider, key: key, model: model, session: session, cache: cache)
        self.fallback = fallback
    }

    func translate(_ text: String) async throws -> String {
        try await core.translate(text) { [fallback] line in try await fallback.translate(line) }
    }

    func spokenLines(for text: String) -> [SpokenLine] {
        core.spokenLines(for: text) { [fallback] line in fallback.spokenLines(for: line) }
    }
}

extension OnlineKeyState {
    init(_ failure: AIFailure) {
        switch failure {
        case .invalidKey: self = .invalid
        case .quotaExceeded: self = .quotaExceeded
        case .modelRejected: self = .modelRejected
        case .unreachable: self = .unreachable
        }
    }
}
