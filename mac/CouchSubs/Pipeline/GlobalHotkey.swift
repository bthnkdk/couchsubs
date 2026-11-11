// SPDX-License-Identifier: AGPL-3.0-only

import Carbon.HIToolbox
import Foundation

/// Genel kısayol: kullanıcı kumandayla oynarken Mac'teki pencere arka planda olsa da çalışır.
/// Carbon kısayolu erişilebilirlik izni istemez. Kısayol yalnız `enabled` iken tutulur; böylece çeviri kapalıyken
/// tuşlar diğer uygulamalarda olağan işini görür. Başka bir uygulama kısayolu tutuyorsa sessizce atlanır.
@MainActor
final class GlobalHotkey {
    enum Key: UInt32 {
        /// ⌥⌘T: ekranı çevir.
        case translateScreen = 1
        /// ⌥⌘L: altyazı penceresinde "Tıklamalar geçsin"i aç/kapat.
        case clickThrough = 2

        var keyCode: UInt32 {
            switch self {
            case .translateScreen: UInt32(kVK_ANSI_T)
            case .clickThrough: UInt32(kVK_ANSI_L)
            }
        }
    }

    private nonisolated let key: Key
    private let pressed: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(_ key: Key, pressed: @escaping () -> Void) {
        self.key = key
        self.pressed = pressed
    }

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { register() } else { unregister() }
        }
    }

    private nonisolated static let signature = OSType(0x4353_5354) // "CSST"

    private func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        // Her kısayolun kendi işleyicisi vardır; başka kısayolun olayını almaz, sıradakine bırakır.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            guard status == noErr, id.signature == GlobalHotkey.signature, id.id == hotkey.key.rawValue else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkey.pressed() } }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
        RegisterEventHotKey(key.keyCode, UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
