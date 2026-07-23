//
//  CliqmodMacApp.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import SwiftUI

@main
struct CliqmodMacApp: App {
    @State private var serial: SerialConnection

    init() {
        _serial = State(initialValue: SerialConnection(onCompanionAction: { message in
            CompanionActionExecutor.execute(message)
        }))
    }

    var body: some Scene {
        MenuBarExtra(serial.isConnected ? "Cliqmod" : "Cliqmod (searching)",
                     systemImage: serial.isConnected ? "keyboard.fill" : "keyboard") {
            CompanionMenuView(serial: serial)
        }
        .menuBarExtraStyle(.window)
    }
}