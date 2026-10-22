import CoreGraphics
import Foundation
import Testing
import _CSSParser

@testable import SVGCore

/// The declared value of a declaration in a style sheet, such as the part of `fill: red` after the colon.
private func declared<P: StyleProperty>(_: P.Type, css text: String) -> Declared<P.Specified>? {
  var input = _CSSParser.Parser(input: ParserInput(input: text))
  return P.declared(css: &input)
}

private func style(
  _ declarations: [PropertyDeclaration], parent: ComputedStyle? = nil, root: ComputedStyle? = nil
) -> ComputedStyle {
  ComputedStyle(cascaded: CascadedValues(declarations), parent: parent, root: root)
}

/// The size in pixels, or `nil` for a size in another unit or a keyword.
private func pixels(_ size: SVGUIFont.Size) -> CGFloat? {
  if case .length(.pixel(let value)) = size { return value }
  return nil
}

@Suite("Style")
struct StyleTests {
  @Test("every property is described by the type for its name")
  func registryMatchesNames() {
    for id in PropertyID.allCases {
      #expect(id.property.id == id)
    }
  }

  @Test("font-size is computed after font-family, and lengths after font-size")
  func computationOrder() throws {
    let order = PropertyID.allCases
    let family = try #require(order.firstIndex(of: .fontFamily))
    let size = try #require(order.firstIndex(of: .fontSize))
    for id in [PropertyID.strokeWidth, .x, .y, .width, .height] {
      let index = try #require(order.firstIndex(of: id))
      #expect(size < index)
    }
    #expect(family < size)
  }

  @Test("presentation attributes take inherit, but no other keyword that every property takes")
  func attributeKeywords() {
    #expect(OpacityProperty.declared(attribute: " inherit ").map { if case .inherit = $0 { true } else { false } } == true)
    #expect(OpacityProperty.declared(attribute: "initial") == nil)
    #expect(OpacityProperty.declared(attribute: "unset") == nil)
  }

  @Test("declarations in style sheets take inherit, initial and unset")
  func cssKeywords() {
    func kind(_ value: Declared<Double>?) -> String? {
      switch value {
      case .value: "value"
      case .inherit: "inherit"
      case .initial: "initial"
      case .unset: "unset"
      case nil: nil
      }
    }
    #expect(kind(declared(OpacityProperty.self, css: "INHERIT")) == "inherit")
    #expect(kind(declared(OpacityProperty.self, css: "initial")) == "initial")
    #expect(kind(declared(OpacityProperty.self, css: "unset")) == "unset")
    #expect(kind(declared(OpacityProperty.self, css: "0.5")) == "value")
    #expect(kind(declared(OpacityProperty.self, css: "foo")) == nil)
  }

  @Test("declarations in style sheets are parsed without their comments")
  func cssComments() {
    guard case .value(let width) = declared(StrokeWidthProperty.self, css: "/* a */ 2px /* b */") else {
      Issue.record("stroke-width isn't parsed")
      return
    }
    #expect(width == .pixel(2))
  }

  @Test("fill and stroke take none, currentColor, colors and paint servers")
  func paints() {
    func describe(_ value: Declared<Paint>?) -> String? {
      guard case .value(let paint) = value else { return nil }
      return switch paint {
      case .none: "none"
      case .currentColor: "currentColor"
      case .color(let color): color.description
      case .url(let id): "url(\(id))"
      }
    }
    #expect(describe(declared(FillProperty.self, css: "none")) == "none")
    #expect(describe(declared(FillProperty.self, css: "currentColor")) == "currentColor")
    #expect(describe(declared(FillProperty.self, css: "url(#a)")) == "url(a)")
    #expect(describe(StrokeProperty.declared(attribute: "currentcolor")) == "currentColor")
    #expect(describe(StrokeProperty.declared(attribute: "#ff0000")) == SVGColor.hex(SVGHexColor(hex: "ff0000")!).description)
  }

  @Test("a name that isn't a color and a function that isn't supported are invalid")
  func invalidColors() {
    #expect(FillProperty.declared(attribute: "bogus") == nil)
    #expect(StopColorProperty.declared(attribute: "hsla(120, 100%, 75%, 0.5)") == nil)
    #expect(declared(FloodColorProperty.self, css: "bogus") == nil)
    #expect(FillProperty.declared(attribute: "green") != nil)
  }

  @Test("transform in a style sheet")
  func cssTransform() {
    guard case .value(let transform) = declared(TransformProperty.self, css: "translate(10, 20) scale(2)") else {
      Issue.record("transform isn't parsed")
      return
    }
    #expect(transform == CGAffineTransform(translationX: 10, y: 20).scaledBy(x: 2, y: 2))
  }

  @Test("inherited properties take the value of the parent, and others the initial value")
  func inheritance() {
    let parent = style([
      PropertyDeclaration(FillOpacityProperty.self, .value(0.5)),
      PropertyDeclaration(OpacityProperty.self, .value(0.5)),
    ])
    let child = style([], parent: parent)
    #expect(child.fillOpacity == 0.5)
    #expect(child.opacity == 1)
  }

  @Test("inherit, initial and unset")
  func keywords() {
    let parent = style([
      PropertyDeclaration(FillOpacityProperty.self, .value(0.5)),
      PropertyDeclaration(OpacityProperty.self, .value(0.5)),
    ])
    let inherit = style(
      [
        PropertyDeclaration(FillOpacityProperty.self, .value(0.2)),
        PropertyDeclaration(OpacityProperty.self, .inherit),
      ], parent: parent)
    #expect(inherit.opacity == 0.5)
    let initial = style([PropertyDeclaration(FillOpacityProperty.self, .initial)], parent: parent)
    #expect(initial.fillOpacity == 1)
    let unset = style(
      [
        PropertyDeclaration(FillOpacityProperty.self, .unset),
        PropertyDeclaration(OpacityProperty.self, .unset),
      ], parent: parent)
    #expect(unset.fillOpacity == 0.5)
    #expect(unset.opacity == 1)
  }

