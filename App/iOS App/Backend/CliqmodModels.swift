//
//  CliqmodState.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//

import Foundation

// ============================================================
//  These mirror the firmware's actual JSON output 1:1 — field names,
//  types, and optionality all match buildStateJson() / buildSourcesJson()
//  in cliqmod_brain_firmware.ino. If the firmware's schema changes,
//  update here first before touching any view code.
// ============================================================

// GET /api/state
struct CliqmodState: Codable {
    let activeProfile: Int
    let firmware: String
    let network: NetworkStatus
    let profiles: [Profile]
    let modules: [ModuleInfo]
    let diagnostics: Diagnostics
}

struct Diagnostics: Codable {
    let uptimeMs: Int
    let left: SideDiagnostics
    let right: SideDiagnostics
}

struct SideDiagnostics: Codable {
    let busRecoveries: Int       // count since boot — nonzero means the bus locked up and self-recovered
    let lastHeartbeatAgoMs: Int  // time since the last fully-clean ping of this side
    let modulesConnected: Int
    let powerBudgetMax: Int      // see README: safe ceiling before pogo-pin voltage drop becomes a factor
}

struct NetworkStatus: Codable {
    let mode: String        // "ap" | "sta"
    let connected: Bool
    let ssid: String
    let ip: String
    let hostname: String    // e.g. "cliqmod.local"
    let lastError: String   // empty string, not null, when there's nothing to report
}

struct Profile: Codable {
    let name: String
    let mappings: [Mapping]
}

// Only ACTIVE mappings are ever present in this array — the firmware skips inactive
// slots entirely rather than sending 48 mostly-empty entries per profile.
struct Mapping: Codable, Identifiable {
    let id: Int
    var label: String
    let source: String        // human-readable ("Brain Enc Click", "Module 0x10") — display only, don't parse
    var srcCode: Int
    var controlId: Int
    var eventType: Int
    let eventTypeLabel: String  // "enc_cw", "enc_ccw", "fader", "button", "none", etc.
    var keycombo: String        // key combo string OR literal text, depending on isString
    var isString: Bool
}

struct ModuleInfo: Codable, Identifiable {
    let present: Bool
    let label: String
    let side: String       // "L" | "R"
    let pos: Int            // 1-3
    let address: Int        // 0 if not present
    let type: String        // "knob_slider" | "buttons" | "unknown"
    let encValues: [Int]?   // only present for knob_slider modules
    let faderValues: [Int]? // only present for knob_slider modules

    var id: String { "\(side)\(pos)" }
}

// GET /api/sources — every mappable (source, control, event) combination available
// right now, given whatever modules are actually connected. Rebuild this list after
// every rescan or module hot-plug; it's not static.
struct SourceEntry: Codable, Identifiable, Hashable {
    let srcCode: Int
    let controlId: Int
    let eventType: Int
    let eventTypeLabel: String
    let label: String

    var id: String { "\(srcCode)-\(controlId)-\(eventType)" }
}

struct SourcesResponse: Codable {
    let sources: [SourceEntry]
}

// ============================================================
//  Request bodies (what the app sends)
// ============================================================

struct SetProfileRequest: Codable {
    let index: Int
}

struct SaveMappingsRequest: Codable {
    let profile: Int
    let mappings: [MappingPayload]
}

// Note: this intentionally does NOT include `id`, `source`, or `eventTypeLabel` —
// those are server-derived/display-only. Sending a full replace of a profile's
// mapping list is how the firmware's POST /api/mappings works; there's no
// incremental "edit one mapping" endpoint.
struct MappingPayload: Codable {
    let label: String
    let keycombo: String
    let srcCode: Int
    let controlId: Int
    let eventType: Int
    let isString: Bool
}

struct WifiJoinRequest: Codable {
    let ssid: String
    let password: String
}

struct WifiJoinResponse: Codable {
    let ok: Bool
    let ip: String?
    let error: String?
}

struct OkResponse: Codable {
    let ok: Bool
}

// POST /api/trigger — fires an action immediately, bypassing the brain's normal
// source-matching (which only responds to physical module interrupts). Exactly one of
// the two shapes is used per call: mappingId re-fires something already stored on the
// brain; keycombo/isString fires a one-off action that was never saved anywhere. A
// "macro" is just several of these calls in a row with delays between them — no
// sequence/macro concept exists on the firmware side at all.
struct TriggerRequest: Codable {
    var mappingId: Int?
    var keycombo: String?
    var isString: Bool?

