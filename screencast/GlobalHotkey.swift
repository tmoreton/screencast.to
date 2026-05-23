import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey. Supports
/// multiple hotkeys and both key-down (`onPressed`) and key-up (`onReleased`)
/// so callers can implement hold-to-act gestures. We deliberately avoid SPM
/// (`KeyboardShortcuts`, `MASShortcut`) so the project keeps a flat dependency
/// graph; the API surface we need is tiny.
@MainActor
final class GlobalHotkey {
    private struct Handlers {
        let pressed: () -> Void
        let released: (() -> Void)?
    }

    // Carbon's event handler is a C function pointer — it can't capture Swift
    // state. Keep handlers keyed by hotkey id on the type itself and let the
    // trampoline hop back to the main queue to invoke the right one.
    nonisolated(unsafe) private static var handlers: [UInt32: Handlers] = [:]
    nonisolated(unsafe) private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    private var refs: [UInt32: EventHotKeyRef] = [:]

    /// `keyCode` is a Carbon virtual keycode (e.g. `kVK_ANSI_R`).
    /// `modifiers` is the Carbon modifier mask (e.g. `cmdKey | shiftKey`).
    /// Returns an id used to `unregister` later.
    @discardableResult
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        onPressed: @escaping () -> Void,
        onReleased: (() -> Void)? = nil
    ) -> UInt32 {
        Self.installHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = Handlers(pressed: onPressed, released: onReleased)

        var ref: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: OSType(0x53435354) /* 'SCST' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            NSLog("GlobalHotkey: registered id=\(id) keyCode=\(keyCode) modifiers=\(modifiers)")
        } else {
            Self.handlers[id] = nil
            NSLog("GlobalHotkey: RegisterEventHotKey FAILED status=\(status) keyCode=\(keyCode) modifiers=\(modifiers)")
        }
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        let specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        _ = specs.withUnsafeBufferPointer { buffer in
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                guard let event else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                if err != noErr { return noErr }
                let kind = GetEventKind(event)
                let id = hkID.id
                DispatchQueue.main.async {
                    guard let handlers = GlobalHotkey.handlers[id] else { return }
                    if kind == UInt32(kEventHotKeyPressed) {
                        handlers.pressed()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        handlers.released?()
                    }
                }
                return noErr
            }, buffer.count, buffer.baseAddress, nil, nil)
        }
    }
}
