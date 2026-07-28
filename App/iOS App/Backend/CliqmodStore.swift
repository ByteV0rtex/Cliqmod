//
//  CliqmodStore.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import Foundation
import Observation

enum AppTab {
    case deck, config
}

/// Derived from consecutive poll failures rather than a single failed request — WiFi
/// blips constantly, and flashing "disconnected" on every dropped packet would be noise.
/// One or two failures means "probably fine, retrying"; sustained failure is real.
enum ConnectionState {
    case connected
    case reconnecting
    case disconnected

    var isHealthy: Bool { self == .connected }

    var label: String {
        switch self {
        case .connected:    return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Cliqmod disconnected"
        }
    }
}

@MainActor
@Observable
final class CliqmodStore {
    let client: CliqmodClient

    var currentTab: AppTab = .deck

    private(set) var state: CliqmodState?
    private(set) var sources: [SourceEntry] = []
    private(set) var lastError: String?
    private(set) var isLoading = false

    /// Consecutive failed refresh cycles. Reset to 0 on any success.
    private(set) var consecutiveFailures = 0
    private(set) var lastContact: Date?

    /// How many failed cycles before we call it genuinely disconnected rather than a
    /// transient blip. At the 4s poll interval that's roughly 12 seconds of silence.
    private static let failuresBeforeDisconnected = 3

    var connectionState: ConnectionState {
        // Never reached the brain yet (fresh launch) counts as searching, not connected.
        // Otherwise the first-ever connection attempt would use the slow steady-state
        // poll interval, which is precisely when the user is waiting on it.
        if lastContact == nil && consecutiveFailures == 0 { return .reconnecting }
        if consecutiveFailures == 0 { return .connected }
        if consecutiveFailures < Self.failuresBeforeDisconnected { return .reconnecting }
        return .disconnected
    }

    /// One grid layout per brain profile index — switching the active profile switches
    /// which virtual grid you see, same as switching profiles changes the physical
    /// modules' mappings.
    private(set) var deckLayouts: [Int: DeckLayout] = [:]

    private var pollTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let layoutsKey = "cliqmod.deckLayouts"
    private static let lastWorkingHostKey = "cliqmod.lastWorkingHost"

    /// The brain is reachable at a different address depending on its mode: its own
    /// fixed IP while broadcasting the setup AP, or cliqmod.local via mDNS once it's
    /// joined a home network. Both are tried on every failed refresh — see refresh().
    private static let candidateHosts = ["http://192.168.4.1", "http://cliqmod.local"]

    init() {
        let savedHost = UserDefaults.standard.string(forKey: Self.lastWorkingHostKey)
        let startingHost = savedHost ?? Self.candidateHosts[0]
        self.client = CliqmodClient(baseURL: URL(string: startingHost)!)
        loadLayoutsFromDisk()
    }

    // MARK: - Polling

    /// Steady-state poll interval. Deliberately unhurried — the brain's web server
    /// handles one connection at a time, so there's no value in hammering it once
    /// everything is working.
    private static let connectedPollInterval: Duration = .seconds(4)

    /// Used while disconnected or pairing. The user is actively waiting for the device
    /// to show up, so responsiveness matters more than politeness here — and if the
    /// brain isn't reachable, these requests fail fast rather than loading it.
    private static let searchingPollInterval: Duration = .seconds(1)

    func startPolling(interval: Duration? = nil) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let next = interval
                    ?? (self.connectionState.isHealthy
                        ? Self.connectedPollInterval
                        : Self.searchingPollInterval)
                try? await Task.sleep(for: next)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        if await tryFetch() {
            defaults.set(await client.baseURL.absoluteString, forKey: Self.lastWorkingHostKey)
            markSuccess()
            return
        }

