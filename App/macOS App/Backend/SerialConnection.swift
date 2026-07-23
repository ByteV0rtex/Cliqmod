//
//  SerialConnection.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import Foundation
import Observation

@MainActor
@Observable
final class SerialConnection {
    private(set) var isConnected = false
    private(set) var lastHeartbeat: HeartbeatMessage?
    private(set) var lastAction: CompanionActionMessage?
    private(set) var portPath: String?

    private var port: RawSerialPort?
    private var monitorTask: Task<Void, Never>?
    private var lastHeartbeatAt: Date?

    /// A brain that stops heartbeating (unplugged, sketch crashed/restarted) needs to
    /// be noticed even if the underlying file descriptor still looks open.
    private static let heartbeatTimeout: TimeInterval = 6

    private let onCompanionAction: (CompanionActionMessage) -> Void

    init(onCompanionAction: @escaping (CompanionActionMessage) -> Void) {
        self.onCompanionAction = onCompanionAction
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        port?.close()
        port = nil
        isConnected = false
    }

    private func tick() async {
        if port == nil {
            openFirstAvailablePort()
        }
        if let last = lastHeartbeatAt, Date().timeIntervalSince(last) > Self.heartbeatTimeout {
            isConnected = false
        }
    }

    private func openFirstAvailablePort() {
        guard let path = RawSerialPort.findCandidatePorts().first else { return }
        let newPort = RawSerialPort()

        newPort.onLine = { [weak self] line in
            Task { @MainActor in self?.handleLine(line) }
        }
        newPort.onClosed = { [weak self] in
            Task { @MainActor in self?.handlePortClosed() }
        }

        if newPort.open(path: path) {
            port = newPort
            portPath = path
        }
    }

    private func handleLine(_ line: String) {
        // Plain debug logs ([WIFI], [MACRO], etc.) share this stream and don't match
        // this prefix — see SERIAL_PROTOCOL.md.
        guard line.hasPrefix("CLIQ1|") else { return }
        let jsonPart = String(line.dropFirst("CLIQ1|".count))
        guard let data = jsonPart.data(using: .utf8),
              let generic = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = generic["type"] as? String else { return }

        switch type {
        case "heartbeat":
            guard let msg = try? JSONDecoder().decode(HeartbeatMessage.self, from: data) else { return }
            lastHeartbeat = msg
            lastHeartbeatAt = Date()
            isConnected = true
        case "companion_action":
            guard let msg = try? JSONDecoder().decode(CompanionActionMessage.self, from: data) else { return }
            lastAction = msg
            onCompanionAction(msg)
        default:
            break
        }
    }

    private func handlePortClosed() {
        port = nil
        portPath = nil
        isConnected = false
    }
}