//
//  CompanionMenuView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import SwiftUI

struct CompanionMenuView: View {
    var serial: SerialConnection
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(serial.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(serial.isConnected ? "Connected" : "Searching for Cliqmod...")
                    .font(.headline)
            }

            Text(serial.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let heartbeat = serial.lastHeartbeat {
                Divider()
                LabeledContent("Firmware", value: "v\(heartbeat.firmware)")
                LabeledContent("Profile", value: heartbeat.profileName)
            }

            if let action = serial.lastAction {
                Divider()
                Text("Last action").font(.caption).foregroundStyle(.secondary)
                Text("\(action.subtype): \(action.payload)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }

            Divider()

            DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 8) {
                    if serial.discoveredPorts.isEmpty {
                        Text("No USB serial ports found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Serial ports")
                            .font(.caption.weight(.semibold))
                        // Manual override matters because an ESP32-S3 exposes two ports
                        // (native USB and the UART bridge) and only one carries our
                        // protocol output — auto-probing usually finds it, but this is
                        // the escape hatch when it doesn't.
                        Picker("Port", selection: Binding(
                            get: { serial.manualPortOverride ?? "auto" },
                            set: { serial.manualPortOverride = $0 == "auto" ? nil : $0 }
                        )) {
                            Text("Auto").tag("auto")
                            ForEach(serial.discoveredPorts, id: \.self) { path in
                                Text((path as NSString).lastPathComponent).tag(path)
                            }
                        }
                        .labelsHidden()
                    }

                    LabeledContent("Lines seen", value: "\(serial.linesSeenOnCurrentPort)")

                    if let raw = serial.lastRawLine {
                        Text("Last line received")
                            .font(.caption.weight(.semibold))
                        Text(raw)
                            .font(.system(size: 10).monospaced())
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nothing received yet on this port.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)

            Divider()

            Button("Quit Cliqmod Companion") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 300)
        .task {
            // Normally already started from applicationDidFinishLaunching — start() is
            // idempotent, so this is just a harmless backstop.
            serial.start()
        }
    }
}   