        // Current address failed — the brain's reachable address changes between AP
        // mode (setup) and STA mode (joined a home network), so a single fixed
        // baseURL can't work forever. Try whichever candidate we're NOT currently
        // using before giving up for this cycle.
        let currentHost = await client.baseURL.absoluteString
        for candidate in Self.candidateHosts where candidate != currentHost {
            guard let url = URL(string: candidate) else { continue }
            await client.updateBaseURL(url)
            if await tryFetch() {
                defaults.set(candidate, forKey: Self.lastWorkingHostKey)
                markSuccess()
                return
            }
        }
        // Every candidate address failed this cycle — that's one strike toward being
        // considered genuinely disconnected. Next tick tries again from wherever we
        // ended up; lastError was already set by the final tryFetch().
        consecutiveFailures += 1
    }

    private func markSuccess() {
        consecutiveFailures = 0
        lastContact = Date()
    }

    /// Single attempt against whatever client.baseURL currently is. Returns whether it
    /// succeeded, so refresh() can decide whether to try the other candidate address.
    private func tryFetch() async -> Bool {
        do {
            // Deliberately sequential, NOT `async let` in parallel. The ESP32's
            // WebServer library services exactly one client per handleClient() call in
            // the firmware's main loop — firing two requests simultaneously means the
            // second one is stalled or dropped depending on timing, which showed up as
            // the connection working intermittently rather than failing outright.
            let newState = try await client.fetchState()
            state = newState
            lastError = nil
            ensureLayoutExists(for: newState.activeProfile)

            // Sources only change when modules are physically connected/disconnected,
            // so there's no reason to re-fetch them every poll cycle — that was
            // doubling the request load on a server that can only handle one at a time.
            // rescanModules() refreshes them explicitly when it actually matters.
            if sources.isEmpty {
                sources = (try? await client.fetchSources()) ?? []
            }
            return true
        } catch {
            lastError = "Can't reach Cliqmod — \(error.localizedDescription)"
            return false
        }
    }

    /// Forces a sources re-fetch — call after anything that changes which modules are
    /// connected, since tryFetch() otherwise leaves an already-populated list alone.
    private func refreshSources() async {
        sources = (try? await client.fetchSources()) ?? sources
    }

    // MARK: - Actions

    func setActiveProfile(_ index: Int) async {
        do {
            try await client.setProfile(index)
            await refresh()
        } catch {
            lastError = "Couldn't switch profile: \(error.localizedDescription)"
        }
    }

    /// Executes whatever's bound to a Deck slot. Mapping/profile actions call the brain
    /// directly; everything else expands to a MacroStep sequence run client-side.
    ///
    /// Returns whether it actually reached the brain, so the UI can give feedback — a
    /// silently-failed button press is indistinguishable from a working one otherwise.
    @discardableResult
    func fire(_ action: ButtonAction) async -> Bool {
        do {
            switch action {
            case .none:
                return true
            case .fireMapping(let id, _):
                try await client.trigger(.mapping(id))
            case .switchProfile(let index):
                await setActiveProfile(index)
            case .companion(let subtype, let payload):
                // Not a HID sequence — the brain relays this to the Mac companion app
                // over serial, which does the actual OS-level work.
                try await client.trigger(.companion(subtype, payload: payload))
            case .keyCombo, .typeText, .macro, .openApp:
                try await MacroRunner.run(action.expandedSteps(), using: client)
            }
            markSuccess()
            return true
        } catch {
            lastError = "Trigger failed: \(error.localizedDescription)"
            // A failed trigger is just as much evidence of a dead connection as a failed
            // poll, and it's more immediate — the user is actively pressing a button.
            consecutiveFailures += 1
            return false
        }
    }

    func rescanModules() async {
        do {
            try await client.rescan()
            await refresh()
            // Module set just changed, so the mappable-source list almost certainly did
            // too — tryFetch() won't re-pull it on its own once it's non-empty.
            await refreshSources()
        } catch {
            lastError = "Rescan failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Deck layout persistence

    func layout(for profileIndex: Int) -> DeckLayout {
        deckLayouts[profileIndex] ?? DeckLayout.makeDefault()
    }

    func updateLayout(_ layout: DeckLayout, for profileIndex: Int) {
        deckLayouts[profileIndex] = layout
        saveLayoutsToDisk()
    }

    private func ensureLayoutExists(for profileIndex: Int) {
        if deckLayouts[profileIndex] == nil {
            deckLayouts[profileIndex] = DeckLayout.makeDefault()
            saveLayoutsToDisk()
        }
    }

    private func loadLayoutsFromDisk() {
        guard let data = defaults.data(forKey: Self.layoutsKey) else { return }
        if let decoded = try? JSONDecoder().decode([Int: DeckLayout].self, from: data) {
            deckLayouts = decoded
        }
    }

    private func saveLayoutsToDisk() {
        if let data = try? JSONEncoder().encode(deckLayouts) {
            defaults.set(data, forKey: Self.layoutsKey)
        }
    }
}
