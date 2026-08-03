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

/// The app's name, set to match the icon.
///
/// Drawn as text rather than shipped as an image: it then picks up Dynamic
/// Type, stays crisp at any size, and adapts to dark mode without a second
/// asset — none of which a PNG of the same word would do.
struct Wordmark: View {
    var size: CGFloat = 40

    var body: some View {
        Text("Òrain")
            .font(.system(size: size, weight: .bold, design: .serif))
            .foregroundStyle(Theme.chordColour)
            .accessibilityAddTraits(.isHeader)
    }
}
