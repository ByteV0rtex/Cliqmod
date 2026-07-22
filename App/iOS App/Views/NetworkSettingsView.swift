//
//  NetworkSettingsView.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import SwiftUI

/// Dark-themed text field background — default .roundedBorder renders as a light box,
/// which clashes hard with the black theme everywhere else.
private struct DarkFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}
private extension View {
    func darkField() -> some View { modifier(DarkFieldStyle()) }
}

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
                .darkField()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .darkField()

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
            .tint(Theme.accent)
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

/// Full first-run flow: Welcome -> Connecting -> Credentials. The middle two steps
/// aren't tracked with their own explicit "step" state — whether to show "still
/// searching" vs "found it, get credentials" falls straight out of store.state being
/// nil or not, which the store's own background polling already keeps up to date.
/// One less thing to keep in sync by hand.
struct PairingView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var pastWelcome = false

    var body: some View {
        Group {
            if !pastWelcome {
                WelcomeStepView { withAnimation(.easeInOut(duration: 0.4)) { pastWelcome = true } }
            } else if store.state == nil {
                ConnectingStepView()
            } else {
                CredentialsStepView()
            }
        }
        .onAppear {
            OrientationController.lockPortrait()
        }
    }
}

private struct WelcomeStepView: View {
    let onContinue: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.35))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .opacity(pulse ? 0.9 : 0.5)

                    Image(systemName: "square.grid.3x3.square")
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

                VStack(spacing: 10) {
                    Text("Welcome to Cliqmod")
                        .font(.largeTitle.bold())
                    // Easy to swap — just change this one line.
                    Text("Your desk, reprogrammed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
}

private struct ConnectingStepView: View {
    @Environment(CliqmodStore.self) private var store
    @State private var pulse = false
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 100 + CGFloat(i) * 40, height: 100 + CGFloat(i) * 40)
                            .scaleEffect(pulse ? 1.1 : 0.85)
                            .opacity(pulse ? 0 : 0.6)
                            .animation(
                                .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.4),
                                value: pulse
                            )
                    }
                    Image(systemName: "wifi")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .frame(height: 180)
                .onAppear { pulse = true }

                VStack(spacing: 10) {
                    Text("Connect to Cliqmod WiFi")
                        .font(.title2.bold())
                    Text("Open Settings and join the network below, then come back here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    HStack {
                        Text("Network").foregroundStyle(.secondary)
                        Spacer()
                        Text("Cliqmod").fontWeight(.semibold)
                    }
                    Divider()
                    HStack {
                        Text("Password").foregroundStyle(.secondary)
                        Spacer()
                        Text("cliqmod1").fontWeight(.semibold)
                    }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)

                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Spacer()
                Spacer()

                Button {
                    Task {
                        isRetrying = true
                        await store.refresh()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Try Again Now").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(isRetrying)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
}

private struct CredentialsStepView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                        .padding(.top, 50)

                    VStack(spacing: 8) {
                        Text("Connected!")
                            .font(.title2.bold())
                        Text("Now join your home WiFi so Cliqmod can work without the setup network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    WifiJoinFormView()
                        .padding(20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)
                }
            }
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
