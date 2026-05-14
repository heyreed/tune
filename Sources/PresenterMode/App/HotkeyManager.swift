import AppKit
import Carbon.HIToolbox

/// Carbon-backed global hotkey registry. Supports multiple hotkeys per instance.
///
/// Carbon's RegisterEventHotKey is the only public API for registering system-wide hotkeys on
/// macOS without Accessibility/Input Monitoring permission. We use it for both the launcher
/// hotkey and the cycle-next hotkey.
final class HotkeyManager {
    static let kVK_ANSI_P: UInt32 = UInt32(Carbon.kVK_ANSI_P)
    static let kVK_Tab: UInt32 = UInt32(Carbon.kVK_Tab)

    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    private struct Binding {
        let hotKeyRef: EventHotKeyRef
        let handler: () -> Void
    }
    private var bindings: [UInt32: Binding] = [:]   // keyed by EventHotKeyID.id
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    func register(keyCode: UInt32, modifiers: Modifiers, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x504D4F44), id: id) // 'PMOD'
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers.rawValue, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            bindings[id] = Binding(hotKeyRef: hotKeyRef, handler: handler)
        } else {
            NSLog("HotkeyManager: RegisterEventHotKey failed (status=\(status)) for keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData, let eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let binding = manager.bindings[hotKeyID.id] {
                DispatchQueue.main.async { binding.handler() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    func unregisterAll() {
        for binding in bindings.values { UnregisterEventHotKey(binding.hotKeyRef) }
        bindings.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit { unregisterAll() }
}
