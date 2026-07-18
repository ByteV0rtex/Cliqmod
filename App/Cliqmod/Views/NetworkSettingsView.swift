//
//  NetworkSettingsView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

/// Shared by first-run pairing and later "switch networks" from Config — same form,
/// same underlying /api/wifi/join call either way.
struct WifiJoinFormView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var ssid = ""
    @State private var password = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Network Name", text: $ssid)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await join() }
            } label: {
                if isJoining {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Connect").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(ssid.isEmpty || isJoining)

            Text("Stay on the Cliqmod setup WiFi while it connects — it restarts into the new network once successful, so this app will briefly lose connection too.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func join() async {
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }
        do {
            let result = try await store.client.joinWifi(ssid: ssid, password: password)
            if !result.ok {
                errorMessage = result.error ?? "Could not connect"
            }
            // On success the brain restarts itself; polling will just start succeeding
            // again once it comes back up on the new network — nothing else to do here.
        } catch {
            errorMessage = "Request failed — still on the Cliqmod setup WiFi?"
        }
    }
}

/// Full-screen first-run flow, shown whenever the brain is still in setup-AP mode.
struct PairingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 60)

                VStack(spacing: 8) {
                    Text("Set Up Cliqmod")
                        .font(.title2.bold())
                    Text("First, join the Cliqmod setup WiFi in Settings — network name **Cliqmod**, password **cliqmod1**. Then come back here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                WifiJoinFormView()
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            OrientationController.lockPortrait()
        }
    }
}

struct NetworkSettingsView: View {
    @Environment(CliqmodStore.self) private var store

    var body: some View {
        List {
            if let state = store.state {
                if state.network.mode == "sta" && state.network.connected {
                    Section("Current Network") {
                        LabeledContent("SSID", value: state.network.ssid)
                        LabeledContent("IP", value: state.network.ip)
                        LabeledContent("Hostname", value: state.network.hostname)
                    }
                    Section {
                        Button("Forget This Network", role: .destructive) {
                            Task { try? await store.client.forgetWifi() }
                        }
                    }
                } else {
                    Section("Join a Network") {
                        WifiJoinFormView()
                    }
                }
            }
        }
        .navigationTitle("Network")
        .darkListStyle()
        .listRowBackground(Theme.card)
    }
}
