import Carbon
import Foundation

@MainActor
final class ShortcutManager: NSObject {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var toggleAction: (@MainActor () -> Void)?
    private let identifier = EventHotKeyID(signature: OSType(0x4D4D5554), id: 1)

    func register(toggle: @escaping @MainActor () -> Void) -> Bool {
        toggleAction = toggle
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            macMicMuteHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else { return false }

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        if hotKeyStatus != noErr {
            RemoveEventHandler(eventHandlerReference)
            eventHandlerReference = nil
            return false
        }
        return true
    }

    func invokeToggle() {
        toggleAction?()
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }
}

private let macMicMuteHotKeyHandler: EventHandlerProcPtr = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var pressedHotKey = EventHotKeyID()
    var size = MemoryLayout<EventHotKeyID>.size
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        size,
        &size,
        &pressedHotKey
    )
    guard status == noErr, pressedHotKey.id == 1 else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.invokeToggle()
    }
    return noErr
}
