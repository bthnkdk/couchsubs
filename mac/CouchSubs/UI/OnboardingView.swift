// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private let total = AppModel.Step.allCases.count - 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space("m")) {
                LogoView(size: 32)
                Text(verbatim: "CouchSubs").font(.csHeadline)
                Spacer()
                Text(String(format: String(localized: "Step %lld of %lld"), min(model.step.rawValue + 1, total), total))
                    .font(.csCallout.monospacedDigit())
                    .foregroundStyle(Color.csSecondary)
            }
            .padding(.horizontal, Theme.space("xxl"))
            .padding(.top, Theme.space("xl"))

            ProgressBar(value: Double(model.step.rawValue + 1) / Double(total))
                .padding(.horizontal, Theme.space("xxl"))
                .padding(.top, Theme.space("l"))

            ScrollView {
                Group {
                    switch model.step {
                    case .welcome: WelcomeStep()
                    case .secondAccount: SecondAccountStep()
                    case .psnLogin: PSNLoginStep()
                    case .console: ConsoleStep()
                    case .tv: TVStep()
                    case .test: TestStep()
                    case .betterTranslation, .done: BetterTranslationStep()
                    }
                }
                .padding(Theme.space("xxl"))
            }

            Divider().overlay(Color.csBorder)
            HStack(spacing: Theme.space("m")) {
                if model.step != .welcome {
                    Button("Back") { model.back() }.buttonStyle(.secondary)
                }
                Spacer()
                if model.step == .betterTranslation && !model.usesFreeGemini {
                    // İsteğe bağlı adım: anahtar yoksa geçilir (birincil düğme adımdaki "Ücretsiz anahtar al").
                    Button("Skip for now") { model.advance() }
                        .buttonStyle(.secondary)
                } else if model.step != .test {
                    Button("Continue") { model.advance() }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canAdvance)
                }
            }
            .padding(.horizontal, Theme.space("xxl"))
            .padding(.vertical, Theme.space("l"))
            .background(Color.csSurface)
        }
    }
}

/// İnce, yuvarlak uçlu ilerleme çubuğu.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.csBorder)
                Capsule().fill(Color.csAccent)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(value * 100))%"))
    }
}
