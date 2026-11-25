import CoreGraphics
import Foundation

// The computed values as text, in the forms that `getComputedStyle()` of CSSOM gives them in browsers: colors as
// `rgb()` with `currentcolor` resolved, lengths in pixels where they're absolute, and numbers with at most six
// significant digits.

extension SVGBaseContext {
  /// The computed value of a property of an element of the document as text, as ``ComputedStyle/serializedValue(of:)``
  /// gives it, or `nil` if the document has no such element or SVGUIView doesn't know the property.
  ///
  /// The values are the ones of this context, so a context at a time has the values that its animations give then.
  package func computedValue(of property: String, for element: ElementID) -> String? {
    guard let root, let chain = RenderTreeBuilder.chain(to: element, from: root) else { return nil }
    return chain.last?.base.style.serializedValue(of: property)
  }
}

extension DocumentTree {
  /// The computed value of a property of an element as text, with the style sheets of the `<style>` elements and
  /// without animations, for a document that no view shows, or `nil` if the tree has no such element or SVGUIView
  /// doesn't know the property.
  package func computedValue(of property: String, for element: ElementID) -> String? {
    let stylesheet = StyleSheetSources(document: self, processingInstructions: []).stylesheet
    return SVGBaseContext(document: self, stylesheet: stylesheet).computedValue(of: property, for: element)
  }
}

extension ComputedStyle {
  /// The value of a property as text, as `getPropertyValue()` of the style that `getComputedStyle()` returns gives
  /// it, or `nil` if SVGUIView doesn't know the property.
  ///
  /// - Parameter name: The name of a property, such as `fill`, whose case doesn't matter, or of a custom property,
  ///   such as `--size`, whose case does.
  package func serializedValue(of name: String) -> String? {
    if name.hasPrefix("--") { return customProperties[name] }
    let name = name.lowercased()
    if name == "marker" {
      // The shorthand has a value only where its longhands are the same.
      let values = [markerStart, markerMid, markerEnd].map(CSSText.marker)
      return values.allSatisfy { $0 == values[0] } ? values[0] : ""
    }
    return PropertyID(rawValue: name).map(serializedValue)
  }