  @Test("color: currentColor is the color of the parent, and fill: currentColor stays a keyword")
  func currentColor() {
    let parent = style([PropertyDeclaration(ColorProperty.self, .value(.color(.named(.init(name: "red")))))])
    let child = style(
      [
        PropertyDeclaration(ColorProperty.self, .value(.currentColor)),
        PropertyDeclaration(FillProperty.self, .value(.currentColor)),
      ], parent: parent)
    #expect(child.color.description == "red")
    guard case .currentColor = child.fill else {
      Issue.record("fill isn't currentColor")
      return
    }
    // A descendant with its own color paints with it.
    let grandchild = style([PropertyDeclaration(ColorProperty.self, .value(.color(.named(.init(name: "blue")))))], parent: child)
    guard case .color(let color) = grandchild.resolved(grandchild.fill) else {
      Issue.record("currentColor isn't resolved")
      return
    }
    #expect(color.description == "blue")
  }

  @Test("font-size relative to the parent")
  func relativeFontSizes() {
    let parent = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(20))))])
    func size(_ value: SVGUIFont.Size) -> CGFloat? {
      pixels(style([PropertyDeclaration(FontSizeProperty.self, .value(value))], parent: parent).fontSize)
    }
    #expect(size(.length(.ems(2))) == 40)
    #expect(size(.length(.percent(50))) == 10)
    #expect(size(.smaller) == 20 / 1.2)
    #expect(size(.larger) == 20 * 1.2)
    #expect(size(.length(.points(12))) == 16)
    // With no parent, sizes are relative to the initial size, medium.
    #expect(pixels(style([PropertyDeclaration(FontSizeProperty.self, .value(.smaller))]).fontSize) == 16 / 1.2)
  }

  @Test("font-size in rem is relative to the root")
  func rootRelativeFontSize() {
    let root = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(10))))])
    let parent = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(20))))], parent: root, root: root)
    let child = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.rems(3))))], parent: parent, root: root)
    #expect(pixels(child.fontSize) == 30)
  }

  @Test("font-size in viewport units stays in its unit")
  func viewportFontSize() {
    let parent = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.vw(2))))])
    let child = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.ems(1.5))))], parent: parent)
    guard case .length(.vw(let value)) = child.fontSize else {
      Issue.record("font-size isn't in vw")
      return
    }
    #expect(value == 3)
  }

  @Test("a font-size keyword stays a keyword, which monospace resolves to a smaller size")
  func fontSizeKeyword() {
    let parent = style([PropertyDeclaration(FontSizeProperty.self, .value(.medium))])
    let child = style([PropertyDeclaration(FontFamilyProperty.self, .value("monospace"))], parent: parent)
    guard case .medium = child.fontSize else {
      Issue.record("font-size isn't medium")
      return
    }
    #expect(child.font.sizeValue(context: SVGLengthContextStub()) == 13)
    #expect(parent.font.sizeValue(context: SVGLengthContextStub()) == 16)
  }

  @Test("lengths in em are relative to the element's own font-size")
  func emLengths() {
    let parent = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(10))))])
    let child = style(
      [
        PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(20)))),
        PropertyDeclaration(StrokeWidthProperty.self, .value(.ems(0.5))),
      ], parent: parent)
    #expect(child.strokeWidth == .pixel(10))
    // The computed value is inherited, not the em.
    let grandchild = style([PropertyDeclaration(FontSizeProperty.self, .value(.length(.pixel(40))))], parent: child)
    #expect(grandchild.strokeWidth == .pixel(10))
  }

  @Test(
    "lighter and bolder follow the table of CSS Fonts for the weight of the parent",
    arguments: [
      ("bold", "lighter", 400.0), ("normal", "lighter", 100), ("normal", "bolder", 700), ("bold", "bolder", 900),
      ("50", "lighter", 50), ("50", "bolder", 400), ("549", "lighter", 100), ("549", "bolder", 700),
      ("749", "lighter", 400), ("899", "lighter", 700), ("950", "lighter", 700), ("950", "bolder", 950),
    ])
  func relativeFontWeight(parent: String, child: String, weight: Double) throws {
    let parent = style([PropertyDeclaration(FontWeightProperty.self, .value(try #require(.init(rawValue: parent))))])
    let child = style(
      [PropertyDeclaration(FontWeightProperty.self, .value(try #require(.init(rawValue: child))))], parent: parent)
    #expect(child.fontWeight.value == FontSelectionValue(weight))
  }

  @Test("presentation attributes of geometry are taken only by rect")
  func geometryAttributes() {
    let rect = CascadedValues(CascadedValues.presentationAttributes(of: .rect, attributes: ["x": "10", "fill": "red"]))
    let circle = CascadedValues(
      CascadedValues.presentationAttributes(of: .circle, attributes: ["x": "10", "fill": "red"]))
    #expect(rect[XProperty.self] != nil)
    #expect(circle[XProperty.self] == nil)
    #expect(circle[FillProperty.self] != nil)
  }
}

private struct SVGLengthContextStub: SVGLengthContext {
  var viewBoxSize: CGSize { .zero }
  var font: SVGUIFont? { nil }
  var textScale: Double { 1 }
  var rootFont: SVGUIFont? { nil }
  var viewPort: CGRect { .zero }
  var writingMode: WritingMode? { nil }
}
