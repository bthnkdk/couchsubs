// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

struct TestStep: View {
    @Environment(AppModel.self) private var model
    @State private var sent = false

    var body: some View {
        StepLayout(symbol: "checkmark.seal.fill", title: "Let's test it",
                   message: "CouchSubs will send a sample subtitle to your TV. It should appear at the bottom of the screen, on top of the game.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                Button("Send test subtitle") {
                    model.sendTestSubtitle()
                    sent = true
                }
                .buttonStyle(CSButtonStyle(kind: sent ? .secondary : .primary))
                if sent {
                    Card(title: "Do you see it on the TV?") {
                        HStack(spacing: Theme.space("m")) {
                            Button("Yes, I see it") { model.advance() }
                                .buttonStyle(.primary)
                                .keyboardShortcut(.defaultAction)
                            Button("No") { model.step = .tv }
                                .buttonStyle(.secondary)
                        }
                        HintText(text: "If you don't see it, make sure the CouchSubs TV app is open and connect the TV again.")
                    }
                }
                HintText(text: "CouchSubs sends the English subtitles it reads to a shared pool, anonymously, to make better Turkish translations for everyone. You can turn this off in Settings.")
            }
        }
    }
}
