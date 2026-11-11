// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI

struct ConsoleStep: View {
    @Environment(AppModel.self) private var model
    @State private var consoles: [ConsoleInfo] = []
    @State private var selected: String?
    @State private var manualHost = ""
    @State private var pin = ""
    @State private var searching = false
    @State private var working = false
    @State private var error: String?

    private var host: String { selected ?? manualHost.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        StepLayout(symbol: "gamecontroller.fill", title: "Connect your PS5",
                   message: "Turn on the PS5. As the second user, open Settings › System › Remote Play › Pair Device and enter the 8-digit code shown there.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                if let console = model.console {
                    DoneLabel(text: Self.displayName(of: console))
                }
                Card {
                HStack {
                    Text(verbatim: "PS5").font(.csHeadline)
                    if searching { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Search again") { Task { await search() } }.buttonStyle(.secondary).disabled(searching)
                }
                if consoles.isEmpty && !searching {
                    HintText(text: "No PS5 found. Make sure it is on and on the same network, or enter its IP address. CouchSubs must also be allowed in System Settings › Privacy & Security › Local Network.")
                    TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                        .textFieldStyle(CSTextFieldStyle())
                        .onSubmit { Task { await register() } }
                } else {
                    Picker("PS5", selection: $selected) {
                        ForEach(consoles, id: \.host) { Text(verbatim: "\($0.name) — \($0.host)").tag(Optional($0.host)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .font(.csBody)
                }
                }
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    Text("8-digit code").font(.csCallout).foregroundStyle(Color.csSecondary)
                    // Kod yazılıp Return'e basılınca bağlanılır (eskiden Return, kapalı "Devam"a gidip hiçbir şey yapmıyordu).
                    TextField("", text: $pin)
                        .textFieldStyle(CSTextFieldStyle(font: .csCode, height: 52))
                        .frame(maxWidth: 240)
                        .onSubmit { Task { await register() } }
                }
                HStack(spacing: Theme.space("m")) {
                    // Düğme yalnız çalışırken kapalı; eksik kod ya da adres tıklanınca açıkça söylenir.
                    Button("Connect") { Task { await register() } }
                        .buttonStyle(.primary)
                        .disabled(working)
                    if working {
                        ProgressView().controlSize(.small)
                        HintText(text: "Connecting to the PS5… This can take up to 30 seconds.")
                    }
                }
                ErrorText(error: error).textSelection(.enabled)
                if error != nil {
                    // Eşleştirme olmazsa gönderilecek remoteplay.log Finder'da seçili açılır.
                    Button("Show log file") { showLogFile() }.buttonStyle(.secondary)
                }
            }
        }
        .task { await search() }
    }

    /// PS5 adını göndermezse yine de başarı görünsün.
    private static func displayName(of console: RegisteredConsole) -> String {
        console.name.isEmpty ? "PS5" : console.name
    }

    private func showLogFile() {
        let file = RemotePlayLog.defaultFile
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            let folder = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    private func search() async {
        searching = true
        consoles = await model.discoverConsoles()
        if selected == nil { selected = consoles.first?.host }
        searching = false
    }

    private func register() async {
        guard !working else { return }
        working = true
        error = nil
        do { try await model.register(host: host, pin: pin) } catch { self.error = error.localizedDescription }
        working = false
    }
}
