// SPDX-License-Identifier: AGPL-3.0-only

import Sparkle
import SwiftUI

@main
struct CouchSubsApp: App {
    @State private var model = Self.makeModel()
    /// Bilgisayar ekranındaki altyazı penceresi.
    @State private var overlay = SubtitleOverlayController()
    /// Sparkle: her açılışta ve uygulama açıkken saatte bir GitHub'daki son sürüme bakar; testlerde başlamaz.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        updaterDelegate: nil, userDriverDelegate: nil)

    /// Testler uygulamanın içinde çalışır. Gerçek Anahtarlığa dokunmazlar: imza farklı olunca macOS parola sorar ve test takılır.
    private static func makeModel() -> AppModel {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? AppModel() : AppModel(store: EphemeralStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // Sparkle kendi takviminde günde bir bakar; yeni sürüm her açılışta fark edilsin diye açılışta da sessizce bakılır.
                .task {
                    overlay.attach(model)
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    updater.updater.checkForUpdatesInBackground()
                }
                .appSurface()
                .frame(minWidth: Theme.size("windowWidth"), idealWidth: Theme.size("windowWidth"), maxWidth: Theme.size("windowWidth") * 1.25,
                       minHeight: Theme.size("windowHeight"), idealHeight: Theme.size("windowHeight"))
                // Başlık çubuğu da pencere zemininin rengini alır.
                .containerBackground(Color.csBackground, for: .window)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About CouchSubs") { model.showAbout = true }
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings") { model.showSettings = true }
                    .keyboardShortcut(",")
                    .disabled(model.step != .done)
            }
        }
        // Altyazı bilgisayar ekranındayken menü çubuğundan pencereye ulaşılır ("Tıklamalar geçsin" açıkken geri dönüş yolu).
        MenuBarExtra("CouchSubs", systemImage: "captions.bubble",
                     isInserted: Binding(get: { model.step == .done && model.settings.output.showsOnComputer }, set: { _ in })) {
            Toggle("Clicks pass through", isOn: Binding(get: { model.settings.overlayClickThrough },
                                                        set: { model.settings.overlayClickThrough = $0 }))
            Button("Adjust the subtitle window") { model.overlayAdjusting = true }
            Divider()
            Button("Open CouchSubs") { NSApp.activate() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.step == .done { MainView() } else { OnboardingView() }
        }
        .sheet(isPresented: $model.showAbout) { AboutView().appSurface() }
    }
}
