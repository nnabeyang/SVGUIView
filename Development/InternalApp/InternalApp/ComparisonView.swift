import SVGUIView
import SVGView
import SwiftUI

/// Shows one SVG file with SVGView and with a web view, either in the same place, so that switching between
/// them shows the differences, or one above the other.
///
/// Both views stay in the hierarchy in every mode, so that switching does not load or render the file again.
/// Stepping to the previous or next file keeps the same views and only changes what they load, as an app does.
/// The size of the views and the content mode of SVGView can be changed, to check that SVGView renders again
/// for them. The time sets where the animations of the file are: SVGView shows the start, and a snapshot of
/// SVGUIView shows the other times, while the web view pauses its animations at the time. Playing starts the
/// animations of both from the start.
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
  /// The time of the animations, in seconds.
  @State private var time = 0.0
  /// Whether the snapshot at the time shows the file, so that SVGView, which shows the start, can be hidden.
  @State private var showsSnapshot = false
  /// Whether SVGView and the web view play the animations from the start, instead of showing the time.
  @State private var isPlaying = false
  /// The rendering timeout of SVGView, kept across files and launches.
  @AppStorage("timeoutMilliseconds") private var timeoutMilliseconds = 1000

  private static let timeouts = [10, 100, 1000, 10_000]

  init(comparison: Comparison) {
    self.comparison = comparison
    _index = State(initialValue: comparison.index)
  }

  private var document: SVGFile { comparison.documents[index] }

  private var configuration: SVGUIViewConfiguration {
    // A view that starts playing plays from the start.
    SVGUIViewConfiguration(timeoutDuration: .milliseconds(timeoutMilliseconds), animation: isPlaying ? .play : .none)
  }

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

      HStack {
        Button(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill") {
          isPlaying.toggle()
        }
        .labelStyle(.iconOnly)
        Text("Time")
        // The time doesn't change what's shown while the animations play.
        Slider(value: $time, in: 0...10)
          .disabled(isPlaying)
        TextField("Time", value: $time, format: .number.precision(.fractionLength(0...3)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .monospacedDigit()
          .frame(width: 64)
          .disabled(isPlaying)
        Text("s")
      }
      .padding(.horizontal)

      // Changing the layout keeps the identity of the views, so that they are not created again.
      let layout = mode == .sideBySide ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(ZStackLayout())
      layout {
        ZStack {
          // SVGView stays until the snapshot of the file is rendered, so that the pane isn't empty in between.
          SVGView(contentsOf: document.url, contentMode: contentMode)
            .environment(\.svgViewConfiguration, configuration)
            .opacity(isPlaying || time == 0 || !showsSnapshot ? 1 : 0)
          if time != 0, !isPlaying {
            SnapshotAtTime(
              url: document.url, time: time, contentMode: contentMode, configuration: configuration,
              showsImage: $showsSnapshot)
          }
        }
        .modifier(
          Pane(
            title: contentMode == .fill ? "\(Mode.svgView.rawValue) (Fill)" : Mode.svgView.rawValue,
            size: size, isVisible: mode != .webView))
        // The web view always fits the file in.
        SVGWebView(url: document.url, time: time, isPlaying: isPlaying)
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
    // Another file starts paused at the time.
    .onChange(of: index) { isPlaying = false }
    .navigationTitle(document.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: AnimationControls(file: document)) {
          Label("Animations", systemImage: "slider.horizontal.3")
        }
      }
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
struct Pane: ViewModifier {
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

/// An SVG file rendered by SVGUIView at a time of its animations, as a snapshot, since SVGView shows the start.
private struct SnapshotAtTime: View {
  let url: URL
  /// The time of the animations, in seconds.
  let time: Double
  let contentMode: ContentMode
  let configuration: SVGUIViewConfiguration
  /// Whether the view shows a snapshot of the file at `url`.
  @Binding var showsImage: Bool
  @State private var snapshot: Snapshot?

  /// A snapshot and the file that it shows.
  private struct Snapshot: Equatable {
    let url: URL
    let image: UIImage
  }

  /// What the snapshot depends on, which renders it again when it changes.
  private struct Input: Equatable {
    let url: URL
    let time: Double
    let size: CGSize
    let contentMode: ContentMode
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        if let snapshot, snapshot.url == url {
          Image(uiImage: snapshot.image).resizable()
        }
      }
      .task(id: Input(url: url, time: time, size: proxy.size, contentMode: contentMode)) {
        // A rendering that a newer time cancels keeps the previous image instead of clearing it.
        if let image = await render(size: proxy.size) {
          snapshot = Snapshot(url: url, image: image)
        }
      }
      .onChange(of: snapshot?.url == url, initial: true) { _, shows in
        showsImage = shows
      }
      .onDisappear {
        showsImage = false
      }
    }
  }

  private func render(size: CGSize) async -> UIImage? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let view = SVGUIView(frame: CGRect(origin: .zero, size: size), data: data)
    view.contentMode = contentMode.asUIView()
    view.configuration = configuration
    return try? await view.takeSnapshot(at: .seconds(time))
  }
}
