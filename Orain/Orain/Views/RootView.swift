//  RootView.swift
//  Òrain
//
//  Three tabs: the whole library, the songbooks, and the ways of narrowing
//  either one down.
//
//  A note on the third tab. "Filters" is unusual as a destination — filtering
//  is normally a mode you put a list into, not a place you go. It earns its
//  place here because with a library of this size the question is usually
//  "show me the Gàidhlig ones" or "show me what's tagged for the wedding",
//  and answering that by *browsing* the available axes is faster than
//  remembering which switch to flip. So the tab lists the dimensions —
//  languages, traditions, tags — and tapping one opens the library already
//  narrowed. It behaves like a table of contents rather than a control panel.

import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Songs", systemImage: "music.note.list")
            }

            NavigationStack {
                CollectionsView()
            }
            .tabItem {
                Label("Collections", systemImage: "books.vertical")
            }

            NavigationStack {
                BrowseView()
            }
            .tabItem {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
