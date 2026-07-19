//
//  DiagnosticsView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import SwiftUI

struct DiagnosticsView: View {
    @Environment(CliqmodStore.self) private var store

    var body: some View {
        List {
            if let state = store.state {
                systemSection(state: state)
                networkSection(state: state)
                sideSection(title: "Left Chain", diag: state.diagnostics.left,
                            modules: state.modules.filter { $0.side == "L" })
                sideSection(title: "Right Chain", diag: state.diagnostics.right,
                            modules: state.modules.filter { $0.side == "R" })
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Diagnostics")
        .darkListStyle()
        .listRowBackground(Theme.card)
        .refreshable { await store.refresh() }
    }

    private func systemSection(state: CliqmodState) -> some View {
        Section("System") {
            LabeledContent("Firmware", value: "v\(state.firmware)")
            LabeledContent("Uptime", value: formatDuration(ms: state.diagnostics.uptimeMs))
            LabeledContent("Active Profile", value: state.profiles[state.activeProfile].name)
        }
    }

    private func networkSection(state: CliqmodState) -> some View {
        Section("Network") {
            LabeledContent("Mode", value: state.network.mode == "sta" ? "WiFi (STA)" : "Setup AP")
            LabeledContent("Status", value: state.network.connected ? "Connected" : "Not connected")
                .foregroundStyle(state.network.connected ? Color.primary : Color.orange)
            LabeledContent("SSID", value: state.network.ssid)
            LabeledContent("IP", value: state.network.ip)
            LabeledContent("Hostname", value: state.network.hostname)
            if !state.network.lastError.isEmpty {
                LabeledContent("Last Error", value: state.network.lastError)
                    .foregroundStyle(.red)
            }
        }
    }

    private func sideSection(title: String, diag: SideDiagnostics, modules: [ModuleInfo]) -> some View {
        Section(title) {
            LabeledContent("Bus Health") {
                HStack(spacing: 4) {
                    Image(systemName: diag.busRecoveries > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(diag.busRecoveries > 0 ? Color.orange : Color.green)
                    Text(diag.busRecoveries > 0 ? "\(diag.busRecoveries) recoveries" : "Clean")
                }
            }
            LabeledContent("Last Heartbeat", value: formatAgo(ms: diag.lastHeartbeatAgoMs))

            LabeledContent("Power Budget") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(diag.modulesConnected) / \(diag.powerBudgetMax) modules")
                    ProgressView(value: Double(diag.modulesConnected), total: Double(diag.powerBudgetMax))
                        .frame(width: 100)
                        .tint(diag.modulesConnected >= diag.powerBudgetMax ? Color.orange : Color.blue)
                }
            }

            ForEach(modules) { m in
                portRow(m)
            }
        }
    }

    @ViewBuilder
    private func portRow(_ m: ModuleInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Port \(m.side)\(m.pos)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if m.present {
                    Text(String(format: "0x%02X", m.address))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if m.present {
                Text("\(m.label) — \(m.type.replacingOccurrences(of: "_", with: " "))")
                    .font(.caption).foregroundStyle(.secondary)
                if let enc = m.encValues, let fad = m.faderValues {
                    HStack(spacing: 12) {
                        ForEach(Array(enc.prefix(2).enumerated()), id: \.offset) { i, v in
                            Label("Enc\(i+1): \(v)", systemImage: "dial.min")
                                .font(.caption2)
                        }
                        ForEach(Array(fad.prefix(2).enumerated()), id: \.offset) { i, v in
                            Label("Fader\(i+1): \(v)", systemImage: "slider.vertical.3")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Empty").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func formatAgo(ms: Int) -> String {
        if ms < 1500 { return "Just now" }
        return "\(ms / 1000)s ago"
    }
}
