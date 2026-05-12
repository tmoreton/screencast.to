import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via Carbon's RegisterEventHotKey.
/// We deliberately avoid SPM (`KeyboardShortcuts`, `MASShortcut`) so the
/// project keeps a flat dependency graph; the API surface we need is tiny.
@MainActor
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?

    // Carbon's event handler is a C function pointer — it can't capture Swift
    // state. Stash the latest handler on the type itself and let the trampoline
    // hop back to the main queue to invoke it.
    nonisolated(unsafe) private static var handler: (() -> Void)?
    nonisolated(unsafe) private static var handlerInstalled = false

    /// `keyCode` is a Carbon virtual keycode (e.g. `kVK_ANSI_R`).
    /// `modifiers` is the Carbon modifier mask (e.g. `cmdKey | shiftKey`).
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.handler = handler
        installHandlerIfNeeded()

        unregister()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x53435354) /* 'SCST' */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("GlobalHotkey: RegisterEventHotKey failed with status \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !Self.handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                GlobalHotkey.handler?()
            }
            return noErr
        }, 1, &spec, nil, nil)
        Self.handlerInstalled = true
    }
}
