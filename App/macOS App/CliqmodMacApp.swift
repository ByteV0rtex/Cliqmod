//
//  CliqmodMacApp.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//

import SwiftUI
import AppKit

/// Owns the serial connection and starts it at launch.
///
/// Two things this arrangement deliberately avoids:
///
/// 1. `serial` is created eagerly as a stored property rather than assigned inside
///    applicationDidFinishLaunching. AppDelegate is a plain NSObject, not @Observable,
///    so SwiftUI cannot see a nil -> non-nil transition on it — a view rendered while
///    it was still nil would show its placeholder forever. Non-optional from the start
///    means there's no such state to get stuck in.
///
/// 2. `start()` is called here rather than from the menu's .task, because MenuBarExtra
///    only instantiates its content view when the user first clicks the menu open —
///    listening would otherwise not begin until then.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let serial = SerialConnection(onCompanionAction: { message in
        CompanionActionExecutor.execute(message)
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        serial.start()
    }
}

@main
struct CliqmodMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            CompanionMenuView(serial: appDelegate.serial)
        } label: {
            Image(systemName: appDelegate.serial.isConnected ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
