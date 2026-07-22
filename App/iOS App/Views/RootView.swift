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
            if let state = store.state, state.network.mode != "ap" {
                switch store.currentTab {
                case .deck:
                    DeckView()
                case .config:
                    ConfigView()
                }
            } else {
                // Not yet paired: store.state is either nil (haven't reached the brain
                // yet) or present but still in AP/setup mode. PairingView's own steps
                // handle both — the "still searching" UI is just what it shows for the
                // nil case, no separate generic error screen needed.
                PairingView()
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
