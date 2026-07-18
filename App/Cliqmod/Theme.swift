//
//  Theme.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import SwiftUI

/// System dark mode's default backgrounds (.systemGroupedBackground etc.) are dark
/// gray, not black — this defines true black plus a couple of slightly-lighter shades
/// for the layering/contrast that pure black-on-black would otherwise lose.
enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.09)
    static let cardBorder = Color(white: 0.16)
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.98)  // a cooler cyan-blue than default iOS blue
}

/// Applies the black background to a List/Form — .scrollContentBackground(.hidden)
/// removes the system's own (dark gray, not black) background so ours shows through,
/// and each row gets Theme.card so rows are still readable as distinct from the page.
struct DarkListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

extension View {
    func darkListStyle() -> some View { modifier(DarkListStyle()) }
}