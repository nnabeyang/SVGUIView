import SVGUIView
import SwiftUI

/// Controls the CSS animations of an SVG file one by one through SVGUIView's document API, and makes the same
/// operations on the animations of a web view, which shows the file below SVGUIView.
///
/// Both views play from when they load the file, so the times of their animations can differ until an animation is
/// moved to a time in both.
struct AnimationControlView: View {
  let file: SVGFile
  @State private var controller = AnimationController()
  /// The selector of the elements whose class the toggle changes.
  @State private var selector = "#box"
  @State private var className = "run"

  var body: some View {
    VStack(spacing: 8) {
      VStack(spacing: 8) {
        ControlledSVGView(url: file.url, controller: controller)
          .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
        SVGWebView(url: file.url, time: 0, isPlaying: true, control: controller.web)
          .modifier(Pane(title: "WebView", size: 1, isVisible: true))
      }
      .frame(maxHeight: 360)
      .padding(.horizontal)

      HStack {
        Button("Pause All") { controller.forEach { controller.pause($0) } }
        Button("Play All") { controller.forEach { controller.play($0) } }
        Button("Start All") { controller.forEach { controller.seek($0, to: 0) } }
      }
      .buttonStyle(.bordered)

      HStack {
        TextField("Selector", text: $selector)
        TextField("Class", text: $className)
        Button("Toggle Class") { controller.toggleClass(className, of: selector) }
          .buttonStyle(.bordered)
      }
      .textFieldStyle(.roundedBorder)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .padding(.horizontal)

      List {
        Section {
          ForEach(controller.animations, id: \.self) { animation in
            AnimationRow(animation: animation, controller: controller)
          }
        } footer: {
          Text(
            "The web view doesn't list the animations that have finished without filling, so the operations on them "
              + "don't reach it.")
        }
      }
    }
    .navigationTitle(file.name)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      // A change of a class adds or removes animations, so the list is read again.
      while !Task.isCancelled {
        controller.reload()
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }
}

/// The view whose document's animations the controller controls, and the web view that gets the same operations.
@MainActor
@Observable
final class AnimationController {
  @ObservationIgnored weak var view: SVGUIView?
  @ObservationIgnored let web = WebAnimationControl()
  /// The CSS animations of the document, as they were when the list was read.
  private(set) var animations: [SVGDocument.Animation] = []

  /// Reads the list of animations again.
  func reload() {
    let animations = view?.document.animations ?? []
    if animations != self.animations {
      self.animations = animations
    }
  }

  func forEach(_ body: (SVGDocument.Animation) -> Void) {
    animations.forEach(body)
  }

  func play(_ animation: SVGDocument.Animation) {
    animation.play()
    send(.play, animation)
  }

  func pause(_ animation: SVGDocument.Animation) {
    animation.pause()
    send(.pause, animation)
  }

  /// Moves an animation to a time in seconds.
  func seek(_ animation: SVGDocument.Animation, to time: Double) {
    animation.currentTime = .seconds(time)
    send(.seek, animation, value: time * 1000)
  }

  func setRate(_ rate: Double, of animation: SVGDocument.Animation) {
    animation.playbackRate = rate
    send(.rate, animation, value: rate)
  }

  /// Toggles a class of the elements that a selector matches.
  func toggleClass(_ name: String, of selector: String) {
    guard !name.isEmpty, let document = view?.document, let elements = try? document.querySelectorAll(selector)
    else { return }
    for element in elements {
      element.classList.toggle(name)
      if let index = position(of: element) {
        web.toggleClass(name, element: index)
      }
    }
    reload()
  }

  private func send(_ action: WebAnimationControl.Action, _ animation: SVGDocument.Animation, value: Double = 0) {
    guard let element = position(of: animation.element) else { return }
    // The animations of the element with the same name before this one, which the web view counts the same way.
    let occurrence = animations.prefix { $0 != animation }.filter {
      $0.element == animation.element && $0.animationName == animation.animationName
    }.count
    web.send(action, element: element, name: animation.animationName, occurrence: occurrence, value: value)
  }

  /// The position of an element in document order from the root element, which finds it in the web view.
  private func position(of element: SVGDocument.Element) -> Int? {
    try? element.document.querySelectorAll("*").firstIndex(of: element)
  }
}

/// An animation with its time, and the buttons that control it.
private struct AnimationRow: View {
  let animation: SVGDocument.Animation
  let controller: AnimationController
  /// The time that the slider moves the animation to, in seconds.
  @State private var time = 0.0
  @State private var rate = 1.0
  @State private var finish = Finish.none

  private enum Finish {
    case none, waiting, finished
  }

  private static let rates = [-1, 0.5, 1, 2]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TimelineView(.periodic(from: .now, by: 0.1)) { _ in
        HStack {
          Text(animation.animationName).bold()
          Text(label(of: animation.element)).foregroundStyle(.secondary)
          Spacer()
          Text(animation.currentTime.map { $0.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 2))) } ?? "–")
            .monospacedDigit()
          Button(animation.isPaused ? "Play" : "Pause", systemImage: animation.isPaused ? "play.fill" : "pause.fill") {
            animation.isPaused ? controller.play(animation) : controller.pause(animation)
          }
          .labelStyle(.iconOnly)
        }
      }
      Slider(value: $time, in: 0...10) { editing in
        if !editing {
          controller.seek(animation, to: time)
        }
      }
      HStack {
        Picker("Rate", selection: $rate) {
          ForEach(Self.rates, id: \.self) { rate in
            Text("\(rate.formatted())×").tag(rate)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: rate) { controller.setRate(rate, of: animation) }
        Button(finish == .finished ? "Finished" : "Wait") {
          finish = .waiting
          Task {
            await animation.finished()
            finish = .finished
          }
        }
        .disabled(finish == .waiting)
        .buttonStyle(.bordered)
      }
    }
    .buttonStyle(.borderless)
  }

  /// The ID of an element, or its name.
  private func label(of element: SVGDocument.Element) -> String {
    element.attribute("id").map { "#\($0)" } ?? element.localName
  }
}

/// An SVGUIView that plays the animations of a file, which the controller controls.
private struct ControlledSVGView: UIViewRepresentable {
  let url: URL
  let controller: AnimationController

  func makeUIView(context _: Context) -> SVGUIView {
    let view = SVGUIView(frame: .zero, data: try? Data(contentsOf: url))
    view.contentMode = .scaleAspectFit
    view.configuration = SVGUIViewConfiguration(animation: .play)
    controller.view = view
    return view
  }

  func updateUIView(_: SVGUIView, context _: Context) {}

  /// The size that SwiftUI proposes, as SVGView takes, instead of the size of the document.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: SVGUIView, context _: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions(by: uiView.intrinsicContentSize)
  }
}
