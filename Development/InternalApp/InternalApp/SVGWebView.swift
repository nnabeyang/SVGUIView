import SwiftUI
import WebKit

/// Shows an SVG file with WebKit, fitted into the view as SVGView does with `.fit`, with its CSS and SMIL animations
/// paused at a time, or playing from the start.
struct SVGWebView: UIViewRepresentable {
  let url: URL
  /// The time of the animations, in seconds, where they're paused while they don't play.
  let time: Double
  /// Whether the animations play from the start instead.
  var isPlaying = false

  final class Coordinator: NSObject, WKNavigationDelegate {
    var url: URL?
    var time = 0.0
    var isPlaying = false

    /// Pauses the animations of the file at the time, or plays them from the start, once the file has loaded.
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
      update(webView)
    }

    /// Sends the time to the file, and whether to play from it, as the file is in a frame of another origin that the
    /// page can't reach otherwise.
    func update(_ webView: WKWebView) {
      let time = isPlaying ? 0 : time
      webView.evaluateJavaScript(
        #"document.querySelector("object")?.contentWindow?.postMessage({ time: \#(time * 1000), play: \#(isPlaying) }, "*");"#
      )
    }
  }

  /// Pauses the CSS animations and the SMIL animations of the SVG file at the time that the page sends, and plays
  /// them from there when it says so.
  private static var seekScript: WKUserScript {
    WKUserScript(
      source: """
        if (document.documentElement instanceof SVGElement) {
          // The animations that seeking has paused. An animation that the file pauses stays where it is.
          const seeking = new WeakSet();
          window.addEventListener("message", (event) => {
            for (const animation of document.getAnimations()) {
              if (animation.playState === "paused" && !seeking.has(animation)) continue;
              seeking.add(animation);
              animation.pause();
              animation.currentTime = event.data.time;
            }
            // SMIL animations share the timeline of the document, which takes seconds.
            const root = document.documentElement;
            if (root instanceof SVGSVGElement) {
              root.pauseAnimations();
              root.setCurrentTime(event.data.time / 1000);
            }
            if (event.data.play) {
              for (const animation of document.getAnimations()) {
                if (seeking.has(animation)) animation.play();
              }
              if (root instanceof SVGSVGElement) root.unpauseAnimations();
            }
          });
        }
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(Self.seekScript)
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.panGestureRecognizer.isEnabled = false
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    if context.coordinator.time != time || context.coordinator.isPlaying != isPlaying {
      context.coordinator.time = time
      context.coordinator.isPlaying = isPlaying
      context.coordinator.update(webView)
    }
    guard context.coordinator.url != url else { return }
    context.coordinator.url = url
    // Loading the file through a page in its folder lets it be sized to the view, and lets it refer to
    // other files in the folder, such as images.
    webView.loadHTMLString(Self.page(for: url), baseURL: url.deletingLastPathComponent())
  }

  private static func page(for url: URL) -> String {
    let source = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    return """
      <!DOCTYPE html>
      <html>
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
      <style>
        html, body { margin: 0; width: 100%; height: 100%; background-color: transparent; }
        object { display: block; width: 100%; height: 100%; }
      </style>
      </head>
      <body><object data="\(source)" type="image/svg+xml"></object></body>
      </html>
      """
  }
}
