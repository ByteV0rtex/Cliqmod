//
//  ActionEditorView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

private enum ActionKind: String, CaseIterable, Identifiable {
    case none = "None"
    case fireMapping = "Existing Mapping"
    case keyCombo = "Key Combo"
    case typeText = "Type Text"
    case macro = "Macro"
    case openApp = "Open App"
    case switchProfile = "Switch Profile"
    var id: String { rawValue }
}

struct ActionEditorView: View {
    @Environment(CliqmodStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let slot: DeckSlot
    let profileIndex: Int
    let onSave: (DeckSlot) -> Void

    @State private var label: String
    @State private var symbol: String
    @State private var tint: String
    @State private var kind: ActionKind

    // Per-kind editable state
    @State private var selectedMappingID: Int?
    @State private var keyComboText = ""
    @State private var typeText = ""
    @State private var macroSteps: [MacroStep] = []
    @State private var openAppName = ""
    @State private var openAppTarget: TargetOS = .mac
    @State private var switchProfileIndex = 0

    private static let symbolChoices = [
        "square.dashed", "bolt.fill", "app.badge", "keyboard", "text.cursor",
        "play.fill", "pause.fill", "mic.slash.fill", "speaker.wave.2.fill",
        "arrow.uturn.backward", "arrow.uturn.forward", "square.and.arrow.down",
        "camera.fill", "scissors", "doc.on.doc", "paintbrush.fill"
    ]
    private static let tintChoices = ["blue", "purple", "pink", "orange", "green", "teal", "indigo", "red", "yellow", "gray"]

    init(slot: DeckSlot, profileIndex: Int, onSave: @escaping (DeckSlot) -> Void) {
        self.slot = slot
        self.profileIndex = profileIndex
        self.onSave = onSave
        _label = State(initialValue: slot.label)
        _symbol = State(initialValue: slot.symbol)
        _tint = State(initialValue: slot.tint)

        switch slot.action {
        case .none:
            _kind = State(initialValue: .none)
        case .fireMapping(let id, _):
            _kind = State(initialValue: .fireMapping)
            _selectedMappingID = State(initialValue: id)
        case .keyCombo(let k):
            _kind = State(initialValue: .keyCombo)
            _keyComboText = State(initialValue: k)
        case .typeText(let t):
            _kind = State(initialValue: .typeText)
            _typeText = State(initialValue: t)
        case .macro(let steps):
            _kind = State(initialValue: .macro)
            _macroSteps = State(initialValue: steps)
        case .openApp(let name, let target):
            _kind = State(initialValue: .openApp)
            _openAppName = State(initialValue: name)
            _openAppTarget = State(initialValue: target)
        case .switchProfile(let index):
            _kind = State(initialValue: .switchProfile)
            _switchProfileIndex = State(initialValue: index)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    TextField("Label", text: $label)
                    symbolPicker
                    tintPicker
                }

                Section("Action") {
                    Picker("Type", selection: $kind) {
                        ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                actionDetailSection
            }
            .navigationTitle("Edit Button")
            .navigationBarTitleDisplayMode(.inline)
            .darkListStyle()
            .listRowBackground(Theme.card)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    // MARK: - Appearance pickers

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.symbolChoices, id: \.self) { name in
                    Image(systemName: name)
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .background(symbol == name ? tint.asTintColor.opacity(0.3) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .onTapGesture { symbol = name }
                }
            }
        }
    }

    private var tintPicker: some View {
        HStack(spacing: 10) {
            ForEach(Self.tintChoices, id: \.self) { name in
                Circle()
                    .fill(name.asTintColor)
                    .frame(width: 26, height: 26)
                    .overlay {
                        if tint == name { Circle().strokeBorder(.primary, lineWidth: 2) }
                    }
                    .onTapGesture { tint = name }
            }
        }
    }

    // MARK: - Per-action-type forms

