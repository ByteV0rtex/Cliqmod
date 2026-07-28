//
//  CliqmodClient.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import Foundation

/// Wraps every call to the brain's REST API. One actor so requests are naturally
/// serialized — matters here because the brain is a single-threaded ESP32 web server,
/// not a beefy backend that shrugs off concurrent requests.
///
/// Point `baseURL` at `http://192.168.4.1` (the brain's own setup-AP address) or
/// `http://cliqmod.local` once it's joined your home WiFi — that's the default now that
/// testing has moved to real hardware. Switch back to `http://localhost:8080` only when
/// running against mock-server.js in the simulator.
actor CliqmodClient {
    private(set) var baseURL: URL

    init(baseURL: URL = URL(string: "http://192.168.4.1")!) {
        self.baseURL = baseURL
    }

    /// Called when the brain's reachable address changes — e.g. after a successful
    /// WiFi join, it restarts and moves from its own fixed AP address to whatever IP
    /// DHCP assigns it on the home network. Needs to be a method rather than a plain
    /// external assignment since baseURL is actor-isolated state.
    func updateBaseURL(_ newURL: URL) {
        baseURL = newURL
    }

    enum ClientError: Error {
        case badStatus(Int)
        case decoding(Error)
    }

    /// Short timeouts, deliberately. URLSession.shared defaults to 60s per request,
    /// which is catastrophic here: the app probes two candidate addresses in sequence,
    /// so one unreachable host could stall a poll cycle for a full minute and two could
    /// stall it for two. That's what made the pairing screen look frozen after the brain
    /// reset back to AP mode while the app still had the old address saved.
    ///
    /// The brain is a device on the same LAN — it either answers in well under a second
    /// or it isn't reachable at all, so waiting longer never produces a better outcome.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 6
        // Don't let a cached response mask a device that's actually gone.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Reads

    func fetchState() async throws -> CliqmodState {
        try await get("/api/state")
    }

    func fetchSources() async throws -> [SourceEntry] {
        let response: SourcesResponse = try await get("/api/sources")
        return response.sources
    }

    // MARK: - Writes

    @discardableResult
    func setProfile(_ index: Int) async throws -> OkResponse {
        try await post("/api/profile", body: SetProfileRequest(index: index))
    }

    @discardableResult
    func saveMappings(profile: Int, mappings: [MappingPayload]) async throws -> OkResponse {
        try await post("/api/mappings", body: SaveMappingsRequest(profile: profile, mappings: mappings))
    }

    @discardableResult
    func rescan() async throws -> OkResponse {
        try await post("/api/rescan")
    }

    /// Fires a single existing mapping by id, or an ad-hoc action never stored anywhere.
    /// A "macro" is just several of these in a row — see `MacroRunner` below.
    @discardableResult
    func trigger(_ request: TriggerRequest) async throws -> OkResponse {
        try await post("/api/trigger", body: request)
    }

    @discardableResult
    func joinWifi(ssid: String, password: String) async throws -> WifiJoinResponse {
        try await post("/api/wifi/join", body: WifiJoinRequest(ssid: ssid, password: password))
    }

    @discardableResult
    func forgetWifi() async throws -> OkResponse {
        try await post("/api/wifi/forget")
    }

    // MARK: - Low-level helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent(path))
        try Self.checkStatus(response)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ClientError.decoding(error) }
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ClientError.decoding(error) }
    }

    /// For endpoints that take no request body at all (rescan, forget).
    private func post<T: Decodable>(_ path: String) async throws -> T {
        try await post(path, body: Optional<Data>.none)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        // /api/wifi/join deliberately returns 200 even on a failed join (the failure is
        // in the JSON body's `ok`/`error` fields, not the HTTP status), so this only
        // guards against transport-level failures, not "the join didn't work".
        guard (200...299).contains(http.statusCode) else {
            throw ClientError.badStatus(http.statusCode)
        }
    }
}

/// Runs a sequence of MacroSteps by calling CliqmodClient.trigger(...) for each key/type
/// step and Task.sleep for each wait step. This is the entire "macro" implementation —
/// deliberately just a client-side loop over ordinary trigger calls, so the firmware
/// never needed a sequence/macro concept of its own.
enum MacroRunner {
    static func run(_ steps: [MacroStep], using client: CliqmodClient) async throws {
        for step in steps {
            switch step {
            case .key(let combo):
                try await client.trigger(.adHoc(keycombo: combo, isString: false))
            case .type(let text):
                try await client.trigger(.adHoc(keycombo: text, isString: true))
            case .wait(let ms):
                try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
        }
    }
}
