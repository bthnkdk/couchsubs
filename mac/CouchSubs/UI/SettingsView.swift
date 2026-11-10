// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var obsCopied = false

    /// OBS'de "Tarayıcı kaynağı" adresi; OBS çoğunlukla CouchSubs ile aynı bilgisayarda çalışır.
    private var obsAddress: String { "http://localhost:\(model.serverPort)/obs" }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.csTitle)
                Spacer()
            }
            .padding(.horizontal, Theme.space("xxl"))
            .padding(.top, Theme.space("xl"))
            .padding(.bottom, Theme.space("m"))

            ScrollView {
                VStack(spacing: Theme.space("l")) {
                    Card(title: "On the TV") {
                        // 1920 piksellik TV ekranında yazı yüksekliği; sürüklerken TV'de örnek altyazı görünür.
                        Slider(value: Binding(get: { Double(model.settings.style.fontSize) },
                                              set: { model.settings.style.fontSize = Int($0.rounded()) }), in: 20...80) {
                            Text("Text size")
                        } minimumValueLabel: {
                            Text("Small").font(.csCallout).foregroundStyle(Color.csSecondary)
                        } maximumValueLabel: {
                            Text("Large").font(.csCallout).foregroundStyle(Color.csSecondary)
                        } onEditingChanged: { editing in
                            if editing { model.sendTestSubtitle() }
                        }
                        Picker("Placement", selection: $model.settings.style.placement) {
                            Text("Over the English subtitle").tag(SubtitlePlacement.cover)
                            Text("Above the English subtitle").tag(SubtitlePlacement.above)
                            Text("Below the English subtitle").tag(SubtitlePlacement.below)
                            Text("Fixed position").tag(SubtitlePlacement.fixed)
                        }
                        if model.settings.style.placement == .fixed {
                            // Sürüklerken TV'de örnek altyazı görünür; böylece yeri doğrudan ekranda ayarlanır.
                            Slider(value: Binding(get: { Double(model.settings.style.bottomPercent) },
                                                  set: { model.settings.style.bottomPercent = Int($0.rounded()) }), in: 0...85) {
                                Text("Position on screen")
                            } minimumValueLabel: {
                                Text("Bottom").font(.csCallout).foregroundStyle(Color.csSecondary)
                            } maximumValueLabel: {
                                Text("Top").font(.csCallout).foregroundStyle(Color.csSecondary)
                            } onEditingChanged: { editing in
                                if editing { model.sendTestSubtitle() }
                            }
                            HintText(text: "In fixed position you can also move subtitles with the ▲ and ▼ buttons on the TV remote.")
                        } else {
                            HintText(text: "The translation follows where the game shows its own subtitle.")
                        }
                        Slider(value: Binding(get: { Double(model.settings.style.background) },
                                              set: { model.settings.style.background = Int($0.rounded()) }), in: 0...100) {
                            Text("Background")
                        } minimumValueLabel: {
                            Text("None").font(.csCallout).foregroundStyle(Color.csSecondary)
                        } maximumValueLabel: {
                            Text("Solid").font(.csCallout).foregroundStyle(Color.csSecondary)
                        } onEditingChanged: { editing in
                            if editing { model.sendTestSubtitle() }
                        }
                        Toggle("Bold text", isOn: $model.settings.style.bold)
                        Picker("Text color", selection: $model.settings.style.textColor) {
                            Text("White").tag(SubtitleTextColor.white)
                            Text("Yellow").tag(SubtitleTextColor.yellow)
                        }
                        Button("Send test subtitle") { model.sendTestSubtitle() }.buttonStyle(.secondary)
                    }
                    DubbingCard()
                    Card(title: "Language") {
                        Picker("Game language", selection: $model.settings.sourceLanguage) {
                            Text("English").tag("en")
                            Text("Japanese").tag("ja")
                            Text("German").tag("de")
                            Text("French").tag("fr")
                            Text("Spanish").tag("es")
                        }
                    }
                    DeepLCard()
                    Card(title: "Subtitle area") {
                        RegionPicker(region: $model.settings.region, frame: model.lastFrame)
                        HintText(text: "Adjust the frame so it covers where the game shows its subtitles.")
                    }
                    Card(title: "Translate the screen (⌥⌘T)") {
                        HintText(text: "Press ⌥⌘T while playing: every text on the screen is translated once and shown on the TV in its own place. Press again to remove the translations.")
                    }
                    Card(title: "OBS overlay") {
                        HintText(text: "Streaming with a capture card? In OBS add a Browser source with this address (width 1920, height 1080). The Turkish subtitles appear over the game on your screen and on the stream.")
                        HStack(spacing: Theme.space("m")) {
                            Text(verbatim: obsAddress)
                                .font(.csBody.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Button(obsCopied ? "Copied" : "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(obsAddress, forType: .string)
                                obsCopied = true
                            }
                            .buttonStyle(.secondary)
                        }
                        HintText(text: "If OBS runs on another computer, use this Mac's network address instead of localhost. The overlay only shows subtitles while the translation is running.")
                    }
                    TVAppCard()
                    Card {
                        HStack(spacing: Theme.space("m")) {
                            Button("About CouchSubs") { model.showAbout = true }.buttonStyle(.secondary)
                            Spacer()
                            Button("Set up again…") { confirmReset = true }.buttonStyle(.secondary).foregroundStyle(Color.csDanger)
                        }
                    }
                }
                .padding(.horizontal, Theme.space("xxl"))
                .padding(.bottom, Theme.space("xl"))
            }

            Divider().overlay(Color.csBorder)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.space("xxl"))
            .padding(.vertical, Theme.space("l"))
            .background(Color.csSurface)
        }
        .frame(width: 600, height: 720)
        .background(Color.csBackground)
        .confirmationDialog("Set up again?", isPresented: $confirmReset) {
            Button("Set up again", role: .destructive) {
                model.resetSetup()
                dismiss()
            }
        } message: {
            Text("The saved PS5, account and TV connection will be removed.")
        }
    }
}

