//
//  DeckView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

/// Maps the model's named tint strings to actual colors — kept out of CliqmodModels.swift
/// so that file stays UI-agnostic.
extension String {
    var asTintColor: Color {
        switch self {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

/// A single Deck button. Liquid Glass on iOS 26+, with a plain material fallback for
/// anything older — per Apple's own guidance, glass belongs on controls/navigation
/// elements like this, not on dense content, so a button grid is exactly the right place
/// for it. Each button gets its own glass shape rather than sharing one big surface, per
/// the "never stack glass on glass" guidance — the GlassEffectContainer around the whole
/// grid (in DeckView) is what lets them blend/morph as a coordinated group instead.
struct DeckButtonView: View {
    let slot: DeckSlot
    let isEditing: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: slot.action == .none ? "plus" : slot.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .symbolEffect(.bounce, value: isPressed)
                if !slot.label.isEmpty {
                    Text(slot.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(slot.action == .none ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .modifier(GlassButtonBackground(tint: slot.action == .none ? .gray : slot.tint.asTintColor))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// Isolated so the #available check only has to happen once, not at every call site.
struct GlassButtonBackground: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.5)).interactive(),
                                 in: RoundedRectangle(cornerRadius: 20))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        }
    }
}

struct DeckView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var isEditing = false
    @State private var editingSlot: DeckSlot?
    @State private var showingLayoutPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let state = store.state {
                    let layout = store.layout(for: state.activeProfile)
                    deckGrid(layout: layout, profileIndex: state.activeProfile)
                        .padding()
                } else {
                    ProgressView("Connecting...")
                        .padding(.top, 80)
                }
            }
            .navigationTitle("Deck")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.3)) { isEditing.toggle() }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLayoutPicker = true
                    } label: {
                        Image(systemName: "square.grid.3x3")
                    }
                }
            }
            .sheet(item: $editingSlot) { slot in
                if let state = store.state {
                    ActionEditorView(
                        slot: slot,
                        profileIndex: state.activeProfile,
                        onSave: { updated in
                            saveSlot(updated, profileIndex: state.activeProfile)
                        }
                    )
                }
            }
            .confirmationDialog("Grid Size", isPresented: $showingLayoutPicker, titleVisibility: .visible) {
                ForEach(DeckLayout.presets, id: \.name) { preset in
                    Button(preset.name) {
                        guard let state = store.state else { return }
                        var layout = store.layout(for: state.activeProfile)
                        layout.resize(rows: preset.rows, columns: preset.cols)
                        store.updateLayout(layout, for: state.activeProfile)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deckGrid(layout: DeckLayout, profileIndex: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: layout.columns)

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                LazyVGrid(columns: columns, spacing: 14) {
                    gridContent(layout: layout, profileIndex: profileIndex)
                }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                gridContent(layout: layout, profileIndex: profileIndex)
            }
        }
    }

    @ViewBuilder
    private func gridContent(layout: DeckLayout, profileIndex: Int) -> some View {
        ForEach(layout.slots) { slot in
            DeckButtonView(slot: slot, isEditing: isEditing) {
                if isEditing {
                    editingSlot = slot
                } else {
                    Task { await store.fire(slot.action) }
                }
            }
        }
    }

    private func saveSlot(_ slot: DeckSlot, profileIndex: Int) {
        var layout = store.layout(for: profileIndex)
        if let idx = layout.slots.firstIndex(where: { $0.id == slot.id }) {
            layout.slots[idx] = slot
        }
        store.updateLayout(layout, for: profileIndex)
    }
}
