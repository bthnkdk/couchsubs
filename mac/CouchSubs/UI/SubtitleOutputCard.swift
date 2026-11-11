// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de" ve bilgisayar ekranındaki pencerenin seçenekleri.
/// Ana ekranda ve ayarlarda aynı kart kullanılır (Windows'ta da aynı düzen).
struct SubtitleOutputCard: View {
    @Environment(AppModel.self) private var model
    /// Ayarlarda açıklamalar da gösterilir; ana ekranda kart kısa kalır.
    var detailed = false

    var body: some View {
        @Bindable var model = model
        Card {
            HStack(spacing: Theme.space("m")) {
                Text("Show subtitles on").font(.csBody.weight(.semibold))
                Spacer()
                Picker("Show subtitles on", selection: $model.settings.output) {
                    Text(verbatim: "TV").tag(SubtitleOutput.tv)
                    Text("Computer screen").tag(SubtitleOutput.computer)
                    Text("Both").tag(SubtitleOutput.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if model.settings.output.showsOnComputer {
                if detailed {
                    HintText(text: "Subtitles appear in a window on this computer, over the game or PS Remote Play.")
                }
                HStack(spacing: Theme.space("m")) {
                    Toggle("Clicks pass through", isOn: $model.settings.overlayClickThrough)
                    Spacer()
                    Button("Adjust the subtitle window") { model.overlayAdjusting = true }
                        .buttonStyle(.secondary)
                        .disabled(model.overlayAdjusting)
                }
                if detailed || model.settings.overlayClickThrough {
                    HintText(text: "When on, clicks go through to the window below. Press ⌥⌘L or use the menu bar to turn it off.")
                }
            }
        }
    }
}