/// İsteğe bağlı çevrimiçi çeviri: kullanıcının kendi DeepL anahtarı.
struct DeepLCard: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var checking = false
    @State private var status: OnlineKeyCheck?

    var body: some View {
        @Bindable var model = model
        Card(title: "Online translation (DeepL)") {
            HintText(text: "Optional. With your own free DeepL key, translations read more naturally. Subtitle text is sent to DeepL; when DeepL cannot be reached, the translation model on this computer takes over.")
            if model.hasDeepLKey {
                Toggle("Translate with DeepL", isOn: $model.settings.onlineTranslation)
                Button("Remove key") {
                    model.removeDeepLKey()
                    status = nil
                }
                .buttonStyle(.secondary)
            } else {
                HStack(spacing: Theme.space("m")) {
                    SecureField("DeepL API key", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save and test") {
                        checking = true
                        Task {
                            status = await model.setDeepLKey(key)
                            if model.hasDeepLKey { key = "" }
                            checking = false
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(checking || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Get a free DeepL API key", destination: URL(string: "https://www.deepl.com/pro-api")!)
                    .font(.csCallout)
            }
            if let status {
                Text(Self.describe(status))
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if model.hasDeepLKey { status = await model.deepLUsage() }
        }
    }

    private static func describe(_ check: OnlineKeyCheck) -> String {
        switch check.state {
        case .valid:
            String(format: String(localized: "This month: %1$@ of %2$@ characters used."),
                   check.used.formatted(), check.limit.formatted())
        case .quotaExceeded:
            String(localized: "This month's DeepL limit is used up. Until it renews, the translation model on this computer translates.")
        case .invalid:
            String(localized: "DeepL did not accept this key. Copy it again from your DeepL account page.")
        case .unreachable:
            String(localized: "DeepL could not be reached. Check your internet connection.")
        }
    }
}

/// Son karenin üstünde altyazı bölgesini gösteren ve kenarlardan ayarlanan çerçeve.
struct RegionPicker: View {
    @Binding var region: CropRegion
    let frame: CGImage?

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    if let frame {
                        Image(decorative: frame, scale: 1).resizable()
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.csBackground)
                        Text("The game picture appears here once translating starts.")
                            .font(.csCaption).foregroundStyle(Color.csSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Rectangle()
                        .strokeBorder(Color.csAccent, lineWidth: 2)
                        .background(Color.csAccent.opacity(0.14))
                        .frame(width: size.width * (region.right - region.left), height: size.height * (region.bottom - region.top))
                        .offset(x: size.width * region.left, y: size.height * region.top)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius("control")))

            Grid(alignment: .leading) {
                GridRow {
                    Text("Top")
                    Slider(value: $region.top, in: 0...max(0, region.bottom - 0.05))
                }
                GridRow {
                    Text("Bottom")
                    Slider(value: $region.bottom, in: min(1, region.top + 0.05)...1)
                }
                GridRow {
                    Text("Left")
                    Slider(value: $region.left, in: 0...max(0, region.right - 0.05))
                }
                GridRow {
                    Text("Right")
                    Slider(value: $region.right, in: min(1, region.left + 0.05)...1)
                }
            }
            Button("Reset area") { region = CropRegion() }.buttonStyle(.secondary)
        }
    }
}
