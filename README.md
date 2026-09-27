# MacMicMute

A small native macOS menu-bar utility. It reads and changes mute/volume controls on the **current default input device** with Apple's public Core Audio APIs; it does not record, capture, store, or transmit audio and does not inspect other apps.

## Platform behavior and limitation

macOS does not expose a public, universal software property that silences every microphone input for every app. Core Audio exposes device properties such as `kAudioDevicePropertyMute` and `kAudioDevicePropertyVolumeScalar` in the input scope, but support and writability depend on the selected device and its driver.

MacMicMute first attempts the input device's writable Core Audio mute property. If that is absent, it sets the device's writable input-volume scalar to zero and remembers the prior level by device UID so it can restore it on unmute. These are device-level changes—not an app-local Boolean or a stopped recording session—and should affect clients reading that same device. If the device exposes neither writable control, the app reports it as unavailable rather than claiming it is muted. Some virtual/aggregate devices, drivers, or applications using a different input route can therefore fall outside this guarantee. Test the particular device and conferencing app before relying on it for sensitive calls.

The app polls the default input every second, reflects external changes, and follows a mute request when the default input device changes. The menu icon updates immediately after changes made through MacMicMute.

## Requirements and permissions

- Xcode 15 or later; deployment target macOS 13.0 or later.
- **No microphone capture permission is requested.** The app does not open an input audio stream, so `NSMicrophoneUsageDescription` is intentionally not set.
- No Accessibility or Input Monitoring permission is needed for the global shortcut: it uses Carbon `RegisterEventHotKey` for the specific Control–Option–Command–M chord, not a global keystroke monitor.
- No custom entitlements are required. App Sandbox is disabled because this utility needs direct Core Audio device-property access. Hardened Runtime remains enabled. The app has no network functionality.
- To keep the app running after login, install it in `/Applications`, then add it under **System Settings → General → Login Items → Open at Login**. The status-bar icon is a direct toggle and does not open a menu.

## Open and run in Xcode

1. Open `MacMicMute.xcodeproj`.
2. Select the `MacMicMute` scheme and **My Mac** as the run destination.
3. If signing is required, choose a development team under **Signing & Capabilities**. The project has Hardened Runtime enabled and no special entitlements.
4. Build and run. No main window opens; look for the microphone symbol in the menu bar.
5. Click the menu-bar microphone once to toggle mute/unmute, or use **Control–Option–Command–M** from another app.
6. If unavailable, select an input in **System Settings → Sound → Input**. If its driver does not expose a writable mute or volume control, MacMicMute cannot silence that device using public Core Audio APIs.

## Build a Release app

In Xcode choose **Product → Archive** to archive and export the signed `.app`, or run a local unsigned Release build:

```sh
xcodebuild -project MacMicMute.xcodeproj -scheme MacMicMute -configuration Release -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The local product is at `build/Build/Products/Release/MacMicMute.app`. For distribution outside your machine, sign with your Developer ID, notarize the app, and staple the notarization ticket before sharing it.

## Optional DMG

After producing `build/Build/Products/Release/MacMicMute.app`, create a simple read-only compressed disk image:

```sh
hdiutil create -volname MacMicMute -srcfolder build/Build/Products/Release/MacMicMute.app -ov -format UDZO MacMicMute.dmg
```

For a distributable DMG, sign/notarize the app first and separately sign and notarize the disk image.

## Verification checklist

Test by selecting each available input (built-in microphone, AirPods, and USB microphone if present), toggling in the menu and with the shortcut while another app is frontmost, changing the input while muted, and confirming audio is absent/restored in each target app: Teams, Meet in Chrome, Meet in Safari, Zoom, and Discord. Confirm the menu reports unavailable for any input whose Core Audio controls cannot be written. Those device/application tests require the corresponding hardware and apps and cannot be inferred from a successful Xcode build.
