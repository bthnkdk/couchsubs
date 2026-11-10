// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

final class ButtonPromptTests: XCTestCase {
    func testControllerHintsAreRecognized() {
        for line in ["R2 Swing", "[R2] Swing", "L1 + R1 Spartan Rage", "△ Pick up", "✕ Jump", "□ Light Attack",
                     "X Interact", "O Back", "Press ✕ to jump", "Hold R2 to aim", "Press X to continue", "OPTIONS Menu"] {
            XCTAssertTrue(ButtonPrompts.isPrompt(line), line)
        }
    }

    func testDialogueIsKept() {
        for line in ["Boy, hold still.", "Press on, we're almost there.", "X marks the spot.", "Take the R2 exit, then left.",
                     "Kratos: We go now.", "O brother, where art thou?", "Use your head, boy.", "Hold on!"] {
            XCTAssertFalse(ButtonPrompts.isPrompt(line), line)
        }
    }

    func testReadingDropsPromptLinesAndKeepsTheirBoxesOut() {
        let reading = Reading(lines: [
            TextLine("We should keep moving.", box: TextBox(left: 0.2, top: 0.6, right: 0.8, bottom: 0.7)),
            TextLine("R2 Swing", box: TextBox(left: 0.85, top: 0.9, right: 0.98, bottom: 0.95)),
        ]).withoutButtonPrompts()
        XCTAssertEqual(reading.text, "We should keep moving.")
        XCTAssertEqual(reading.box, TextBox(left: 0.2, top: 0.6, right: 0.8, bottom: 0.7))
    }

    func testBoxesArePlacedInTheFrame() {
        let area = TextBox(left: 0.1, top: 0.6, right: 0.9, bottom: 1.0)
        let box = TextBox(left: 0.25, top: 0.5, right: 0.75, bottom: 1.0).placed(in: area)
        XCTAssertEqual(box.left, 0.3, accuracy: 1e-9)
        XCTAssertEqual(box.top, 0.8, accuracy: 1e-9)
        XCTAssertEqual(box.right, 0.7, accuracy: 1e-9)
        XCTAssertEqual(box.bottom, 1.0, accuracy: 1e-9)
    }
}

final class SubtitleSegmenterTests: XCTestCase {
    private func pieces(_ text: String) -> [String] {
        SubtitleSegmenter.split(text).map { ($0.translate ? "+" : "=") + $0.text }
    }

    func testWrappedLinesBecomeOneSentence() {
        XCTAssertEqual(pieces("We should keep\nmoving, boy."), ["+We should keep moving, boy."])
    }

    func testSpeakerLabelsAreNotTranslated() {
        XCTAssertEqual(pieces("ATREUS: Father, look!"), ["=ATREUS: ", "+Father, look!"])
        XCTAssertEqual(pieces("Kratos: Stay close.\nMimir: Aye, brother."),
                       ["=Kratos: ", "+Stay close.", "=\n", "=Mimir: ", "+Aye, brother."])
        XCTAssertEqual(pieces("Old Man: Who goes there?"), ["=Old Man: ", "+Who goes there?"])
    }

    /// Windows'taki MarianTranslatorTests.SpeakerNamesAreNotTranslated ile aynı örnekler: çevirmene giden yalnız cümledir.
    func testSpeakerNamesAreNotSentToTheTranslator() {
        let cases = [
            ("ATREUS: Father!", ["Father!"]),
            ("OLD MAN: Who goes there?", ["Who goes there?"]),
            ("Mimir Head: Brother, wait.", ["Brother, wait."]),
            ("Note: Press X.", ["Note: Press X."]),
        ]
        for (text, sent) in cases {
            XCTAssertEqual(SubtitleSegmenter.split(text).filter(\.translate).map(\.text), sent, text)
        }
        let names = SpeakerNames()
        names.learn(from: SubtitleSegmenter.split("OLD MAN: Hello."))
        XCTAssertEqual(SubtitleSegmenter.normalizeCase("RUN, OLD MAN!", names: names.all), "Run, Old Man!")
    }

    func testGameHeadingsAreTranslated() {
        XCTAssertEqual(pieces("Objective: Find the gate."), ["+Objective: Find the gate."])
    }

    func testSentencesAreSplitButAbbreviationsAreNot() {
        XCTAssertEqual(pieces("Boy! What is that? Ask Mr. Smith."), ["+Boy!", "= ", "+What is that?", "= ", "+Ask Mr. Smith."])
        XCTAssertEqual(pieces("Wait... what was that?"), ["+Wait... what was that?"])
    }

    func testDialogueDashesStay() {
        XCTAssertEqual(pieces("- Run!\n- Where?"), ["=- ", "+Run!", "=\n", "=- ", "+Where?"])
    }

    func testAllCapsSentenceIsNormalizedKeepingNames() {
        XCTAssertEqual(SubtitleSegmenter.normalizeCase("THE GATE WILL NOT HOLD, ATREUS. I KNOW."),
                       "The gate will not hold, atreus. I know.")
        XCTAssertEqual(SubtitleSegmenter.normalizeCase("THE GATE WILL NOT HOLD, ATREUS.", names: ["ATREUS"]),
                       "The gate will not hold, Atreus.")
        XCTAssertEqual(SubtitleSegmenter.normalizeCase("BOY!"), "BOY!")
        XCTAssertEqual(SubtitleSegmenter.normalizeCase("Already fine."), "Already fine.")
    }

    func testNamesAreLearnedFromLabels() {
        let names = SpeakerNames()
        names.learn(from: SubtitleSegmenter.split("OLD MAN: Hello.\nFreya: Hi."))
        XCTAssertEqual(names.all, ["OLD", "MAN", "Freya"])
    }
}
