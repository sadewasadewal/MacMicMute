import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audioManager = AudioManager()
    private let shortcutManager = ShortcutManager()
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = MenuBarManager(audio: audioManager)
        menuBarManager = menu
        audioManager.start()

        let registered = shortcutManager.register { [weak audioManager] in
            audioManager?.toggle()
        }
        menu.shortcutRegistered = registered
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager.unregister()
        audioManager.stop()
    }
}