    @ViewBuilder
    private var actionDetailSection: some View {
        switch kind {
        case .none:
            EmptyView()

        case .fireMapping:
            Section("Which Mapping") {
                let mappings = store.state?.profiles[safe: profileIndex]?.mappings ?? []
                if mappings.isEmpty {
                    Text("No mappings on this profile yet — add one in Config first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Mapping", selection: $selectedMappingID) {
                        Text("None").tag(Int?.none)
                        ForEach(mappings) { m in
                            Text("\(m.label) (\(m.source))").tag(Optional(m.id))
                        }
                    }
                }
            }

        case .keyCombo:
            Section("Key Combo") {
                TextField("e.g. CTRL+Z", text: $keyComboText)
                    .textInputAutocapitalization(.characters)
                Text("Sent straight to whatever computer is plugged into the brain's USB port.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .typeText:
            Section("Text to Type") {
                TextField("Text", text: $typeText, axis: .vertical)
            }

        case .macro:
            macroEditor

        case .openApp:
            Section("Open App") {
                TextField("App name (as it appears in search)", text: $openAppName)
                Picker("Target", selection: $openAppTarget) {
                    ForEach(TargetOS.allCases) { Text($0.displayName).tag($0) }
                }
                Text(openAppTarget == .mac
                     ? "Sends Cmd+Space, types the name, then Enter — same as using Spotlight yourself."
                     : "Sends the Windows key, types the name, then Enter — same as using Windows Search yourself.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("This is a blind, timed sequence — there's no confirmation the app actually opened. Works well for apps that show up as the first Spotlight/Search result; less reliable on a slow or busy system.")
                    .font(.caption).foregroundStyle(.orange)
            }

        case .switchProfile:
            Section("Which Profile") {
                let profiles = store.state?.profiles ?? []
                Picker("Profile", selection: $switchProfileIndex) {
                    ForEach(Array(profiles.enumerated()), id: \.offset) { i, p in
                        Text(p.name).tag(i)
                    }
                }
            }
        }
    }

    private var macroEditor: some View {
        Section {
            ForEach(Array(macroSteps.enumerated()), id: \.offset) { i, step in
                macroStepRow(index: i, step: step)
            }
            .onDelete { macroSteps.remove(atOffsets: $0) }

            Menu("Add Step") {
                Button("Key Combo") { macroSteps.append(.key("")) }
                Button("Type Text") { macroSteps.append(.type("")) }
                Button("Wait") { macroSteps.append(.wait(ms: 300)) }
            }
        } header: {
            Text("Macro Steps")
        } footer: {
            Text("Runs top to bottom, in order, with real delays for any Wait steps. This is exactly how Open App works internally — a macro is just a named preset for a step sequence like this.")
        }
    }

    @ViewBuilder
    private func macroStepRow(index: Int, step: MacroStep) -> some View {
        switch step {
        case .key(let combo):
            HStack {
                Image(systemName: "keyboard")
                TextField("Key combo", text: Binding(
                    get: { combo },
                    set: { macroSteps[index] = .key($0) }
                ))
            }
        case .type(let text):
            HStack {
                Image(systemName: "text.cursor")
                TextField("Text", text: Binding(
                    get: { text },
                    set: { macroSteps[index] = .type($0) }
                ))
            }
        case .wait(let ms):
            HStack {
                Image(systemName: "clock")
                Text("Wait")
                Spacer()
                Stepper("\(ms) ms", value: Binding(
                    get: { ms },
                    set: { macroSteps[index] = .wait(ms: $0) }
                ), in: 50...3000, step: 50)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let action: ButtonAction
        switch kind {
        case .none:
            action = .none
        case .fireMapping:
            let label = store.state?.profiles[safe: profileIndex]?.mappings.first(where: { $0.id == selectedMappingID })?.label ?? "Mapping"
            action = selectedMappingID.map { .fireMapping(id: $0, label: label) } ?? .none
        case .keyCombo:
            action = .keyCombo(keyComboText)
        case .typeText:
            action = .typeText(typeText)
        case .macro:
            action = .macro(macroSteps)
        case .openApp:
            action = .openApp(name: openAppName, target: openAppTarget)
        case .switchProfile:
            action = .switchProfile(index: switchProfileIndex)
        }

        var updated = slot
        updated.label = label
        updated.symbol = symbol
        updated.tint = tint
        updated.action = action
        onSave(updated)
        dismiss()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
