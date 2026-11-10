// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Windows'taki TranslationCacheTests ile aynı durumlar.
final class TranslationCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-cache-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(engine: String = "deepl") -> URL {
        TranslationCache.file(in: directory, engine: engine, source: "en", target: "tr")
    }

    func testTranslationsSurviveRestart() {
        let first = TranslationCache(file: file())
        first.store("Kapıyı kapat.", for: "Close the door.")
        first.store("ATREUS: Baba!", for: "ATREUS: Father!")

        let second = TranslationCache(file: file())
        XCTAssertEqual(second.value(for: "Close the door."), "Kapıyı kapat.")
        XCTAssertEqual(second.value(for: "ATREUS: Father!"), "ATREUS: Baba!")
        XCTAssertNil(second.value(for: "Run!"))
    }

    func testEnginesHaveSeparateFiles() {
        TranslationCache(file: file(engine: "deepl")).store("DeepL çevirisi", for: "Run!")
        XCTAssertNil(TranslationCache(file: file(engine: "apple")).value(for: "Run!"))
        XCTAssertEqual(file(engine: "apple").lastPathComponent, "v1-apple-en-tr.jsonl")
    }

    func testLinesWithQuotesAndNewlinesRoundTrip() {
        let source = "KRATOS: \"Boy.\"\nATREUS: Yes?"
        TranslationCache(file: file()).store("KRATOS: \"Evlat.\"\nATREUS: Evet?", for: source)
        XCTAssertEqual(TranslationCache(file: file()).value(for: source), "KRATOS: \"Evlat.\"\nATREUS: Evet?")
    }

    func testLeastRecentlyUsedEntriesAreDropped() {
        let cache = TranslationCache(file: file(), limit: 10)
        for i in 0..<10 { cache.store("t\(i)", for: "s\(i)") }
        // s0 yeni kullanıldı; atılan en eskiler s1 ve sonrası olur.
        XCTAssertEqual(cache.value(for: "s0"), "t0")
        cache.store("t10", for: "s10")
        XCTAssertLessThanOrEqual(cache.count, 10)
        XCTAssertEqual(cache.value(for: "s0"), "t0")
        XCTAssertNil(cache.value(for: "s1"))
        XCTAssertEqual(cache.value(for: "s10"), "t10")
    }

    func testFileIsCompactedWhenItGrows() throws {
        let cache = TranslationCache(file: file(), limit: 5)
        for round in 0..<6 {
            for i in 0..<5 { cache.store("t\(i)-\(round)", for: "s\(i)") }
        }
        let lines = try String(contentsOf: file(), encoding: .utf8).split(separator: "\n")
        XCTAssertLessThanOrEqual(lines.count, 10)
        let reloaded = TranslationCache(file: file(), limit: 5)
        XCTAssertEqual(reloaded.value(for: "s3"), "t3-5")
    }

    func testBrokenLinesAreSkipped() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "[\"Run!\",\"Koş!\"]\nnot json\n[\"only one\"]\n".write(to: file(), atomically: true, encoding: .utf8)
        let cache = TranslationCache(file: file())
        XCTAssertEqual(cache.value(for: "Run!"), "Koş!")
        XCTAssertEqual(cache.count, 1)
    }

    func testEmptyValuesAreNotStored() {
        let cache = TranslationCache(file: file())
        cache.store("", for: "Run!")
        XCTAssertNil(cache.value(for: "Run!"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file().path))
    }

    func testMemoryOnlyCacheWorksWithoutFile() {
        let cache = TranslationCache()
        cache.store("Koş!", for: "Run!")
        XCTAssertEqual(cache.value(for: "Run!"), "Koş!")
    }

    func testSharedReturnsOneCachePerFile() {
        let a = TranslationCache.shared(in: directory, engine: "apple", source: "en", target: "tr")
        let b = TranslationCache.shared(in: directory, engine: "apple", source: "en", target: "tr")
        let c = TranslationCache.shared(in: directory, engine: "deepl", source: "en", target: "tr")
        XCTAssertTrue(a === b)
        XCTAssertFalse(a === c)
    }
}