  private func serializedValue(of id: PropertyID) -> String {
    switch id {
    case .fontFamily: CSSText.fontFamily(fontFamily)
    case .fontSize: fontSizeText
    case .fontWeight: CSSText.fontWeight(fontWeight)
    case .fontStyle: CSSText.fontStyle(fontStyle)
    case .writingMode: writingMode.rawValue
    case .color: CSSText.color(color)
    case .fill: paintText(fill)
    case .fillOpacity: CSSText.opacity(fillOpacity)
    case .fillRule: fillRule.rawValue
    case .stroke: paintText(stroke)
    case .strokeOpacity: CSSText.opacity(strokeOpacity)
    case .strokeWidth: CSSText.length(strokeWidth)
    case .strokeLinecap: CSSText.lineCap(strokeLinecap)
    case .strokeLinejoin: CSSText.lineJoin(strokeLinejoin)
    case .strokeMiterlimit: CSSText.number(strokeMiterlimit)
    case .strokeDasharray:
      strokeDasharray.isEmpty ? "none" : strokeDasharray.map(CSSText.length).joined(separator: ", ")
    case .strokeDashoffset: CSSText.length(strokeDashoffset)
    case .paintOrder: CSSText.paintOrder(paintOrder)
    case .shapeRendering: shapeRendering.rawValue.lowercased()
    case .imageRendering: imageRendering.rawValue
    case .imageOrientation: imageOrientation.rawValue
    case .pointerEvents: pointerEvents.rawValue.lowercased()
    case .clipRule: clipRule.rawValue
    case .textAnchor: textAnchor.rawValue
    case .direction: direction.rawValue
    case .unicodeBidi: unicodeBidi.rawValue
    case .textOrientation: textOrientation.rawValue
    case .glyphOrientationVertical: CSSText.glyphOrientation(glyphOrientationVertical)
    case .whiteSpace: whiteSpace.rawValue
    case .textDecoration: CSSText.textDecoration(textDecoration)
    case .letterSpacing: CSSText.letterSpacing(letterSpacing)
    case .wordSpacing: CSSText.length(wordSpacing)
    case .dominantBaseline: dominantBaseline.rawValue
    case .alignmentBaseline: alignmentBaseline.rawValue
    case .baselineShift: CSSText.baselineShift(baselineShift)
    case .markerStart: CSSText.marker(markerStart)
    case .markerMid: CSSText.marker(markerMid)
    case .markerEnd: CSSText.marker(markerEnd)
    case .visibility: visibility.rawValue
    case .colorInterpolation: colorInterpolation?.rawValue.lowercased() ?? "srgb"
    case .colorInterpolationFilters: colorInterpolationFilters?.rawValue.lowercased() ?? "linearrgb"
    case .opacity: CSSText.opacity(opacity)
    case .mixBlendMode: mixBlendMode.rawValue
    case .isolation: isolation.rawValue
    case .maskType: maskType.rawValue
    case .transform: CSSText.transform(transform)
    case .transformOrigin: "\(CSSText.length(transformOrigin.x)) \(CSSText.length(transformOrigin.y))"
    case .transformBox: transformBox.rawValue
    case .clipPath: CSSText.clipPath(clipPath)
    case .mask: CSSText.mask(mask)
    case .filter: filterText
    case .display: display.rawValue
    case .overflow: overflow.rawValue
    case .stopColor: CSSText.color(resolved(stopColor))
    case .stopOpacity: CSSText.opacity(stopOpacity)
    case .floodColor: CSSText.color(resolved(floodColor))
    case .floodOpacity: CSSText.opacity(floodOpacity)
    case .lightingColor: CSSText.color(resolved(lightingColor))
    // The initial value of the coordinates is 0, and of the sizes and the radii of an ellipse `auto`.
    case .x: CSSText.length(x ?? .number(0))
    case .y: CSSText.length(y ?? .number(0))
    case .width: width.map(CSSText.length) ?? "auto"
    case .height: height.map(CSSText.length) ?? "auto"
    case .cx: CSSText.length(cx ?? .number(0))
    case .cy: CSSText.length(cy ?? .number(0))
    case .r: CSSText.length(r ?? .number(0))
    case .rx: rx.map(CSSText.length) ?? "auto"
    case .ry: ry.map(CSSText.length) ?? "auto"
    case .d: CSSText.path(d)
    case .animationName: CSSText.list(animationName, CSSText.animationName)
    case .animationDuration: CSSText.list(animationDuration, CSSText.time)
    case .animationTimingFunction: CSSText.list(animationTimingFunction, CSSText.easing)
    case .animationDelay: CSSText.list(animationDelay, CSSText.time)
    case .animationIterationCount: CSSText.list(animationIterationCount, CSSText.iterationCount)
    case .animationDirection: CSSText.list(animationDirection, \.rawValue)
    case .animationFillMode: CSSText.list(animationFillMode, \.rawValue)
    case .animationPlayState: CSSText.list(animationPlayState, \.rawValue)
    case .transitionProperty: CSSText.list(transitionProperty, CSSText.transitionProperty)
    case .transitionDuration: CSSText.list(transitionDuration, CSSText.time)
    case .transitionTimingFunction: CSSText.list(transitionTimingFunction, CSSText.easing)
    case .transitionDelay: CSSText.list(transitionDelay, CSSText.time)
    case .transitionBehavior: CSSText.list(transitionBehavior, \.rawValue)
    }
  }

  /// A paint with `currentcolor` resolved, as browsers give it.
  private func paintText(_ paint: Paint) -> String {
    switch resolved(paint) {
    case .none: "none"
    case .color(let color): CSSText.color(color)
    case .url(let id, let fallback): CSSText.url(id) + (fallback.map { " " + paintText($0) } ?? "")
    case .contextFill: "context-fill"
    case .contextStroke: "context-stroke"
    // `resolved(_:)` leaves no `currentcolor`.
    case .currentColor, .expression: CSSText.color(color)
    }
  }

  /// The size of the font in pixels, where a keyword is the size that it has with the font family.
  private var fontSizeText: String {
    switch fontSize {
    case .length(let length): CSSText.length(length)
    default: CSSText.number(font.sizeValue(context: NoLengthContext())) + "px"
    }
  }

  private var filterText: String {
    guard case .list(let functions) = filter else { return "none" }
    return functions.map { function in
      switch function {
      case .url(let id): CSSText.url(id)
      case .blur(let deviation): "blur(\(CSSText.length(deviation)))"
      case .dropShadow(let shadow, let dx, let dy, let deviation):
        "drop-shadow(\(CSSText.color(resolved(shadow))) \(CSSText.length(dx)) \(CSSText.length(dy)) \(CSSText.length(deviation)))"
      case .colorAdjust(let adjust, let amount): "\(adjust.rawValue)(\(CSSText.number(amount)))"
      case .hueRotate(let angle): "hue-rotate(\(CSSText.number(angle))deg)"
      }
    }.joined(separator: " ")
  }
}

