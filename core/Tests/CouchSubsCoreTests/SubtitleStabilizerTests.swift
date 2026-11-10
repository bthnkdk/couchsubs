// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class SubtitleStabilizerTests: XCTestCase {
    /// Noktalamayla bitmeyen satır yazılmakta olabilir; iki kare aynı okununca gönderilir.
    func testUnfinishedLineIsSentAfterTwoStableFrames() {
        var s = SubtitleStabilizer()
        XCTAssertEqual(s.feed("We do not have time"), .none)
        XCTAssertEqual(s.feed("We do not have time"), .translate("We do not have time"))
        XCTAssertEqual(s.feed("We do not have time"), .none)
    }

    /// Cümle bitmişse beklemeye gerek yok; hızlı konuşmada her kare önemli.
    func testFinishedSentenceIsSentOnFirstFrame() {
        for line in ["We do not have time.", "Wait!", "Who are you?", "I know…", "\"Run.\""] {
            var s = SubtitleStabilizer()
            XCTAssertEqual(s.feed(line), .translate(line), line)
            XCTAssertEqual(s.feed(line), .none, line)
        }
    }

    func testOcrNoiseDoesNotReemit() {
        var s = SubtitleStabilizer()
        _ = s.feed("The gate will not hold"); _ = s.feed("The gate will not hold")
        XCTAssertEqual(s.feed("The gale will not hold"), .none)
        XCTAssertEqual(s.feed("The gale will not hold"), .none)
    }

    /// Süslü yazıda aynı cümle her karede başka çöple okunur; TV'de iki çeviri olarak görünmemeli.
    func testGarbledRereadOfSentLineDoesNotReemit() {
        var s = SubtitleStabilizer()
        let first = "Across the deep waters, Pbo ou$3e went, hoping a boat would carry him home."
        XCTAssertEqual(s.feed(first), .translate(first))
        XCTAssertEqual(s.feed("Across the deep waters2aljd O went, Hoping a boat would carry him home."), .none)
        XCTAssertEqual(s.feed("Across the deep waters2aljd O went, Hoping a boat would carry him home."), .none)
        XCTAssertEqual(s.feed("Across the deep waters, he went."), .translate("Across the deep waters, he went."))
    }

    func testFlickeringHudDoesNotSpam() {
        var s = SubtitleStabilizer()
        var sent = 0
        for i in 0..<20 { if case .translate = s.feed(i % 2 == 0 ? "24 / 120" : "") { sent += 1 } }
        XCTAssertEqual(sent, 0)
    }

    func testTypewriterSendsCompletedLine() {
        var s = SubtitleStabilizer()
        _ = s.feed("We do"); _ = s.feed("We do not have")
        XCTAssertEqual(s.feed("We do not have time for this, boy."), .translate("We do not have time for this, boy."))
        XCTAssertEqual(s.feed("We do not have time for this, boy."), .none)
    }

    /// Altyazının kalktığına okuma sayısıyla değil süreyle karar verilir: bölge 800 ms boş kalınca silinir.
    func testEmptyRegionClearsAfterClearTime() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        _ = s.feed("Hello there"); _ = s.feed("Hello there")
        XCTAssertEqual(s.feed(""), .none)
        clock.now += SubtitleStabilizer.clearAfterMs - 1
        XCTAssertEqual(s.feed(""), .none)
        clock.now += 1
        XCTAssertEqual(s.feed(""), .clear)
        XCTAssertEqual(s.feed(""), .none)
    }

    /// Parlak arka planda okuma birkaç kare kaçar; 800 ms'den kısa boşluk ne siler ne yeniden gönderir.
    func testShortFlickerNeitherClearsNorResends() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        _ = s.feed("Hold the gate")
        XCTAssertEqual(s.feed("Hold the gate"), .translate("Hold the gate"))
        for _ in 0..<3 {
            for _ in 0..<10 { clock.now += 50; XCTAssertEqual(s.feed(""), .none) }
            for _ in 0..<4 { clock.now += 50; XCTAssertEqual(s.feed("Hold the gate"), .none) }
        }
    }

    /// Kalkan satır 1,5 sn içinde geri gelirse yeniden çevrilmez; çevirisi yeniden gösterilsin diye restore döner.
    func testLineReturningSoonAfterClearIsRestored() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        XCTAssertEqual(s.feed("Hold the gate."), .translate("Hold the gate."))
        _ = s.feed("")
        clock.now += SubtitleStabilizer.clearAfterMs
        XCTAssertEqual(s.feed(""), .clear)
        clock.now += SubtitleStabilizer.restoreWithinMs
        XCTAssertEqual(s.feed("Hold the gate"), .none)
        XCTAssertEqual(s.feed("Hold the gate"), .restore("Hold the gate."))
        XCTAssertEqual(s.feed("Hold the gate."), .none)
        // Geri gelen satır da kalkınca silinir.
        _ = s.feed("")
        clock.now += SubtitleStabilizer.clearAfterMs
        XCTAssertEqual(s.feed(""), .clear)
    }

    /// Daha geç gelen aynı satır gerçek bir tekrardır (oyunda aynı söz yeniden söylendi); yeniden çevrilir.
    func testLineReturningLaterIsTranslatedAgain() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        _ = s.feed("Hold the gate.")
        _ = s.feed("")
        clock.now += SubtitleStabilizer.clearAfterMs
        XCTAssertEqual(s.feed(""), .clear)
        clock.now += SubtitleStabilizer.restoreWithinMs + 1
        XCTAssertEqual(s.feed("Hold the gate."), .translate("Hold the gate."))
    }

    /// Okuma iki satır arasında gidip gelirse (yerine başkası geldi, sonra geri döndü) eski satır yeniden çevrilmez.
    func testReplacedLineComingBackIsRestored() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        XCTAssertEqual(s.feed("Hold the gate."), .translate("Hold the gate."))
        clock.now += 100
        XCTAssertEqual(s.feed("Run!"), .translate("Run!"))
        clock.now += 100
        XCTAssertEqual(s.feed("Hold the gate."), .restore("Hold the gate."))
        clock.now += 100
        XCTAssertEqual(s.feed("Run!"), .restore("Run!"))
    }

    /// İki konuşmacı neredeyse aynı sözleri söylüyor; ikinci satır da çevrilmeli.
    func testTwoSpeakersWithOverlappingWordsAreBothTranslated() {
        let pairs = [
            ("Where are you going?", "Where are you going, boy?"),
            ("Where are you going, boy?", "Where are you going?"),
            ("We need to leave this place before the sun goes down.", "We need to leave this place before the sun goes down, boy."),
        ]
        for (first, second) in pairs {
            let clock = TestClock()
            var s = SubtitleStabilizer(clock: clock.read)
            XCTAssertEqual(s.feed(first), .translate(first))
            clock.now += 50
            XCTAssertEqual(s.feed(second), .translate(second), "\(first) / \(second)")
        }
    }

    func testAlreadyTranslatedIsSkipped() {
        var s = SubtitleStabilizer()
        XCTAssertFalse(s.shouldSend(source: "Kullanıcı Ekle Oturum Açtı", translation: "Kullanıcı Ekle Oturum Açtı"))
        XCTAssertTrue(s.shouldSend(source: "Add user", translation: "Kullanıcı ekle"))
    }

    func testResetClearsOnlyAfterSomethingWasSent() {
        var s = SubtitleStabilizer()
        XCTAssertEqual(s.reset(), .none)
        _ = s.feed("Hello there"); _ = s.feed("Hello there")
        XCTAssertEqual(s.reset(), .clear)
        XCTAssertEqual(s.reset(), .none)
    }
}

final class SubtitleStabilizerRetryTests: XCTestCase {
    /// Çevirisi başarısız olan satır ekranda kaldıkça yeniden denenebilmeli; ama saniyede en çok bir kez.
    func testForgottenLineIsTranslatedAgainAfterBackoff() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        _ = s.feed("Hold the gate")
        XCTAssertEqual(s.feed("Hold the gate"), .translate("Hold the gate"))
        s.forgetSent()
        for _ in 0..<19 { clock.now += 50; XCTAssertEqual(s.feed("Hold the gate"), .none) }
        clock.now += 50
        XCTAssertEqual(s.feed("Hold the gate"), .translate("Hold the gate"))
    }

    /// Bekleme yalnız başarısız satır için: başka bir satır hemen çevrilir.
    func testBackoffDoesNotDelayANewLine() {
        let clock = TestClock()
        var s = SubtitleStabilizer(clock: clock.read)
        _ = s.feed("Hold the gate"); _ = s.feed("Hold the gate")
        s.forgetSent()
        XCTAssertEqual(s.feed("Run!"), .translate("Run!"))
    }
}

/// Testlerde elle ilerletilen saat (milisaniye).
final class TestClock: @unchecked Sendable {
    var now = 1_000_000
    func read() -> Int { now }
}
