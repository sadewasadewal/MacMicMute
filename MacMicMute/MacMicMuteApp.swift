//
//  MacMicMuteApp.swift
//  MacMicMute
//
//  Created by Sandew on 2026-09-25.
//

import AppKit

@main
enum MacMicMuteApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
