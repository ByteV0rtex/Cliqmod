//
//  CompanionActionExecutor.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import Foundation

/// Executes a companion_action message. Uses /usr/bin/open and /usr/bin/shortcuts via
/// Process rather than NSWorkspace's newer openApplication API — the newer API needs a
/// resolved bundle URL (not just a display name) and has a history of permission
/// quirks for exactly this "helper tool launches another app" use case; the `open`
/// CLI already does name resolution the same way Spotlight does, reliably.
///
/// IMPORTANT: this requires App Sandbox to be OFF for this target. A sandboxed app
/// cannot launch arbitrary executables via Process at all, regardless of entitlements —
/// there's no capability that allows it. Since this is a personal utility talking to
/// your own hardware, not something distributed via the App Store, disable App Sandbox
/// in Signing & Capabilities rather than trying to work around it.
enum CompanionActionExecutor {
    static func execute(_ message: CompanionActionMessage) {
        switch message.subtype {
        case "openApp":
            openApp(named: message.payload)
        case "runShortcut":
            runShortcut(named: message.payload)
        case "runAppleScript":
            runAppleScript(message.payload)
        default:
            print("[Companion] Unknown subtype: \(message.subtype)")
        }
    }

    private static func openApp(named name: String) {
        run("/usr/bin/open", ["-a", name])
    }

    private static func runShortcut(named name: String) {
        run("/usr/bin/shortcuts", ["run", name])
    }

    /// Requires the user to grant Automation permission the first time (standard
    /// macOS prompt) — the app's Info.plist needs NSAppleEventsUsageDescription set,
    /// or the prompt won't have an explanation string and may behave inconsistently.
    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            print("[Companion] Failed to parse AppleScript")
            return
        }
        script.executeAndReturnError(&error)
        if let error {
            print("[Companion] AppleScript error: \(error)")
        }
    }

    private static func run(_ executablePath: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        do {
            try task.run()
        } catch {
            print("[Companion] Failed to run \(executablePath): \(error)")
        }
    }
}