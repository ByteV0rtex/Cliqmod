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

    // Diagnostics — without these, a failed connection is just a silent "searching..."
    // with no way to tell whether the port is wrong, the firmware isn't sending, or the
    // framing doesn't match.
    private(set) var discoveredPorts: [String] = []
    private(set) var lastRawLine: String?
    private(set) var linesSeenOnCurrentPort = 0
    private(set) var statusDetail = "Starting up"

    /// Set to pin a specific port instead of auto-probing (from the menu's port picker).
    var manualPortOverride: String? {
        didSet { closeCurrentPort() }
    }

    private var port: RawSerialPort?
    private var monitorTask: Task<Void, Never>?
    private var lastHeartbeatAt: Date?
    private var currentPortOpenedAt: Date?
    private var portsAlreadyTried: Set<String> = []

    /// A brain that stops heartbeating (unplugged, sketch crashed/restarted) needs to
    /// be noticed even if the underlying file descriptor still looks open.
    private static let heartbeatTimeout: TimeInterval = 6

    /// How long to give a freshly-opened port to produce a recognisable protocol line
    /// before assuming it's the wrong device and moving on. The firmware heartbeats
    /// every 2s, so this is comfortably more than one interval.
    private static let probeTimeout: TimeInterval = 5

    private let onCompanionAction: (CompanionActionMessage) -> Void

    init(onCompanionAction: @escaping (CompanionActionMessage) -> Void) {
        self.onCompanionAction = onCompanionAction
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        closeCurrentPort()
    }

    private func tick() {
        discoveredPorts = RawSerialPort.findCandidatePorts()

        if discoveredPorts.isEmpty {
            statusDetail = "No USB serial devices found — is the brain plugged into the native USB port?"
            isConnected = false
            return
        }

        if port == nil {
            openNextCandidatePort()
            return
        }

        // A port that opened but never produced a protocol line is the wrong device
        // (an ESP32-S3 exposes both a native USB CDC port and a UART bridge port, and
        // only one of them carries our output). Give up on it and try the next.
        if !isConnected,
           let openedAt = currentPortOpenedAt,
           Date().timeIntervalSince(openedAt) > Self.probeTimeout {
            statusDetail = "No Cliqmod data on \(portName(portPath)) — trying another port"
            closeCurrentPort()
            return
        }

        if let last = lastHeartbeatAt, Date().timeIntervalSince(last) > Self.heartbeatTimeout {
            isConnected = false
            statusDetail = "Lost heartbeat — brain may have been unplugged or reset"
        }
    }

    private func openNextCandidatePort() {
        let candidates: [String]
        if let manual = manualPortOverride {
            candidates = [manual]
        } else {
            let untried = discoveredPorts.filter { !portsAlreadyTried.contains($0) }
            // Every port has been tried without success — start the cycle over, since
            // the right one may only have appeared after a replug.
            candidates = untried.isEmpty ? { portsAlreadyTried.removeAll(); return discoveredPorts }() : untried
        }

        guard let path = candidates.first else { return }
        portsAlreadyTried.insert(path)

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
            currentPortOpenedAt = Date()
            linesSeenOnCurrentPort = 0
            statusDetail = "Listening on \(portName(path))..."
        } else {
            statusDetail = "Couldn't open \(portName(path))"
        }
    }

    private func closeCurrentPort() {
        port?.close()
        port = nil
        portPath = nil
        currentPortOpenedAt = nil
        isConnected = false
    }

    private func handleLine(_ line: String) {
        guard !line.isEmpty else { return }
        linesSeenOnCurrentPort += 1
        lastRawLine = line

        // Plain debug logs ([WIFI], [MACRO], etc.) share this stream and don't match
        // this prefix — see SERIAL_PROTOCOL.md.
        guard line.hasPrefix("CLIQ1|") else { return }
        let jsonPart = String(line.dropFirst("CLIQ1|".count))
        guard let data = jsonPart.data(using: .utf8),
              let generic = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = generic["type"] as? String else {
            statusDetail = "Received a malformed protocol line"
            return
        }

        switch type {
        case "heartbeat":
            guard let msg = try? JSONDecoder().decode(HeartbeatMessage.self, from: data) else { return }
            lastHeartbeat = msg
            lastHeartbeatAt = Date()
            isConnected = true
            statusDetail = "Connected on \(portName(portPath))"
            // This port works — make sure a later retry cycle prefers it.
            portsAlreadyTried.removeAll()
        case "companion_action":
            guard let msg = try? JSONDecoder().decode(CompanionActionMessage.self, from: data) else { return }
            lastAction = msg
            onCompanionAction(msg)
        default:
            break
        }
    }

    private func handlePortClosed() {
        closeCurrentPort()
        statusDetail = "Port closed"
    }

    private func portName(_ path: String?) -> String {
        guard let path else { return "unknown port" }
        return (path as NSString).lastPathComponent
    }
}
