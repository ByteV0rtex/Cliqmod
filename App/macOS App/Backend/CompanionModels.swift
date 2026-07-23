//
//  CompanionModels.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 23.07.2026.
//


import Foundation

/// Matches SERIAL_PROTOCOL.md exactly — sent every ~2s, the app's only signal that a
/// brain is actually on the other end of the serial line.
struct HeartbeatMessage: Codable {
    let type: String
    let firmware: String
    let activeProfile: Int
    let profileName: String
}

/// Matches SERIAL_PROTOCOL.md — fired whenever a mapping with an ACTION_COMPANION
/// action executes, from either a physical module event or /api/trigger.
struct CompanionActionMessage: Codable {
    let type: String
    let requestId: Int
    let subtype: String   // "openApp" | "runShortcut" | "runAppleScript"
    let payload: String
}
