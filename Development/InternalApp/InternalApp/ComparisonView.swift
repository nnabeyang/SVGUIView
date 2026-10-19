import SVGUIView
import SVGView
import SwiftUI

/// Shows one SVG file with SVGView and with a web view, either in the same place, so that switching between
/// them shows the differences, or one above the other.
///
/// Both views stay in the hierarchy in every mode, so that switching does not load or render the file again.
/// Stepping to the previous or next file keeps the same views and only changes what they load, as an app does.
/// The size of the views and the content mode of SVGView can be changed, to check that SVGView renders again
/// for them.
struct ComparisonView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case svgView = "SVGView"
    case webView = "WebView"
    case sideBySide = "Side by Side"

    var id: Self { self }
  }

  let comparison: Comparison
  @State private var index: Int
  @State private var mode = Mode.svgView
  /// The size of the views, as a fraction of the space for each.
  @State private var size = 1.0
  @State private var contentMode = ContentMode.fit
  /// The rendering timeout of SVGView, kept across files and launches.
  @AppStorage("timeoutMilliseconds") private var timeoutMilliseconds = 1000

  private static let timeouts = [10, 100, 1000, 10_000]

  init(comparison: Comparison) {
    self.comparison = comparison
    _index = State(initialValue: comparison.index)
  }

  private var document: SVGDocument { comparison.documents[index] }

  var body: some View {
    VStack {
      Picker("Mode", selection: $mode) {
        ForEach(Mode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)

      HStack {
        Text("Size")
        Slider(value: $size, in: 0.2...1)
        Text(size.formatted(.percent.precision(.fractionLength(0))))
          .monospacedDigit()
          .frame(minWidth: 44, alignment: .trailing)
      }
      .padding(.horizontal)

      // Changing the layout keeps the identity of the views, so that they are not created again.
      let layout = mode == .sideBySide ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(ZStackLayout())
      layout {
        SVGView(contentsOf: document.url, contentMode: contentMode)
          .environment(
            \.svgViewConfiguration, SVGUIViewConfiguration(timeoutDuration: .milliseconds(timeoutMilliseconds))
          )
          .modifier(
            Pane(
              title: contentMode == .fill ? "\(Mode.svgView.rawValue) (Fill)" : Mode.svgView.rawValue,
              size: size, isVisible: mode != .webView))
        // The web view always fits the file in.
        SVGWebView(url: document.url)
          .modifier(Pane(title: Mode.webView.rawValue, size: size, isVisible: mode != .svgView))
      }

      HStack {
        Button("Previous", systemImage: "chevron.left") { index -= 1 }
          .disabled(index == 0)
        Spacer()
        Text("\(index + 1) / \(comparison.documents.count)")
          .monospacedDigit()
        Spacer()
        Button("Next", systemImage: "chevron.right") { index += 1 }
          .disabled(index == comparison.documents.count - 1)
      }
      .padding(.horizontal)
    }
    .navigationTitle(document.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Content Mode", selection: $contentMode) {
            Text("Fit").tag(ContentMode.fit)
            Text("Fill").tag(ContentMode.fill)
          }
        } label: {
          Label("Content Mode", systemImage: "aspectratio")
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Timeout", selection: $timeoutMilliseconds) {
            ForEach(Self.timeouts, id: \.self) { milliseconds in
              Text(Duration.milliseconds(milliseconds).formatted(.units(allowed: [.seconds, .milliseconds])))
                .tag(milliseconds)
            }
          }
        } label: {
          Label("Timeout", systemImage: "timer")
        }
      }
    }
  }
}

/// A view in the comparison, framed and labeled with the name of its renderer, so that switching shows which
/// one is visible even when they look the same.
private struct Pane: ViewModifier {
  let title: String
  /// The size of the view, as a fraction of the space for it. The view is centered in the space.
  let size: Double
  let isVisible: Bool

  func body(content: Content) -> some View {
    GeometryReader { proxy in
      content
        .frame(width: proxy.size.width * size, height: proxy.size.height * size)
        .border(Color.black, width: 1)
        .overlay(alignment: .topLeading) {
          Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: .capsule)
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .opacity(isVisible ? 1 : 0)
  }
}
