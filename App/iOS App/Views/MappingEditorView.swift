//
//  MappingEditorView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import SwiftUI

/// What kind of action a stored mapping performs. Mirrors how the firmware branches on
/// isCompanion / isString when writing a Mapping.
private enum MappingActionKind: String, CaseIterable, Identifiable {
    case keyCombo = "Key Combo"
    case typeText = "Type Text"
    case companion = "Mac App Action"
    var id: String { rawValue }
}

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
    @State private var selectedSource: SourceEntry?
    @State private var actionKind: MappingActionKind
    @State private var companionSubtype: CompanionSubtype

    init(profileIndex: Int, existing: Mapping?, onSave: @escaping (MappingPayload) -> Void) {
        self.profileIndex = profileIndex
        self.existing = existing
        self.onSave = onSave
        _label = State(initialValue: existing?.label ?? "")
        _keycombo = State(initialValue: existing?.keycombo ?? "")

        // Companion takes priority over isString, matching the firmware's own branch
        // order when it writes a Mapping.
        let kind: MappingActionKind
        if existing?.isCompanion == true { kind = .companion }
        else if existing?.isString == true { kind = .typeText }
        else { kind = .keyCombo }
        _actionKind = State(initialValue: kind)
        _companionSubtype = State(initialValue:
            CompanionSubtype(rawValue: existing?.companionSubtype ?? "") ?? .openApp)
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

                Section("Action") {
                    Picker("Type", selection: $actionKind) {
                        ForEach(MappingActionKind.allCases) { Text($0.rawValue).tag($0) }
                    }

                    if actionKind == .companion {
                        Picker("Does", selection: $companionSubtype) {
                            ForEach(CompanionSubtype.allCases) { Text($0.displayName).tag($0) }
                        }
                    }

                    TextField(fieldPlaceholder, text: $keycombo, axis: .vertical)
                        .textInputAutocapitalization(actionKind == .keyCombo ? .characters : .sentences)

                    if actionKind == .companion {
                        Text(companionSubtype.helpText)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Needs the Cliqmod companion app running on the connected Mac.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Mapping" : "Edit Mapping")
            .navigationBarTitleDisplayMode(.inline)
            .darkListStyle()
            .listRowBackground(Theme.card)
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

    private var fieldPlaceholder: String {
        switch actionKind {
        case .keyCombo:  return "e.g. CMD+C"
        case .typeText:  return "Text to type"
        case .companion: return companionSubtype.placeholder
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
            isString: actionKind == .typeText,
            isCompanion: actionKind == .companion,
            companionSubtype: actionKind == .companion ? companionSubtype.rawValue : ""
        ))
        dismiss()
    }
}