    static func mapping(_ id: Int) -> TriggerRequest {
        TriggerRequest(mappingId: id, keycombo: nil, isString: nil)
    }
    static func adHoc(keycombo: String, isString: Bool = false) -> TriggerRequest {
        TriggerRequest(mappingId: nil, keycombo: keycombo, isString: isString)
    }
}

// ============================================================
//  Phone-side action & layout model
// ============================================================
//  Deliberately NOT synced to the brain as a blob — the grid shape (2x4, 3x5, custom)
//  and which action lives in which slot are a phone-side rendering/config choice.
//  When an action needs to actually happen on the connected computer, it goes out via
//  CliqmodClient.trigger(...), same as any physical button press would.
// ============================================================

enum TargetOS: String, Codable, CaseIterable, Identifiable {
    case mac, windows
    var id: String { rawValue }
    var displayName: String { self == .mac ? "Mac" : "Windows" }
}

// One atomic step in a macro. `wait` exists because sequences like "Open App" need a
// pause for Spotlight/Windows Search to actually open before typing into it — there's
// no feedback loop confirming it opened, so this is inherently a fixed-delay approach,
// not a guaranteed one. Good enough for Spotlight-style search+launch; a proper
// "launch this exact app" action would need a desktop companion process with real OS
// access, which doesn't exist yet.
enum MacroStep: Identifiable, Equatable {
    case key(String)          // a key combo string, e.g. "CMD+SPACE"
    case type(String)         // literal text to type
    case wait(ms: Int)

    var id: String {
        switch self {
        case .key(let k): return "key-\(k)"
        case .type(let t): return "type-\(t)"
        case .wait(let ms): return "wait-\(ms)"
        }
    }
}

// Manual Codable rather than relying on the compiler's enum-associated-value synthesis
// (SE-0295) — that feature's exact behavior across labeled/unlabeled associated values
// isn't something worth gambling on for a file with no compiler available to check it
// against. This is a private, app-only encoding (never sent to the firmware, never read
// by anything but this same app reading back its own UserDefaults), so all that matters
// is that encode/decode round-trip consistently with each other, which an explicit
// implementation guarantees outright.
extension MacroStep: Codable {
    private enum Kind: String, Codable { case key, type, wait }
    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .key:  self = .key(try container.decode(String.self, forKey: .value))
        case .type: self = .type(try container.decode(String.self, forKey: .value))
        case .wait: self = .wait(ms: try container.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let k):
            try container.encode(Kind.key, forKey: .kind)
            try container.encode(k, forKey: .value)
        case .type(let t):
            try container.encode(Kind.type, forKey: .kind)
            try container.encode(t, forKey: .value)
        case .wait(let ms):
            try container.encode(Kind.wait, forKey: .kind)
            try container.encode(ms, forKey: .value)
        }
    }
}

enum ButtonAction: Equatable {
    case none
    case fireMapping(id: Int, label: String)     // re-fire something already stored on the brain
    case keyCombo(String)                         // ad-hoc, e.g. "CTRL+Z" — not stored on the brain
    case typeText(String)                          // ad-hoc literal text
    case macro([MacroStep])                        // sequence of ad-hoc steps
    case openApp(name: String, target: TargetOS)   // convenience preset — expands to a macro at fire-time
    case switchProfile(index: Int)                  // local: calls setProfile(), no trigger involved

