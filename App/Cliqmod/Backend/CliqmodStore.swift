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

    init(baseURL: URL = URL(string: "http://localhost:8080")!) {
        self.client = CliqmodClient(baseURL: baseURL)
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
        do {
            async let stateResult = client.fetchState()
            async let sourcesResult = client.fetchSources()
            let (newState, newSources) = try await (stateResult, sourcesResult)
            state = newState
            sources = newSources
            lastError = nil
            ensureLayoutExists(for: newState.activeProfile)
        } catch {
            lastError = "Can't reach Cliqmod — \(error.localizedDescription)"
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
