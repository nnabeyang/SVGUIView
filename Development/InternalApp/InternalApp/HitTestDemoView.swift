import SVGUIView
import SwiftUI

/// The demonstration of finding the elements at a point of the view, as an app that edits shapes picks the shape
/// under a finger.
struct HitTestDemo: Hashable {}

/// Shows a document of the cases that hit testing tells apart, and outlines the frontmost element where a finger
/// touches, with the bounding box and the transform of the element, while the list under the view shows every
/// element there from the front.
///
/// The tolerance widens what a finger hits, in points of the view, so that it can pick the thin line, and a circle
/// around the touch shows it.
struct HitTestDemoView: View {
  @State private var tolerance = 0.0
  @State private var hits = [Hit]()
  @State private var touched = false

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Tolerance")
        Slider(value: $tolerance, in: 0...20, step: 1)
        Text("\(Int(tolerance)) pt")
          .monospacedDigit()
          .frame(minWidth: 44, alignment: .trailing)
      }
      .padding(.horizontal)

      HitTestingSVGView(tolerance: tolerance) { hits in
        self.hits = hits
        touched = true
      }
      .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
      .padding(.horizontal)

      List {
        Section("Elements at the point, from the front") {
          if hits.isEmpty {
            Text(touched ? "None" : "Touch the view, or drag on it.")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
            VStack(alignment: .leading, spacing: 2) {
              Text(hit.name)
                .font(.body.monospaced())
                .fontWeight(index == 0 ? .bold : .regular)
              if let note = hit.note {
                Text(note)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .listStyle(.plain)
      .frame(height: 160)
    }
    .padding(.vertical)
    .navigationTitle("Hit Testing")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// An element that a point hits.
struct Hit {
  /// The tag name of the element with its `id` or its classes.
  let name: String
  /// What the outline shows of the element, if it isn't the element's own bounding box.
  let note: String?
}

/// A view of the document that hit-tests where a finger touches, and outlines the frontmost element.
private struct HitTestingSVGView: UIViewRepresentable {
  let tolerance: Double
  /// Called with the elements at the point that the finger last touched.
  let onHits: ([Hit]) -> Void

  func makeUIView(context _: Context) -> HitTestCanvas {
    let canvas = HitTestCanvas(data: Data(Self.document.utf8))
    canvas.tolerance = tolerance
    canvas.onHits = onHits
    return canvas
  }

  func updateUIView(_ canvas: HitTestCanvas, context _: Context) {
    canvas.tolerance = tolerance
    canvas.onHits = onHits
  }

  /// The size that SwiftUI proposes, as SVGView takes, instead of the size of the document.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: HitTestCanvas, context _: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions(by: uiView.intrinsicContentSize)
  }

  /// A document of 400 by 400 units in cells of 100 by 100, each with a case and its label.
  private static let document = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" font-family="sans-serif">
      <style>
        .label { font-size: 9px; fill: #666; pointer-events: none }
        .cell { fill: none; stroke: #ddd }
      </style>
      <defs>
        <rect id="tile" width="40" height="40" rx="6" fill="slateblue"/>
        <marker id="dot" markerWidth="20" markerHeight="20" refX="10" refY="10" markerUnits="userSpaceOnUse">
          <circle cx="10" cy="10" r="9" fill="orange"/>
        </marker>
        <clipPath id="round"><circle cx="350" cy="50" r="30"/></clipPath>
        <mask id="clear"><rect width="400" height="400" fill="black"/></mask>
      </defs>
      <g id="grid" pointer-events="none">
        <path class="cell" d="M100 0V400M200 0V400M300 0V400M0 100H400M0 200H400M0 300H400"/>
      </g>

      <g id="overlap">
        <rect id="back" x="10" y="15" width="55" height="55" fill="seagreen"/>
        <rect id="front" x="35" y="35" width="55" height="45" fill="tomato"/>
      </g>
      <text class="label" x="5" y="95">overlap</text>

      <path id="ring" fill="teal" fill-rule="evenodd" d="M110 10h80v70h-80zM130 25h40v40h-40z"/>
      <text class="label" x="105" y="95">evenodd hole</text>

      <line id="dashed" x1="215" y1="30" x2="285" y2="30" stroke="navy" stroke-width="10"
        stroke-dasharray="12 10" stroke-linecap="round"/>
      <rect id="outline" x="215" y="50" width="70" height="30" fill="none" stroke="navy" stroke-width="4"/>
      <text class="label" x="205" y="95">dashes, fill none</text>

      <rect id="clipped" x="310" y="10" width="80" height="80" fill="purple" clip-path="url(#round)"/>
      <text class="label" x="305" y="95">clip path</text>

      <use id="tile-use" href="#tile" x="30" y="130"/>
      <text class="label" x="5" y="195">use</text>

      <path id="marked" d="M120 150H175" stroke="black" stroke-width="3" marker-end="url(#dot)"/>
      <text class="label" x="105" y="195">marker (not hit)</text>

      <text id="text" x="210" y="160" font-size="24" fill="black">Ab<tspan id="span" fill="crimson">Cd</tspan></text>
      <text class="label" x="205" y="195">text and tspan</text>

      <rect id="masked" x="315" y="115" width="70" height="60" fill="gold" mask="url(#clear)"/>
      <text class="label" x="305" y="195">mask (hit)</text>

      <rect id="transparent" x="15" y="215" width="70" height="60" fill="gray" opacity="0"/>
      <text class="label" x="5" y="295">opacity 0 (hit)</text>

      <rect id="hidden" x="115" y="215" width="70" height="60" fill="gray" visibility="hidden"/>
      <rect id="hidden-all" x="135" y="235" width="30" height="20" fill="gray" visibility="hidden"
        pointer-events="all"/>
      <text class="label" x="105" y="295">hidden, inner: all</text>

      <rect id="under" x="215" y="215" width="70" height="60" fill="lightsteelblue"/>
      <rect id="cover" x="215" y="215" width="70" height="30" fill="steelblue" fill-opacity="0.5"
        pointer-events="none"/>
      <text class="label" x="205" y="295">pointer-events none</text>

      <rect id="box-target" x="320" y="225" width="20" height="20" fill="none" stroke="darkgreen"
        stroke-width="2" pointer-events="bounding-box"/>
      <circle id="box-circle" cx="365" cy="255" r="20" fill="darkgreen" pointer-events="bounding-box"/>
      <text class="label" x="305" y="295">bounding-box</text>

      <line id="thin" x1="15" y1="350" x2="185" y2="350" stroke="black" stroke-width="0.5"/>
      <text class="label" x="5" y="395">thin line (tolerance)</text>

      <g id="turned" transform="rotate(20 300 350)">
        <rect id="rotated" x="250" y="330" width="100" height="40" fill="coral"/>
        <svg id="inner" x="330" y="330" width="40" height="40" viewBox="0 0 10 10">
          <circle id="nested" cx="5" cy="5" r="4" fill="indigo"/>
        </svg>
      </g>
      <text class="label" x="205" y="395">transforms, nested svg</text>
    </svg>
    """##
}

/// An SVGUIView with a layer over it that outlines the frontmost element at the point that a finger touches.
private final class HitTestCanvas: UIView {
  private let svgView: SVGUIView
  var tolerance = 0.0
  var onHits: ([Hit]) -> Void = { _ in }

  /// The outline of the bounding box of the frontmost element.
  private let outline = CAShapeLayer()
  /// The circle of the tolerance around the touch, or a dot without a tolerance.
  private let touch = CAShapeLayer()
  /// Hit-tests the last point, which a later touch cancels.
  private var hitTesting: Task<Void, Never>?
  /// The size that the outline was found for.
  private var laidOutSize = CGSize.zero

  init(data: Data) {
    svgView = SVGUIView(frame: .zero, data: data)
    super.init(frame: .zero)
    svgView.contentMode = .scaleAspectFit
    addSubview(svgView)
    // A press without a minimum duration begins when the finger touches, and follows it while it drags, without
    // the swipe back of the navigation taking a drag to the right.
    let press = UILongPressGestureRecognizer(target: self, action: #selector(press(_:)))
    press.minimumPressDuration = 0
    press.allowableMovement = .greatestFiniteMagnitude
    addGestureRecognizer(press)
    outline.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
    outline.strokeColor = UIColor.systemBlue.cgColor
    outline.lineWidth = 2
    outline.lineDashPattern = [6, 3]
    touch.fillColor = UIColor.systemPink.withAlphaComponent(0.15).cgColor
    touch.strokeColor = UIColor.systemPink.cgColor
    touch.lineWidth = 1
    layer.addSublayer(outline)
    layer.addSublayer(touch)
    clipsToBounds = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize { svgView.intrinsicContentSize }

  override func layoutSubviews() {
    super.layoutSubviews()
    svgView.frame = bounds
    // At another size, the view places the document again, so the outline would be in the wrong place.
    guard bounds.size != laidOutSize else { return }
    laidOutSize = bounds.size
    hitTesting?.cancel()
    setLayers(outline: nil, touchAt: nil)
  }

  @objc private func press(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began, .changed:
      hitTest(at: gesture.location(in: svgView))
    default:
      break
    }
  }

  private func hitTest(at point: CGPoint) {
    let tolerance = CGFloat(tolerance)
    setLayers(outline: outline.path, touchAt: point, tolerance: tolerance)
    hitTesting?.cancel()
    hitTesting = Task { [weak self] in
      guard let document = self?.svgView.document else { return }
      let elements = await document.elements(at: point, tolerance: tolerance)
      var hits = elements.map { Hit(name: Self.name(of: $0), note: nil) }
      var path: CGPath?
      if let front = elements.first, let outlined = await Self.outline(of: front) {
        path = outlined.path
        if outlined.element != front {
          hits[0] = Hit(name: hits[0].name, note: "Outlined: the box of \(Self.name(of: outlined.element))")
        }
      }
      guard !Task.isCancelled, let self else { return }
      setLayers(outline: path, touchAt: point, tolerance: tolerance)
      onHits(hits)
    }
  }

  /// The bounding box of an element in the coordinates of the view, or of its nearest ancestor that has one, and the
  /// element that it's of.
  private static func outline(
    of element: SVGDocument.Element
  ) async -> (path: CGPath, element: SVGDocument.Element)? {
    var current: SVGDocument.Element? = element
    while let element = current {
      if let box = await element.boundingBox(), var transform = await element.transformToView() {
        return (CGPath(rect: box, transform: &transform), element)
      }
      current = element.parent
    }
    return nil
  }

  /// The tag name of an element with its `id`, or its classes if it has no `id`.
  private static func name(of element: SVGDocument.Element) -> String {
    if let id = element.attribute("id") { return "<\(element.localName)> #\(id)" }
    let classes = element.classList.names
    return classes.isEmpty ? "<\(element.localName)>" : "<\(element.localName)> .\(classes.joined(separator: "."))"
  }

  /// Shows the outline and the touch, without the implicit animations of the layers.
  private func setLayers(outline path: CGPath?, touchAt point: CGPoint?, tolerance: CGFloat = 0) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.path = path
    touch.path = point.map {
      let radius = max(tolerance, 3)
      return CGPath(
        ellipseIn: CGRect(x: $0.x - radius, y: $0.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
    CATransaction.commit()
  }
}
