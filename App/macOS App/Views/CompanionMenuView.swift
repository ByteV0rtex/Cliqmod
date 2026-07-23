//
//  CompanionMenuView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import SwiftUI

struct CompanionMenuView: View {
    var serial: SerialConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(serial.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(serial.isConnected ? "Connected" : "Searching for Cliqmod...")
                    .font(.headline)
            }

            if let heartbeat = serial.lastHeartbeat {
                Divider()
                LabeledContent("Firmware", value: "v\(heartbeat.firmware)")
                LabeledContent("Profile", value: heartbeat.profileName)
                if let path = serial.portPath {
                    LabeledContent("Port", value: (path as NSString).lastPathComponent)
                }
            }

            if let action = serial.lastAction {
                Divider()
                Text("Last action")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(action.subtype): \(action.payload)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }

            Divider()

            Button("Quit Cliqmod Companion") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 260)
        .task {
            serial.start()
        }
    }
}