//
//  RawSerialPort.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import Foundation
import Darwin

/// Raw POSIX serial port I/O. Deliberately NOT actor-isolated — it owns a dedicated
/// background GCD queue for all reading/state access, and callbacks fire on that same
/// queue. Callers (see SerialConnection) are responsible for hopping to whatever
/// actor/thread they need when handling those callbacks.
///
/// Kept separate from SerialConnection (the @MainActor @Observable app-facing wrapper)
/// specifically to avoid mixing actor-isolated state with a background-queue-driven
/// read loop — that combination is exactly what tends to trip Swift's strict
/// concurrency checking.
final class RawSerialPort {
    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var lineBuffer = Data()
    private let queue = DispatchQueue(label: "cliqmod.serial.port")

    /// Fires on `queue`, not the main thread — hop explicitly if you need MainActor.
    var onLine: ((String) -> Void)?
    var onClosed: (() -> Void)?

    @discardableResult
    func open(path: String) -> Bool {
        queue.sync {
            let fd = Darwin.open(path, O_RDWR | O_NOCTTY)
            guard fd >= 0 else { return false }

            var options = termios()
            tcgetattr(fd, &options)
            cfmakeraw(&options)
            cfsetspeed(&options, speed_t(B115200))
            options.c_cflag |= tcflag_t(CLOCAL | CREAD)
            tcsetattr(fd, TCSANOW, &options)

            fileDescriptor = fd

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.readAvailable()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            source.resume()
            readSource = source
            return true
        }
    }

    func close() {
        queue.sync {
            readSource?.cancel()
            readSource = nil
            fileDescriptor = -1
            lineBuffer.removeAll()
        }
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)
        guard bytesRead > 0 else {
            if bytesRead == 0 {
                onClosed?()
            }
            return
        }
        lineBuffer.append(Data(buffer[0..<bytesRead]))
        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[..<newlineIndex]
            lineBuffer.removeSubrange(...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine?(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// The brain's native USB CDC port typically shows up as `cu.usbmodemXXXX` on
    /// macOS. `cu.usbserial`/`cu.wchusbserial` are included as a fallback in case a
    /// different USB-serial chip is ever used instead of the S3's native USB.
    static func findCandidatePorts() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return entries
            .filter {
                $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.wchusbserial")
            }
            .sorted()
            .map { "/dev/" + $0 }
    }
}