//
//  MappingEditorView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

/// Edits one of the brain's actual stored mappings — these drive physical module
/// behavior too (a Knob+Slider turn, a Button Matrix key), not just Deck mode, so the
/// source picker is the full dynamic list from /api/sources, not just brain-only options.
struct MappingEditorView: View {
    @Environment(CliqmodStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profileIndex: Int
    let existing: Mapping?     // nil when adding a new one
    let onSave: (MappingPayload) -> Void

    @State private var label: String
    @State private var keycombo: String
    @State private var isString: Bool
    @State private var selectedSource: SourceEntry?

    init(profileIndex: Int, existing: Mapping?, onSave: @escaping (MappingPayload) -> Void) {
        self.profileIndex = profileIndex
        self.existing = existing
        self.onSave = onSave
        _label = State(initialValue: existing?.label ?? "")
        _keycombo = State(initialValue: existing?.keycombo ?? "")
        _isString = State(initialValue: existing?.isString ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Undo", text: $label)
                }

                Section("Source") {
                    if store.sources.isEmpty {
                        Text("No sources yet — connect a module or rescan.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Control", selection: $selectedSource) {
                            ForEach(store.sources) { source in
                                Text(source.label).tag(Optional(source))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Type literal text instead of a key combo", isOn: $isString)
                    TextField(isString ? "Text to type" : "e.g. CTRL+Z", text: $keycombo)
                        .textInputAutocapitalization(isString ? .sentences : .characters)
                }
            }
            .navigationTitle(existing == nil ? "New Mapping" : "Edit Mapping")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let existing, selectedSource == nil {
                    selectedSource = store.sources.first {
                        $0.srcCode == existing.srcCode && $0.controlId == existing.controlId && $0.eventType == existing.eventType
                    }
                } else if selectedSource == nil {
                    selectedSource = store.sources.first
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedSource == nil || label.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let source = selectedSource else { return }
        onSave(MappingPayload(
            label: label,
            keycombo: keycombo,
            srcCode: source.srcCode,
            controlId: source.controlId,
            eventType: source.eventType,
            isString: isString
        ))
        dismiss()
    }
}