/// A context for the lengths that don't need one, such as the sizes of the keywords of `font-size`.
private struct NoLengthContext: SVGLengthContext {
  var viewBoxSize: CGSize { .zero }
  var font: SVGUIFont? { nil }
  var textScale: Double { 1 }
  var rootFont: SVGUIFont? { nil }
  var viewPort: CGRect { .zero }
  var writingMode: WritingMode? { nil }
  var documentFonts: DocumentFonts? { nil }
}

/// The texts of computed values.
enum CSSText {
  /// A number with at most six significant digits, without zeros at the end, as browsers write numbers.
  static func number(_ value: Double) -> String {
    guard value.isFinite else { return value.isNaN ? "NaN" : value < 0 ? "-infinity" : "infinity" }
    if value == 0 { return "0" }
    let digits = max(0, 5 - Int(floor(log10(abs(value)))))
    var text = String(format: "%.\(digits)f", value)
    if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
    }
    return text == "-0" ? "0" : text
  }

  /// The pixels in a unit of an absolute length, or `nil` for a unit that's relative.
  private static func pixels(per length: SVGLength) -> (value: Double, scale: Double)? {
    switch length {
    case .number(let value), .pixel(let value): (value, 1)
    case .inches(let value): (value, 96)
    case .centimeters(let value): (value, 96 / 2.54)
    case .millimeters(let value): (value, 96 / 25.4)
    case .q(let value): (value, 96 / 101.6)
    case .points(let value): (value, 96 / 72)
    case .picas(let value): (value, 16)
    default: nil
    }
  }

  /// A length in pixels where it's absolute, and as it's written otherwise, such as a percentage, which is resolved
  /// where it's used.
  static func length(_ length: SVGLength) -> String {
    if let (value, scale) = pixels(per: length) { return number(value * scale) + "px" }
    switch length {
    case .sum(let sum): return calc(.sum(sum.terms.map(CalcNode.length)))
    // The clamp of a property whose value can't be negative isn't written, as browsers don't write it.
    case .calc(let expression):
      if case .max(let nodes) = expression.node, nodes.count == 2, nodes[1] == .length(.pixel(0)) {
        return calc(nodes[0])
      }
      return calc(expression.node)
    case .percent(let value): return number(value) + "%"
    case .ems(let value): return number(value) + "em"
    case .rems(let value): return number(value) + "rem"
    case .exs(let value): return number(value) + "ex"
    case .chs(let value): return number(value) + "ch"
    case .ic(let value): return number(value) + "ic"
    case .lhs(let value): return number(value) + "lh"
    case .rlhs(let value): return number(value) + "rlh"
    case .vw(let value): return number(value) + "vw"
    case .vh(let value): return number(value) + "vh"
    case .vi(let value): return number(value) + "vi"
    case .vb(let value): return number(value) + "vb"
    case .vmin(let value): return number(value) + "vmin"
    case .vmax(let value): return number(value) + "vmax"
    case .number, .pixel, .inches, .centimeters, .millimeters, .q, .points, .picas:
      preconditionFailure("an absolute length is in pixels")
    }
  }

  /// A math function, which is a length in pixels if it has no relative lengths.
  private static func calc(_ node: CalcNode) -> String {
    if let value = absoluteValue(node) { return number(value) + "px" }
    let text = calcText(node)
    return text.hasPrefix("min(") || text.hasPrefix("max(") || text.hasPrefix("clamp(") ? text : "calc(\(text))"
  }

  /// The value of a math function in pixels, or `nil` if it has a percentage or a relative length.
  private static func absoluteValue(_ node: CalcNode) -> Double? {
    switch node {
    case .number(let value): value
    case .length(let length): pixels(per: length).map { $0.value * $0.scale }
    case .sum(let nodes): nodes.reduce(0) { sum, node in sum.flatMap { sum in absoluteValue(node).map { sum + $0 } } }
    case .product(let nodes):
      nodes.reduce(1) { product, node in product.flatMap { product in absoluteValue(node).map { product * $0 } } }
    case .inverse(let node): absoluteValue(node).map { 1 / $0 }
    case .min(let nodes): values(nodes).map { $0.min()! }
    case .max(let nodes): values(nodes).map { $0.max()! }
    case .clamp(let low, let value, let high):
      values([low, value, high]).map { max($0[0], min($0[1], $0[2])) }
    case .percentage, .angle, .channel: nil
    }
  }

  private static func values(_ nodes: [CalcNode]) -> [Double]? {
    let values = nodes.compactMap(absoluteValue)
    return values.count == nodes.count && !values.isEmpty ? values : nil
  }

  /// The text of a node of a math function, where a sum adds its percentages first, its lengths in pixels next,
  /// and its other lengths last, as browsers order them.
  private static func calcText(_ node: CalcNode) -> String {
    switch node {
    case .number(let value): return number(value)
    case .percentage(let value): return number(value) + "%"
    case .length(.percent(let value)): return number(value) + "%"
    case .length(let length): return CSSText.length(length)
    case .angle(let value): return number(value) + "deg"
    case .channel(let name): return name
    case .sum(let nodes):
      let percentages = nodes.filter { if case .percentage = $0 { true } else if case .length(.percent) = $0 { true } else { false } }
      let absolute = nodes.compactMap(absoluteValue)
      let others = nodes.filter { node in
        absoluteValue(node) == nil && !percentages.contains(node)
      }
      var terms = percentages.map(calcText)
      if absolute.count > 0 { terms.append(number(absolute.reduce(0, +)) + "px") }
      terms += others.map(calcText)
      return terms.enumerated().map { index, term in
        guard index > 0 else { return term }
        return term.hasPrefix("-") ? "- " + term.dropFirst() : "+ " + term
      }.joined(separator: " ")
    case .product(let nodes): return nodes.map(calcText).joined(separator: " * ")
    case .inverse(let node): return "1 / \(calcText(node))"
    case .min(let nodes): return "min(\(nodes.map(calcText).joined(separator: ", ")))"
    case .max(let nodes): return "max(\(nodes.map(calcText).joined(separator: ", ")))"
    case .clamp(let low, let value, let high): return "clamp(\(calcText(low)), \(calcText(value)), \(calcText(high)))"
    }
  }

  /// A color as `rgb()` or `rgba()`, or as `color(srgb …)` where its components aren't whole numbers, such as a
  /// `color-mix()`, or are outside sRGB.
  static func color(_ color: SVGColor) -> String {
    if case .url(let id) = color { return url(id) }
    let (red, green, blue, alpha) = color.rgba
    let components = [red, green, blue]
    let isLegacy = components.allSatisfy { $0 >= 0 && $0 <= 255 && abs($0 - $0.rounded()) < 1e-6 }
    let opacity = alphaText(alpha / 255)
    guard isLegacy else {
      let text = components.map { number($0 / 255) }.joined(separator: " ")
      return opacity == "1" ? "color(srgb \(text))" : "color(srgb \(text) / \(opacity))"
    }
    let text = components.map { String(Int($0.rounded())) }.joined(separator: ", ")
    return opacity == "1" ? "rgb(\(text))" : "rgba(\(text), \(opacity))"
  }

  /// An alpha as browsers write it: the alpha of 8 bits, with two decimals if they give the same 8 bits, and three
  /// otherwise.
  private static func alphaText(_ alpha: Double) -> String {
    let bits = (min(max(alpha, 0), 1) * 255).rounded()
    let twoDecimals = (bits / 255 * 100).rounded() / 100
    if (twoDecimals * 255).rounded() == bits { return number(twoDecimals) }
    return number((bits / 255 * 1000).rounded() / 1000)
  }

  static func url(_ id: String) -> String {
    let reference = id.hasPrefix("#") || id.contains("/") || id.contains(":") ? id : "#" + id
    return "url(\"\(reference)\")"
  }

  /// The families of a font, with the names in quotes in double quotes.
  static func fontFamily(_ text: String) -> String {
    var families = [String]()
    var current = ""
    var quote: Character?
    for character in text {
      if let open = quote {
        if character == open { quote = nil }
        current.append(character == open ? "\"" : character)
      } else if character == "\"" || character == "'" {
        quote = character
        current.append("\"")
      } else if character == "," {
        families.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    families.append(current)
    return families.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }.joined(separator: ", ")
  }

  static func fontWeight(_ weight: SVGUIFont.Weight) -> String {
    switch weight {
    case .normal: "400"
    case .lighter: "100"
    case .bold, .bolder: "700"
    case .number(let value): number(value)
    }
  }

  static func fontStyle(_ style: FontStyle) -> String {
    switch style {
    case .normal: "normal"
    case .italic: "italic"
    case .oblique(nil): "oblique"
    case .oblique(let angle?): "oblique \(number(angle))deg"
    }
  }

  static func lineCap(_ cap: CGLineCap) -> String {
    switch cap {
    case .butt: "butt"
    case .round: "round"
    case .square: "square"
    @unknown default: "butt"
    }
  }

  static func lineJoin(_ join: CGLineJoin) -> String {
    switch join {
    case .miter: "miter"
    case .round: "round"
    case .bevel: "bevel"
    @unknown default: "miter"
    }
  }

  /// The order of painting, with the layers at the end left out where they're in their normal order.
  static func paintOrder(_ order: PaintOrder) -> String {
    guard order != .normal else { return "normal" }
    let names = order.layers.map {
      switch $0 {
      case .fill: "fill"
      case .stroke: "stroke"
      case .markers: "markers"
      }
    }
    return PaintOrder(first: [order.layers[0]]) == order ? names[0] : names[0...1].joined(separator: " ")
  }

  static func glyphOrientation(_ orientation: TextOrientation?) -> String {
    switch orientation {
    case nil: "auto"
    case .upright?: "0deg"
    default: "90deg"
    }
  }

  static func textDecoration(_ lines: TextDecorationLines) -> String {
    let names: [(TextDecorationLines, String)] = [
      (.underline, "underline"), (.overline, "overline"), (.lineThrough, "line-through"),
    ]
    let text = names.filter { lines.contains($0.0) }.map(\.1).joined(separator: " ")
    return text.isEmpty ? "none" : text
  }

  /// An opacity, which is clamped to 0 to 1.
  static func opacity(_ value: Double) -> String {
    number(min(max(value, 0), 1))
  }

  /// A spacing between letters, whose `normal` is 0, as browsers write 0.
  static func letterSpacing(_ length: SVGLength) -> String {
    if let (value, _) = pixels(per: length), value == 0 { return "normal" }
    return CSSText.length(length)
  }

  static func baselineShift(_ shift: BaselineShift) -> String {
    switch shift {
    case .baseline: "0px"
    case .sub: "sub"
    case .super: "super"
    case .length(let length): CSSText.length(length)
    }
  }

  static func marker(_ reference: SVGMarkerReference) -> String {
    reference.id.map(url) ?? "none"
  }

  static func mask(_ mask: SVGMask) -> String {
    if case .url(let id) = mask { url(id) } else { "none" }
  }

  /// A transform as the matrix of its functions, where a translation by a percentage, which is of the reference
  /// box, keeps the functions.
  static func transform(_ list: TransformList) -> String {
    guard !list.functions.isEmpty else { return "none" }
    var matrix = CGAffineTransform.identity
    for function in list.functions {
      switch function {
      case .translate(let x, let y):
        guard let (x, xScale) = pixels(per: x), let (y, yScale) = pixels(per: y) else { return functionsText(list) }
        matrix = matrix.translatedBy(x: x * xScale, y: y * yScale)
      case .scale(let x, let y): matrix = matrix.scaledBy(x: x, y: y)
      case .rotate(let angle): matrix = matrix.rotated(by: angle * .pi / 180)
      case .skew(let x, let y):
        matrix = CGAffineTransform(a: 1, b: tan(y * .pi / 180), c: tan(x * .pi / 180), d: 1, tx: 0, ty: 0)
          .concatenating(matrix)
      case .matrix(let transform): matrix = transform.concatenating(matrix)
      }
    }
    let values = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].map { number($0) }
    return "matrix(\(values.joined(separator: ", ")))"
  }

  private static func functionsText(_ list: TransformList) -> String {
    list.functions.map { function in
      switch function {
      case .translate(let x, let y): "translate(\(length(x)), \(length(y)))"
      case .scale(let x, let y): "scale(\(number(x)), \(number(y)))"
      case .rotate(let angle): "rotate(\(number(angle))deg)"
      case .skew(let x, let y): "skew(\(number(x))deg, \(number(y))deg)"
      case .matrix(let m): "matrix(\([m.a, m.b, m.c, m.d, m.tx, m.ty].map { number($0) }.joined(separator: ", ")))"
      }
    }.joined(separator: " ")
  }

  static func clipPath(_ clipPath: SVGClipPath) -> String {
    switch clipPath {
    case .none: "none"
    case .url(let id): url(id)
    case .shape(let shape?, .strokeBox): basicShape(shape)
    case .shape(let shape?, let box): "\(basicShape(shape)) \(clipBox(box))"
    case .shape(nil, let box): clipBox(box)
    }
  }

  private static func clipBox(_ box: ClipBox) -> String {
    switch box {
    case .fillBox: "fill-box"
    case .strokeBox: "stroke-box"
    case .viewBox: "view-box"
    }
  }

  private static func basicShape(_ shape: BasicShape) -> String {
    func radius(_ radius: ShapeRadius) -> String? {
      switch radius {
      case .length(let value): length(value)
      case .closestSide: nil
      case .farthestSide: "farthest-side"
      }
    }
    func position(_ position: ShapePosition) -> String { "\(length(position.x)) \(length(position.y))" }
    func at(_ center: ShapePosition) -> String? { center == .center ? nil : "at \(position(center))" }
    switch shape {
    case .circle(let r, let center):
      return "circle(\([radius(r), at(center)].compactMap { $0 }.joined(separator: " ")))"
    case .ellipse(let rx, let ry, let center):
      let radii = rx == .closestSide && ry == .closestSide ? nil : "\(radius(rx) ?? "closest-side") \(radius(ry) ?? "closest-side")"
      return "ellipse(\([radii, at(center)].compactMap { $0 }.joined(separator: " ")))"
    case .inset(let inset):
      let sides = [inset.top, inset.right, inset.bottom, inset.left].map(length)
      let horizontal = shortest(inset.radii.map { length($0.x) })
      let vertical = shortest(inset.radii.map { length($0.y) })
      var round = ""
      if horizontal != ["0px"] || vertical != ["0px"] {
        round = " round " + horizontal.joined(separator: " ")
        if vertical != horizontal { round += " / " + vertical.joined(separator: " ") }
      }
      return "inset(\(shortest(sides).joined(separator: " "))\(round))"
    case .polygon(let rule, let points):
      let list = points.map(position).joined(separator: ", ")
      return rule == .evenodd ? "polygon(evenodd, \(list))" : "polygon(\(list))"
    }
  }

  /// Four values of the sides or the corners of a box, without the ones at the end that repeat the ones before them,
  /// as the shorthands of CSS leave them out.
  private static func shortest(_ values: [String]) -> [String] {
    var values = values
    if values.count == 4, values[3] == values[1] {
      values.removeLast()
      if values[2] == values[0] {
        values.removeLast()
        if values[1] == values[0] { values.removeLast() }
      }
    }
    return values
  }

  static func path(_ data: PathData) -> String {
    guard !data.commands.isEmpty else { return "none" }
    let text = data.commands.map { command in
      ([command.type.name] + command.values.map { number($0) }).joined(separator: " ")
    }.joined(separator: " ")
    return "path(\"\(text)\")"
  }

  static func list<Element>(_ values: [Element], _ text: (Element) -> String) -> String {
    values.map(text).joined(separator: ", ")
  }

  static func time(_ seconds: Double) -> String {
    number(seconds) + "s"
  }

  static func animationName(_ name: AnimationName) -> String {
    switch name {
    case .none: "none"
    case .keyframes(let name): name
    }
  }

  static func iterationCount(_ count: AnimationIterationCount) -> String {
    switch count {
    case .count(let count): number(count)
    case .infinite: "infinite"
    }
  }

  static func transitionProperty(_ property: TransitionProperty) -> String {
    switch property {
    case .none: "none"
    case .all: "all"
    case .property(let id): id.rawValue
    case .unrecognized(let name): name
    }
  }

  static func easing(_ function: EasingFunction) -> String {
    switch function {
    case .linear: return "linear"
    case .ease: return "ease"
    case .easeIn: return "ease-in"
    case .easeOut: return "ease-out"
    case .easeInOut: return "ease-in-out"
    case .cubicBezier(let x1, let y1, let x2, let y2):
      return "cubic-bezier(\([x1, y1, x2, y2].map { number($0) }.joined(separator: ", ")))"
    case .steps(let count, let position):
      switch position {
      case .jumpEnd: return "steps(\(count))"
      case .jumpStart: return "steps(\(count), jump-start)"
      case .jumpNone: return "steps(\(count), jump-none)"
      case .jumpBoth: return "steps(\(count), jump-both)"
      }
    case .piecewiseLinear(let points):
      return "linear(\(points.map { "\(number($0.output)) \(number($0.input * 100))%" }.joined(separator: ", ")))"
    }
  }
}
