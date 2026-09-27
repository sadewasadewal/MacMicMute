import Combine
import CoreAudio
import Foundation

@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var state: MicrophoneState = .unavailable
    @Published private(set) var detail = "Looking for the default input device…"
    @Published private(set) var deviceName = ""

    var onChange: (() -> Void)?

    private var currentDeviceID: AudioDeviceID?
    private var followMuteAcrossDeviceChanges = false
    private var pollTimer: Timer?
    private let restoreLevelPrefix = "MacMicMute.originalInputLevel."
    private let zeroThreshold: Float = 0.0001

    func start() {
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func toggle() {
        guard let muted = state.isMuted else {
            detail = "No usable default input device is available. Connect or select a microphone in System Settings → Sound → Input."
            onChange?()
            return
        }
        setMuted(!muted)
    }

    func setMuted(_ shouldMute: Bool) {
        guard let deviceID = defaultInputDevice() else {
            setUnavailable("No default input device is available. Choose an input in System Settings → Sound → Input.")
            return
        }

        followMuteAcrossDeviceChanges = shouldMute
        currentDeviceID = deviceID
        applyMute(shouldMute, to: deviceID)
    }

    func refresh() {
        guard let deviceID = defaultInputDevice() else {
            currentDeviceID = nil
            deviceName = ""
            setUnavailable("No default input device is available. Choose an input in System Settings → Sound → Input.")
            return
        }

        if let previousDeviceID = currentDeviceID, previousDeviceID != deviceID {
            let shouldCarryMute = followMuteAcrossDeviceChanges || state == .muted
            currentDeviceID = deviceID
            if shouldCarryMute {
                followMuteAcrossDeviceChanges = true
                applyMute(true, to: deviceID)
                return
            }
        } else if currentDeviceID == nil, followMuteAcrossDeviceChanges {
            currentDeviceID = deviceID
            applyMute(true, to: deviceID)
            return
        } else {
            currentDeviceID = deviceID
        }

        deviceName = readDeviceName(deviceID) ?? "Default input device"
        guard let observed = readMuteState(deviceID) else {
            setUnavailable("\(deviceName) does not expose a readable input mute or input-volume control. macOS has no universal software microphone mute API.")
            return
        }
        state = observed ? .muted : .unmuted
        if !observed {
            followMuteAcrossDeviceChanges = false
        }
        detail = controlDescription(for: deviceID)
        onChange?()
    }

    private func applyMute(_ shouldMute: Bool, to deviceID: AudioDeviceID) {
        deviceName = readDeviceName(deviceID) ?? "Default input device"
        if hasWritableHardwareMute(on: deviceID) {
            guard writeHardwareMute(shouldMute, to: deviceID) else {
                setUnavailable("Core Audio refused to change the mute control on \(deviceName).")
                return
            }
            refreshStateAfterWrite(deviceID)
            return
        }
        if writeInputLevelMute(shouldMute, to: deviceID) {
            refreshStateAfterWrite(deviceID)
            return
        }
        if hasWritableInputVolume(on: deviceID) {
            setUnavailable("The input-volume control on \(deviceName) could not be changed or restored. If its level was already zero before MacMicMute muted it, set the level manually in System Settings → Sound → Input.")
        } else {
            setUnavailable("\(deviceName) does not provide a writable input mute or input-volume control. This device cannot be muted through Apple's public Core Audio device controls.")
        }
    }

    private func refreshStateAfterWrite(_ deviceID: AudioDeviceID) {
        guard let observed = readMuteState(deviceID) else {
            setUnavailable("The input control changed, but its current state could not be read back.")
            return
        }
        state = observed ? .muted : .unmuted
        detail = controlDescription(for: deviceID)
        onChange?()
    }

    private func writeHardwareMute(_ shouldMute: Bool, to deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(deviceID, &address), isSettable(address, on: deviceID) else { return false }
        var value: UInt32 = shouldMute ? 1 : 0
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }

    private func hasWritableHardwareMute(on deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        return AudioObjectHasProperty(deviceID, &address) && isSettable(address, on: deviceID)
    }

    private func writeInputLevelMute(_ shouldMute: Bool, to deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        guard hasWritableInputVolume(on: deviceID) else { return false }
        guard let deviceUID = readDeviceUID(deviceID) else { return false }
        let key = restoreLevelPrefix + deviceUID

        if shouldMute {
            guard let currentLevel: Float = readProperty(address, on: deviceID) else { return false }
            if currentLevel > zeroThreshold {
                UserDefaults.standard.set(currentLevel, forKey: key)
            } else if UserDefaults.standard.object(forKey: key) == nil {
                return false
            }
            var zero: Float = 0
            return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &zero) == noErr
        }

        guard UserDefaults.standard.object(forKey: key) != nil else { return false }
        let savedLevel = UserDefaults.standard.float(forKey: key)
        guard savedLevel > zeroThreshold else { return false }
        var restoreLevel = savedLevel
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &restoreLevel)
        if status == noErr {
            UserDefaults.standard.removeObject(forKey: key)
            return true
        }
        return false
    }

    private func hasWritableInputVolume(on deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        return AudioObjectHasProperty(deviceID, &address) && isSettable(address, on: deviceID)
    }

    private func readMuteState(_ deviceID: AudioDeviceID) -> Bool? {
        var muteAddress = propertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        var muteIsOn = false
        let hasReadableMute = AudioObjectHasProperty(deviceID, &muteAddress)
        if hasReadableMute, let value: UInt32 = readProperty(muteAddress, on: deviceID) {
            muteIsOn = value != 0
        } else if hasReadableMute {
            return nil
        }

        var levelAddress = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        if AudioObjectHasProperty(deviceID, &levelAddress),
           let level: Float = readProperty(levelAddress, on: deviceID) {
            return muteIsOn || level <= zeroThreshold
        }
        return hasReadableMute ? muteIsOn : nil
    }

    private func controlDescription(for deviceID: AudioDeviceID) -> String {
        var muteAddress = propertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        if AudioObjectHasProperty(deviceID, &muteAddress), isSettable(muteAddress, on: deviceID) {
            return "Using the input device's Core Audio mute control."
        }
        return "Using the input device's Core Audio input-volume control."
    }

    private func defaultInputDevice() -> AudioDeviceID? {
        let address = propertyAddress(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard let deviceID: AudioDeviceID = readProperty(address, on: AudioObjectID(kAudioObjectSystemObject)), deviceID != AudioDeviceID(0) else {
            return nil
        }
        return deviceID
    }

    private func readDeviceName(_ deviceID: AudioDeviceID) -> String? {
        let address = propertyAddress(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        return readStringProperty(address, on: deviceID)
    }

    private func readDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        let address = propertyAddress(kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
        return readStringProperty(address, on: deviceID)
    }

    private func readProperty<T>(_ address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> T? {
        var address = address
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer)
        guard status == noErr else { return nil }
        return buffer.load(as: T.self)
    }

    private func readStringProperty(_ address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> String? {
        var address = address
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Unmanaged<CFString>>.size,
            alignment: MemoryLayout<Unmanaged<CFString>>.alignment
        )
        defer { buffer.deallocate() }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer)
        guard status == noErr else { return nil }
        return buffer.load(as: Unmanaged<CFString>.self).takeRetainedValue() as String
    }

    private func isSettable(_ address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(objectID, &address, &settable) == noErr && settable.boolValue
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func setUnavailable(_ message: String) {
        state = .unavailable
        detail = message
        onChange?()
    }
}
