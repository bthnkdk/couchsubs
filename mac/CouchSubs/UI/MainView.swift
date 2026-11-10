// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    private var sourceName: String { Locale.current.localizedString(forLanguageCode: model.settings.sourceLanguage) ?? model.settings.sourceLanguage }
    private var targetName: String { Locale.current.localizedString(forLanguageCode: model.settings.targetLanguage) ?? model.settings.targetLanguage }

    private var ps5Status: (String, Bool) {
        (AppModel.statusText(model.sessionState, running: model.isRunning), model.sessionState == .streaming)
    }


    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.space("xl")) {
            HStack(spacing: Theme.space("m")) {
                LogoView(size: 44)
                Text(verbatim: "CouchSubs").font(.csTitle)
                Spacer()
                Button { model.showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.csSecondary)
                .help(Text("Settings"))
            }

            Button {
                Task { model.isRunning ? model.stop() : await model.start() }
            } label: {
                Label(model.isRunning ? "Stop translating" : "Start translating",
                      systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    .font(.csHeadline)
            }
            .buttonStyle(CSButtonStyle(kind: model.isRunning ? .danger : .primary, fullWidth: true, height: "primaryActionHeight"))
            .disabled(model.isStarting)

            Card {
                StatusRow(title: "PS5", value: ps5Status.0, tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                Divider().overlay(Color.csBorder)
                StatusRow(title: "TV", value: model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app"),
                          tone: AppModel.tvTone(clients: model.tvClients, running: model.isRunning))
            }

            if model.translatorStatus != .ready {
                Card {
                    if model.translatorStatus == .needsDownload {
                        Label(String(format: String(localized: "The %@–%@ language pack is not downloaded yet."), sourceName, targetName),
                              systemImage: "arrow.down.circle")
                            .font(.csBody.weight(.semibold))
                            .foregroundStyle(Color.csWarning)
                        HintText(text: "Open System Settings › General › Language & Region › Translation Languages and download both languages.")
                        Button("Open Language & Region") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                        }
                        .buttonStyle(.secondary)
                    } else {
                        Label(String(format: String(localized: "Translation from %@ to %@ is not available on this Mac."), sourceName, targetName),
                              systemImage: "exclamationmark.triangle")
                            .font(.csBody.weight(.semibold))
                            .foregroundStyle(Color.csWarning)
                    }
                }
            }

            // Çevrimiçi motor çeviremiyor: satırlar bu arada ücretsiz çeviriyle geliyor.
            if model.isRunning, let issue = model.onlineIssue {
                Card {
                    Label(String(format: String(localized: "%@ is not translating right now"), model.settings.onlineEngine.displayName),
                          systemImage: "exclamationmark.triangle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                    Text(verbatim: TranslationCard.describe(issue, engine: model.settings.onlineEngine) + " "
                         + String(localized: "Meanwhile the free translation is used."))
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let free = model.readingFailedFreeGB {
                Card {
                    Label("macOS can't read the text on the screen.", systemImage: "exclamationmark.triangle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                    if free < 10 {
                        HintText(text: LocalizedStringKey(String(format: String(localized: "The disk is almost full (%.1f GB free). macOS needs free space to read text; free up a few GB and start the translation again."), free)))
                    } else {
                        HintText(text: "Restart the Mac and start the translation again.")
                    }
                }
            }

            Card(title: "Last subtitle") {
                if model.lastTranslation.isEmpty {
                    HintText(text: "Subtitles will appear here while you play.")
                } else {
                    Text(verbatim: model.lastTranslation)
                        .font(.csTitle.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.lastSource)
                        .font(.csCallout)
                        .foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.history.entries.count > 1 {
                Card(title: "Subtitle history") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.space("m")) {
                            ForEach(model.history.entries.dropFirst()) { entry in
                                VStack(alignment: .leading, spacing: Theme.space("xs")) {
                                    Text(verbatim: entry.translation)
                                        .font(.csBody)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(verbatim: entry.source)
                                        .font(.csCallout)
                                        .foregroundStyle(Color.csSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.space("xxl"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $model.showSettings) { SettingsView().appSurface() }
    }
}
