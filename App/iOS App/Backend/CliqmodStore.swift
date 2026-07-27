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

@MainActor
@Observable
final class CliqmodStore {
    let client: CliqmodClient

    var currentTab: AppTab = .deck

    private(set) var state: CliqmodState?
    private(set) var sources: [SourceEntry] = []
    private(set) var lastError: String?
    private(set) var isLoading = false

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

    func startPolling(interval: Duration = .seconds(4)) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
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
                return
            }
        }
        // Both candidates failed this cycle — lastError already set by the final
        // tryFetch() attempt. Next poll tick tries again from wherever we ended up.
    }

    /// Single attempt against whatever client.baseURL currently is. Returns whether it
    /// succeeded, so refresh() can decide whether to try the other candidate address.
    private func tryFetch() async -> Bool {
        do {
            async let stateResult = client.fetchState()
            async let sourcesResult = client.fetchSources()
            let (newState, newSources) = try await (stateResult, sourcesResult)
            state = newState
            sources = newSources
            lastError = nil
            ensureLayoutExists(for: newState.activeProfile)
            return true
        } catch {
            lastError = "Can't reach Cliqmod — \(error.localizedDescription)"
            return false
        }
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
    func fire(_ action: ButtonAction) async {
        do {
            switch action {
            case .none:
                return
            case .fireMapping(let id, _):
                try await client.trigger(.mapping(id))
            case .switchProfile(let index):
                await setActiveProfile(index)
            case .keyCombo, .typeText, .macro, .openApp:
                try await MacroRunner.run(action.expandedSteps(), using: client)
            }
        } catch {
            lastError = "Trigger failed: \(error.localizedDescription)"
        }
    }

    func rescanModules() async {
        do {
            try await client.rescan()
            await refresh()
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
