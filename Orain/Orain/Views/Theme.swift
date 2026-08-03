//  Theme.swift
//  Òrain
//
//  The web app's palette, carried over so the two do not feel like different
//  products. Rust for chords and chorus rules; everything else is system
//  colours, which is what makes dark mode and Dynamic Type work for free.

import SwiftUI

enum Theme {
    /// The rust the web app uses for chord names and the chorus rule.
    static let chordColour = Color(red: 0.62, green: 0.28, blue: 0.14)
    static let chorusAccent = Color(red: 0.62, green: 0.28, blue: 0.14).opacity(0.7)

    /// Star / favourite / hitlist accents.
    static let mastery = Color.orange
}