    static func == (lhs: ButtonAction, rhs: ButtonAction) -> Bool {
        // Manual Equatable since MacroStep's associated values make the synthesized
        // version awkward to reason about at a glance — this keeps comparisons explicit.
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.fireMapping(a, _), .fireMapping(b, _)): return a == b
        case let (.keyCombo(a), .keyCombo(b)): return a == b
        case let (.typeText(a), .typeText(b)): return a == b
        case let (.switchProfile(a), .switchProfile(b)): return a == b
        case let (.openApp(n1, t1), .openApp(n2, t2)): return n1 == n2 && t1 == t2
        default: return false
        }
    }

    /// Expands any action into the flat sequence of ad-hoc trigger steps needed to
    /// actually execute it. `.fireMapping` and `.switchProfile` are handled separately
    /// by the caller since they aren't ad-hoc HID sequences.
    func expandedSteps() -> [MacroStep] {
        switch self {
        case .keyCombo(let k): return [.key(k)]
        case .typeText(let t): return [.type(t)]
        case .macro(let steps): return steps
        case .openApp(let name, let target):
            switch target {
            case .mac:
                return [.key("CMD+SPACE"), .wait(ms: 450), .type(name), .wait(ms: 250), .key("ENTER")]
            case .windows:
                return [.key("GUI"), .wait(ms: 450), .type(name), .wait(ms: 250), .key("ENTER")]
            }
        case .none, .fireMapping, .switchProfile:
            return []
        }
    }

    var summary: String {
        switch self {
        case .none: return "Unassigned"
        case .fireMapping(_, let label): return label
        case .keyCombo(let k): return k
        case .typeText(let t): return "Type: \(t)"
        case .macro: return "Macro"
        case .openApp(let name, let target): return "Open \(name) (\(target.displayName))"
        case .switchProfile(let i): return "Profile \(i + 1)"
        }
    }
}

extension ButtonAction: Codable {
    private enum Kind: String, Codable {
        case none, fireMapping, keyCombo, typeText, macro, openApp, switchProfile
    }
    private enum CodingKeys: String, CodingKey {
        case kind, id, label, value, steps, name, target, index
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .none:
            self = .none
        case .fireMapping:
            self = .fireMapping(id: try c.decode(Int.self, forKey: .id),
                                 label: try c.decode(String.self, forKey: .label))
        case .keyCombo:
            self = .keyCombo(try c.decode(String.self, forKey: .value))
        case .typeText:
            self = .typeText(try c.decode(String.self, forKey: .value))
        case .macro:
            self = .macro(try c.decode([MacroStep].self, forKey: .steps))
        case .openApp:
            self = .openApp(name: try c.decode(String.self, forKey: .name),
                             target: try c.decode(TargetOS.self, forKey: .target))
        case .switchProfile:
            self = .switchProfile(index: try c.decode(Int.self, forKey: .index))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Kind.none, forKey: .kind)
        case .fireMapping(let id, let label):
            try c.encode(Kind.fireMapping, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(label, forKey: .label)
        case .keyCombo(let k):
            try c.encode(Kind.keyCombo, forKey: .kind)
            try c.encode(k, forKey: .value)
        case .typeText(let t):
            try c.encode(Kind.typeText, forKey: .kind)
            try c.encode(t, forKey: .value)
        case .macro(let steps):
            try c.encode(Kind.macro, forKey: .kind)
            try c.encode(steps, forKey: .steps)
        case .openApp(let name, let target):
            try c.encode(Kind.openApp, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(target, forKey: .target)
        case .switchProfile(let index):
            try c.encode(Kind.switchProfile, forKey: .kind)
            try c.encode(index, forKey: .index)
        }
    }
}

struct DeckSlot: Codable, Identifiable, Equatable {
    let id: Int          // index within the grid, stable regardless of grid size changes
    var label: String
    var symbol: String   // SF Symbol name
    var tint: String      // named color, mapped to SwiftUI.Color at the view layer
    var action: ButtonAction

    static func empty(id: Int) -> DeckSlot {
        DeckSlot(id: id, label: "", symbol: "square.dashed", tint: "gray", action: .none)
    }
}

struct DeckLayout: Codable {
    var rows: Int
    var columns: Int
    var slots: [DeckSlot]

    static let presets: [(name: String, rows: Int, cols: Int)] = [
        ("2x4", 2, 4), ("2x5", 2, 5), ("3x5", 3, 5)
    ]

    static func makeDefault(rows: Int = 2, columns: Int = 4) -> DeckLayout {
        DeckLayout(rows: rows, columns: columns,
                   slots: (0..<(rows * columns)).map { DeckSlot.empty(id: $0) })
    }

    mutating func resize(rows newRows: Int, columns newCols: Int) {
        let newCount = newRows * newCols
        if newCount > slots.count {
            slots.append(contentsOf: (slots.count..<newCount).map { DeckSlot.empty(id: $0) })
        } else if newCount < slots.count {
            slots.removeLast(slots.count - newCount)
        }
        rows = newRows
        columns = newCols
    }
}
