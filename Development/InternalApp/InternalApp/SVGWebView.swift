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
  /// Sends operations on single animations to the web view, or `nil` for a view that only shows the time.
  var control: WebAnimationControl?

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
            // An operation on a CSS animation of an element, which is found by its position in document order, or
            // on the classes of the element.
            const control = event.data.control;
            if (control) {
              const element = document.getElementsByTagName("*")[control.element];
              if (!element) return;
              if (control.action === "toggleClass") {
                element.classList.toggle(control.value);
                return;
              }
              const animation = element.getAnimations()
                .filter((animation) => animation.animationName === control.name)[control.occurrence];
              if (!animation) return;
              switch (control.action) {
                case "play": animation.play(); break;
                case "pause": animation.pause(); break;
                case "seek": animation.currentTime = control.value; break;
                case "rate": animation.playbackRate = control.value; break;
              }
              return;
            }
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
    control?.webView = webView
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

/// Sends operations on the CSS animations of the file that a web view shows, as SVGUIView's document API makes them.
@MainActor
final class WebAnimationControl {
  /// An operation, whose value is a time in milliseconds for `seek`, a rate for `rate`, and a class for `toggleClass`.
  enum Action: String {
    case play, pause, seek, rate, toggleClass
  }

  fileprivate weak var webView: WKWebView?

  /// Sends an operation on an animation of an element, or on the element.
  ///
  /// - Parameters:
  ///   - element: The position of the element in document order, from the root element.
  ///   - name: The name of the animation in `animation-name`.
  ///   - occurrence: The number of the animations of the element with the same name before it.
  func send(_ action: Action, element: Int, name: String = "", occurrence: Int = 0, value: Double = 0) {
    post(action, element: element, name: name, occurrence: occurrence, value: "\(value)")
  }

  /// Toggles a class of an element.
  func toggleClass(_ name: String, element: Int) {
    post(.toggleClass, element: element, name: "", occurrence: 0, value: Self.literal(name))
  }

  /// Posts an operation to the frame of the file, whose value is JavaScript.
  private func post(_ action: Action, element: Int, name: String, occurrence: Int, value: String) {
    let control =
      "{ action: \(Self.literal(action.rawValue)), element: \(element), name: \(Self.literal(name)), "
      + "occurrence: \(occurrence), value: \(value) }"
    webView?.evaluateJavaScript(
      #"document.querySelector("object")?.contentWindow?.postMessage({ control: \#(control) }, "*");"#)
  }

  /// A string as a JavaScript literal.
  private static func literal(_ string: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [string])) ?? Data("[\"\"]".utf8)
    return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
  }
}
