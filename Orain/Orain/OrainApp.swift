//  OrainApp.swift
//  Òrain
//
//  Entry point. One window, one model container, no login screen — this app
//  holds one person's library on their own phone, so there is nobody to
//  authenticate. That is the single biggest structural difference from the Pi
//  version and the reason it can go to the App Store at all.

import SwiftUI
import SwiftData

@main
struct OrainApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: [Song.self, SongVersion.self, MediaLink.self])
    }
}
