import SwiftUI
import WebKit

/// Owns a single, persistent WKWebView for the app's lifetime. Keeping one
/// instance (rather than letting SwiftUI create a fresh one per container)
/// is what lets the player be shown inline, shrunk to near-nothing, or
/// presented full-screen without ever reloading or losing playback
/// position — `PlayerView` below just reparents this same view into
/// whichever container is currently on screen.
final class PlayerBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var currentTime: Double = 0
    @Published var isPlaying = false

    let webView: WKWebView

    override init() {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        super.init()

        contentController.add(self, name: "bridge")

        // YouTube's IFrame Player API returns error 153 ("video player
        // configuration error") when it detects it's running from a
        // file:// origin, which is what loadFileURL produces. Loading the
        // same HTML as a string with an https:// base URL instead makes
        // the page report that origin, which the player accepts. The base
        // URL must NOT be youtube.com itself — that makes the page's own
        // origin identical to the embedded iframe's, which the player
        // rejects outright (immediate "video unavailable" error) rather
        // than treating as a normal parent page.
        if let url = Bundle.main.url(forResource: "player", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: URL(string: "https://chapterplayer.app"))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "time":
            if let time = body["time"] as? Double {
                currentTime = time
            }
        case "state":
            if let state = body["state"] as? String {
                isPlaying = (state == "playing")
            }
        default:
            break
        }
    }

    func load(videoId: String) {
        webView.evaluateJavaScript("window.loadVideo('\(videoId)')")
    }

    func seek(to seconds: Double) {
        webView.evaluateJavaScript("window.seekTo(\(seconds))")
    }

    func play() {
        webView.evaluateJavaScript("window.playVideo()")
    }

    func pause() {
        webView.evaluateJavaScript("window.pauseVideo()")
    }
}

/// A reusable "slot" for the shared WKWebView. Claims it into its own
/// container view on every layout pass, so whichever PlayerView is
/// currently on screen (inline or full-screen) ends up holding it — the
/// video itself, and its playback position, never resets.
final class PlayerContainerView: UIView {}

struct PlayerView: UIViewRepresentable {
    @ObservedObject var bridge: PlayerBridge

    func makeUIView(context: Context) -> PlayerContainerView {
        let container = PlayerContainerView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        return container
    }

    func updateUIView(_ container: PlayerContainerView, context: Context) {
        let webView = bridge.webView
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        container.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
