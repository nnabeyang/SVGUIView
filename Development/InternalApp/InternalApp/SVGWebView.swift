import SwiftUI
import WebKit

/// Shows an SVG file with WebKit, fitted into the view as SVGView does with `.fit`.
struct SVGWebView: UIViewRepresentable {
  let url: URL

  final class Coordinator {
    var url: URL?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context _: Context) -> WKWebView {
    let webView = WKWebView()
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.panGestureRecognizer.isEnabled = false
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
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
