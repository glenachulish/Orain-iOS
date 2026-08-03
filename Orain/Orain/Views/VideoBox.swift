//  VideoBox.swift
//  Òrain
//
//  Video that plays on the song page instead of throwing you out to Safari.
//
//  Leaving the app to watch a reference recording is the wrong shape for what
//  you are actually doing — you want the words in front of you while it plays.
//  It also means coming back and finding your place again.
//
//  Embedded players carry noticeably less advertising than the same video
//  opened in a browser, which is a happy side effect rather than the reason.

import SwiftUI
import WebKit

// MARK: - Turning a share link into an embeddable one

enum VideoEmbed {

    /// The embeddable form of a YouTube or Vimeo link, or nil if this is some
    /// other kind of URL that has to be opened normally.
    ///
    /// Handles the forms that actually turn up when someone copies a link:
    ///   youtu.be/ID
    ///   youtube.com/watch?v=ID
    ///   youtube.com/shorts/ID
    ///   m.youtube.com/…
    ///   vimeo.com/ID
    static func embedURL(for urlString: String) -> URL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let host = url.host?.lowercased()
        else { return nil }

        if host.contains("youtu") {
            guard let id = youTubeID(url) else { return nil }
            // playsinline keeps it in the box rather than going full screen
            // the moment it starts; rel=0 limits the pile of suggestions at
            // the end to the same channel.
            return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&rel=0")
        }

        if host.contains("vimeo") {
            let id = url.pathComponents.filter { $0 != "/" }.last ?? ""
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://player.vimeo.com/video/\(id)")
        }

        return nil
    }

    private static func youTubeID(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // youtu.be/ID
        if host.contains("youtu.be") {
            let id = url.pathComponents.filter { $0 != "/" }.first ?? ""
            return id.isEmpty ? nil : id
        }

        // youtube.com/watch?v=ID
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }

        // youtube.com/shorts/ID, /embed/ID, /live/ID
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            return parts[1]
        }

        return nil
    }
}

// MARK: - The player

struct VideoBox: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Without this the video takes over the whole screen on play, which
        // is precisely what this view exists to avoid.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false   // the page scrolls, not this
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - The row it sits in

/// A video in the media panel: a title you tap to open the player beneath it.
///
/// Deliberately not loaded until asked. A song with several links would
/// otherwise spin up a web view for each one the moment the page appeared,
/// which is slow and starts fetching things nobody asked to watch.
struct VideoRow: View {
    let label: String?
    let urlString: String

    @State private var expanded = false

    private var embed: URL? { VideoEmbed.embedURL(for: urlString) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if embed != nil {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } else if let url = URL(string: urlString) {
                    // Not something we can embed — hand it to the system.
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down.circle.fill" : "play.rectangle.fill")
                        .foregroundStyle(Theme.chordColour)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label ?? host)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Text(embed == nil ? "Opens outside the app" : urlString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if embed == nil {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let embed {
                VideoBox(url: embed)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var host: String {
        guard let host = URL(string: urlString)?.host else { return "Video" }
        if host.contains("youtu") { return "YouTube" }
        if host.contains("vimeo") { return "Vimeo" }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
