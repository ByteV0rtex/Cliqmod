//
//  ConfigView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

struct ConfigView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var editingMapping: Mapping?
    @State private var isAddingMapping = false
    @State private var isRescanning = false

    var body: some View {
        NavigationStack {
            List {
                if let state = store.state {
                    profilesSection(state: state)
                    mappingsSection(state: state)
                    modulesSection(state: state)

                    Section {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label("Diagnostics", systemImage: "waveform.path.ecg")
                        }
                        NavigationLink {
                            NetworkSettingsView()
                        } label: {
                            Label("Network", systemImage: "wifi")
                        }
                    }
                } else {
                    ProgressView("Connecting...")
                }

                if let error = store.lastError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Config")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isRescanning = true
                            await store.rescanModules()
                            isRescanning = false
                        }
                    } label: {
                        if isRescanning { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .sheet(item: $editingMapping) { mapping in
                if let state = store.state {
                    MappingEditorView(profileIndex: state.activeProfile, existing: mapping) { payload in
                        Task { await replaceMappingAndSave(existingID: mapping.id, with: payload, profileIndex: state.activeProfile) }
                    }
                }
            }
            .sheet(isPresented: $isAddingMapping) {
                if let state = store.state {
                    MappingEditorView(profileIndex: state.activeProfile, existing: nil) { payload in
                        Task { await addMappingAndSave(payload, profileIndex: state.activeProfile) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profilesSection(state: CliqmodState) -> some View {
        Section("Profile") {
            Picker("Active Profile", selection: Binding(
                get: { state.activeProfile },
                set: { newValue in Task { await store.setActiveProfile(newValue) } }
            )) {
                ForEach(Array(state.profiles.enumerated()), id: \.offset) { i, p in
                    Text(p.name).tag(i)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func mappingsSection(state: CliqmodState) -> some View {
        let mappings = state.profiles[state.activeProfile].mappings
        Section("Mappings") {
            if mappings.isEmpty {
                Text("No mappings yet.").foregroundStyle(.secondary)
            } else {
                ForEach(mappings) { m in
                    Button {
                        editingMapping = m
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.label).foregroundStyle(.primary)
                            Text("\(m.source) → \(m.isString ? "\"\(m.keycombo)\"" : m.keycombo)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteMappings(at: offsets, profileIndex: state.activeProfile, current: mappings) }
                }
            }
            Button {
                isAddingMapping = true
            } label: {
                Label("Add Mapping", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private func modulesSection(state: CliqmodState) -> some View {
        Section("Connected Modules") {
            ForEach(state.modules) { m in
                HStack {
                    Circle()
                        .fill(m.present ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text("\(m.side)\(m.pos)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(m.present ? m.label : "Empty")
                    Spacer()
                    if m.present {
                        Text(m.type.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Mapping mutations (the API always replaces a profile's whole mapping list)

    private func currentPayloads(from mappings: [Mapping]) -> [MappingPayload] {
        mappings.map {
            MappingPayload(label: $0.label, keycombo: $0.keycombo, srcCode: $0.srcCode,
                            controlId: $0.controlId, eventType: $0.eventType, isString: $0.isString)
        }
    }

    private func addMappingAndSave(_ payload: MappingPayload, profileIndex: Int) async {
        guard let state = store.state else { return }
        var payloads = currentPayloads(from: state.profiles[profileIndex].mappings)
        payloads.append(payload)
        try? await store.client.saveMappings(profile: profileIndex, mappings: payloads)
        await store.refresh()
    }

    private func replaceMappingAndSave(existingID: Int, with payload: MappingPayload, profileIndex: Int) async {
        guard let state = store.state else { return }
        var payloads = currentPayloads(from: state.profiles[profileIndex].mappings)
        if let idx = state.profiles[profileIndex].mappings.firstIndex(where: { $0.id == existingID }) {
            payloads[idx] = payload
        }
        try? await store.client.saveMappings(profile: profileIndex, mappings: payloads)
        await store.refresh()
    }

    private func deleteMappings(at offsets: IndexSet, profileIndex: Int, current: [Mapping]) async {
        var remaining = current
        remaining.remove(atOffsets: offsets)
        let payloads = currentPayloads(from: remaining)
        try? await store.client.saveMappings(profile: profileIndex, mappings: payloads)
        await store.refresh()
    }
}