//
//  RootView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

struct RootView: View {
    @State private var store = CliqmodStore()

    var body: some View {
        Group {
            if let state = store.state {
                if state.network.mode == "ap" {
                    PairingView()
                } else {
                    TabView {
                        DeckView()
                            .tabItem { Label("Deck", systemImage: "square.grid.3x2.fill") }
                        ConfigView()
                            .tabItem { Label("Config", systemImage: "slider.horizontal.3") }
                    }
                }
            } else if let error = store.lastError {
                ContentUnavailableView {
                    Label("Can't Reach Cliqmod", systemImage: "wifi.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await store.refresh() } }
                }
            } else {
                ProgressView("Connecting to Cliqmod...")
            }
        }
        .environment(store)
        .task {
            store.startPolling()
        }
    }
}

@main
struct CliqmodApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
