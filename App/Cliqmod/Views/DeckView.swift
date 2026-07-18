//
//  DeckView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI
import UIKit

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

/// A single Deck button, sized to whatever cellSize the grid computed for the current
/// layout — icon/label scale down together as the grid gets denser (3x5, 4x6) rather
/// than the grid scrolling or clipping.
struct DeckButtonView: View {
    let slot: DeckSlot
    let cellSize: CGFloat
    let isEditing: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    private var iconSize: CGFloat { min(max(cellSize * 0.32, 14), 34) }
    private var labelSize: CGFloat { min(max(cellSize * 0.11, 9), 13) }
    private var showsLabel: Bool { cellSize > 55 && !slot.label.isEmpty }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: slot.action == .none ? "plus" : slot.symbol)
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolEffect(.bounce, value: isPressed)
                if showsLabel {
                    Text(slot.label)
                        .font(.system(size: labelSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(slot.action == .none ? Color.secondary : Color.primary)
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .modifier(GlassButtonBackground(tint: slot.action == .none ? .gray : slot.tint.asTintColor))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 18)
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

struct GlassButtonBackground: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.5)).interactive(),
                                 in: RoundedRectangle(cornerRadius: 18))
        } else {
            content
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        }
    }
}

/// Deck mode: fully chromeless, forced landscape, screen-always-on, everything sized to
/// fit without scrolling. The only UI beyond the grid itself is a tap-to-reveal overlay
/// that auto-hides — normal taps go straight to firing button actions.
struct DeckView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var isEditing = false
    @State private var editingSlot: DeckSlot?
    @State private var showingLayoutPicker = false
    @State private var showOverlay = false
    @State private var hideOverlayTask: Task<Void, Never>?

    private let gridPadding: CGFloat = 20
    private let spacing: CGFloat = 12

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
                .onTapGesture { toggleOverlay() }

            if let state = store.state {
                let layout = store.layout(for: state.activeProfile)
                GeometryReader { geo in
                    let cellSize = computeCellSize(layout: layout, available: geo.size)
                    let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: layout.columns)

                    Group {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer(spacing: spacing) {
                                LazyVGrid(columns: columns, spacing: spacing) {
                                    gridContent(layout: layout, cellSize: cellSize, profileIndex: state.activeProfile)
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                gridContent(layout: layout, cellSize: cellSize, profileIndex: state.activeProfile)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(gridPadding)
            } else {
                ProgressView().tint(Theme.accent)
            }

            overlayBar
        }
        .statusBarHidden(true)
        .onAppear {
            OrientationController.lockLandscape()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(item: $editingSlot) { slot in
            if let state = store.state {
                ActionEditorView(
                    slot: slot,
                    profileIndex: state.activeProfile,
                    onSave: { updated in saveSlot(updated, profileIndex: state.activeProfile) }
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

    // MARK: - Sizing

    private func computeCellSize(layout: DeckLayout, available: CGSize) -> CGFloat {
        let usableWidth = available.width - spacing * CGFloat(layout.columns - 1)
        let usableHeight = available.height - spacing * CGFloat(layout.rows - 1)
        let byWidth = usableWidth / CGFloat(layout.columns)
        let byHeight = usableHeight / CGFloat(layout.rows)
        return max(min(byWidth, byHeight), 32)  // 32pt floor so a dense grid never fully vanishes
    }

    @ViewBuilder
    private func gridContent(layout: DeckLayout, cellSize: CGFloat, profileIndex: Int) -> some View {
        ForEach(layout.slots) { slot in
            DeckButtonView(slot: slot, cellSize: cellSize, isEditing: isEditing) {
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

    // MARK: - Tap-to-reveal overlay

    private func toggleOverlay() {
        withAnimation(.easeOut(duration: 0.2)) { showOverlay.toggle() }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideOverlayTask?.cancel()
        guard showOverlay else { return }
        hideOverlayTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showOverlay = false }
        }
    }

    private var overlayBar: some View {
        VStack {
            if showOverlay {
                HStack(spacing: 16) {
                    Button {
                        store.currentTab = .config
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }

                    Spacer()

                    Text(store.state.map { $0.profiles[$0.activeProfile].name } ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showingLayoutPicker = true
                    } label: {
                        Image(systemName: "square.grid.3x3")
                    }

                    Button {
                        withAnimation(.spring(response: 0.3)) { isEditing.toggle() }
                        scheduleAutoHide()
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeOut(duration: 0.2), value: showOverlay)
    }
}
