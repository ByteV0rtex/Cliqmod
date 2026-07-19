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
                    switch store.currentTab {
                    case .deck:
                        DeckView()
                    case .config:
                        ConfigView()
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
                .background(Theme.background)
            } else {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView("Connecting to Cliqmod...")
                        .tint(Theme.accent)
                }
            }
        }
        .environment(store)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task {
            store.startPolling()
        }
    }
}

@main
struct CliqmodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
