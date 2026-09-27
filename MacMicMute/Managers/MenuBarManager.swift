import AppKit
import ServiceManagement

@MainActor
final class MenuBarManager: NSObject {
    private let audio: AudioManager
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Microphone: …", action: nil, keyEquivalent: "")
    private let detailMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Mute Microphone", action: #selector(toggleMicrophone), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let shortcutMenuItem = NSMenuItem(title: "Global shortcut: ⌃⌥⌘M", action: nil, keyEquivalent: "")
    private let shortcutErrorMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    var shortcutRegistered = false {
        didSet { refresh() }
    }

    init(audio: AudioManager) {
        self.audio = audio
        super.init()
        buildMenu()
        audio.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    private func buildMenu() {
        statusMenuItem.isEnabled = false
        detailMenuItem.isEnabled = false
        shortcutMenuItem.isEnabled = false
        shortcutErrorMenuItem.isEnabled = false
        toggleMenuItem.target = self
        loginMenuItem.target = self

        menu.addItem(statusMenuItem)
        menu.addItem(detailMenuItem)
        menu.addItem(.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(loginMenuItem)
        menu.addItem(shortcutMenuItem)
        menu.addItem(shortcutErrorMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q").withTarget(self))

        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMicrophone)
        statusItem.button?.toolTip = "Click to mute or unmute microphone"
    }

    func refresh() {
        statusMenuItem.title = audio.state.statusTitle
        detailMenuItem.title = audio.detail
        detailMenuItem.isHidden = audio.state != .unavailable && audio.deviceName.isEmpty
        toggleMenuItem.title = audio.state == .muted ? "Unmute Microphone" : "Mute Microphone"
        toggleMenuItem.isEnabled = audio.state != .unavailable
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        shortcutErrorMenuItem.title = shortcutRegistered ? "" : "Global shortcut could not be registered"
        shortcutErrorMenuItem.isHidden = shortcutRegistered

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: audio.state.symbolName, accessibilityDescription: audio.state.statusTitle)
            image?.isTemplate = true
            button.image = image
            button.toolTip = audio.deviceName.isEmpty ? audio.state.statusTitle : "\(audio.state.statusTitle) — \(audio.deviceName)"
        }
    }

    @objc private func toggleMicrophone() {
        audio.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refresh()
        } catch {
            detailMenuItem.title = "Could not update Launch at Login: \(error.localizedDescription)"
            detailMenuItem.isHidden = false
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
