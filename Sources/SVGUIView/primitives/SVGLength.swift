import CoreText
import Foundation

enum SVGLengthType: String {
  case unknown
  case number
  case percentage = "%"
  case ems = "em"
  case rems = "rem"
  case exs = "ex"
  case pixels = "px"
  case centimeters = "cm"
  case millimeters = "mm"
  case inches = "in"
  case points = "pt"
  case picas = "pc"
  case chs = "ch"
  case ic
  case lhs = "lh"
  case rlhs = "rlh"
  case vw
  case vh
  case vi
  case vb
  case vmin
  case vmax
  case q = "Q"
}

enum SVGLengthMode {
  case width
  case height
  case other
}

enum SVGLength: Equatable {
  case number(CGFloat)
  case pixel(CGFloat)
  case percent(CGFloat)
  case ems(CGFloat)
  case rems(CGFloat)
  case exs(CGFloat)
  case centimeters(CGFloat)
  case millimeters(CGFloat)
  case inches(CGFloat)
  case points(CGFloat)
  case picas(CGFloat)
  case chs(CGFloat)
  case ic(CGFloat)
  case lhs(CGFloat)
  case rlhs(CGFloat)
  case vw(CGFloat)
  case vh(CGFloat)
  case vi(CGFloat)
  case vb(CGFloat)
  case vmin(CGFloat)
  case vmax(CGFloat)
  case q(CGFloat)

  static let pixelsPerInch: CGFloat = 96.0
  static var zeroCodePoint: UniChar {
    get { 0x30 }
    set {}
  }

  init(value: Double, unit: CSSUnitType) {
    switch unit {
    case .px:
      self = .pixel(value)
    case .percentage:
      self = .percent(value)
    case .ems:
      self = .ems(value)
    case .exs:
      self = .exs(value)
    case .mm:
      self = .millimeters(value)
    case .chs:
      self = .chs(value)
    case .ic:
      self = .ic(value)
    case .rems:
      self = .rems(value)
    case .lhs:
      self = .lhs(value)
    case .rlhs:
      self = .rlhs(value)
    default:
      self = .pixel(value)
    }
  }

  init(child: SVGLength, parent: SVGLength) {
    switch child {
    case .percent(let percent):
      switch parent {
      case .number(let value):
        self = .number(value * percent / 100.0)
      case .pixel(let value):
        self = .number(value * percent / 100.0)
      case .percent(let value):
        self = .percent(value * percent / 100.0)
      case .ems(let value):
        self = .number(value * percent / 100.0)
      case .rems(let value):
        self = .number(value * percent / 100.0)
      case .exs(let value):
        self = .number(value * percent / 100.0)
      case .centimeters(let value):
        self = .number(value * percent / 100.0)
      case .millimeters(let value):
        self = .number(value * percent / 100.0)
      case .inches(let value):
        self = .number(value * percent / 100.0)
      case .points(let value):
        self = .number(value * percent / 100.0)
      case .picas(let value):
        self = .number(value * percent / 100.0)
      case .chs(let value):
        self = .number(value * percent / 100.0)
      case .ic(let value):
        self = .number(value * percent / 100.0)
      case .lhs(let value):
        self = .number(value * percent / 100.0)
      case .rlhs(let value):
        self = .number(value * percent / 100.0)
      case .vw(let value):
        self = .number(value * percent / 100.0)
      case .vh(let value):
        self = .number(value * percent / 100.0)
      case .vi(let value):
        self = .number(value * percent / 100.0)
      case .vb(let value):
        self = .number(value * percent / 100.0)
      case .vmin(let value):
        self = .number(value * percent / 100.0)
      case .vmax(let value):
        self = .number(value * percent / 100.0)
      case .q(let value):
        self = .number(value * percent / 100.0)
      }
    default:
      self = child
    }
  }

  init?(_ description: String?) {
    guard var data = description?.trimmingCharacters(in: .whitespaces) else {
      return nil
    }
    let v: SVGLength? = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      guard let value = scanner.scanNumber() else { return nil }
      let lengthType = scanner.scanLengthType()
      switch lengthType {
      case .unknown:
        return nil
      case .percentage:
        return .percent(value)
      case .ems:
        return .ems(value)
      case .rems:
        return .rems(value)
      case .exs:
        return .exs(value)
      case .centimeters:
        return .centimeters(value)
      case .millimeters:
        return .millimeters(value)
      case .inches:
        return .inches(value)
      case .points:
        return .points(value)
      case .picas:
        return .picas(value)
      case .chs:
        return .chs(value)
      case .ic:
        return .ic(value)
      case .lhs:
        return .lhs(value)
      case .rlhs:
        return .rlhs(value)
      case .vw:
        return .vw(value)
      case .vh:
        return .vh(value)
      case .vi:
        return .vi(value)
      case .vb:
        return .vb(value)
      case .vmin:
        return .vmin(value)
      case .vmax:
        return .vmax(value)
      case .q:
        return .q(value)
      case .pixels:
        return .pixel(value)
      case .number:
        return .number(value)
      }
    }

    if let v = v {
      self = v
      return
    }
    return nil
  }

  init?(style: CSSValue?, value: String?) {
    if case .length(let length) = style {
      self = length
      return
    }
    guard var data = value?.trimmingCharacters(in: .whitespaces) else {
      return nil
    }
    let v: SVGLength? = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      guard let value = scanner.scanNumber() else { return nil }
      let lengthType = scanner.scanLengthType()
      switch lengthType {
      case .unknown:
        return nil
      case .percentage:
        return .percent(value)
      case .ems:
        return .ems(value)
      case .rems:
        return .rems(value)
      case .exs:
        return .exs(value)
      case .pixels, .number:
        return .pixel(value)
      case .centimeters:
        return .centimeters(value)
      case .millimeters:
        return .millimeters(value)
      case .inches:
        return .inches(value)
      case .points:
        return .picas(value)
      case .picas:
        return .picas(value)
      case .chs:
        return .chs(value)
      case .ic:
        return .ic(value)
      case .lhs:
        return .lhs(value)
      case .rlhs:
        return .rlhs(value)
      case .vw:
        return .vw(value)
      case .vh:
        return .vh(value)
      case .vi:
        return .vi(value)
      case .vb:
        return .vb(value)
      case .vmin:
        return .vmin(value)
      case .vmax:
        return .vmax(value)
      case .q:
        return .q(value)
      }
    }

    if let v = v {
      self = v
      return
    }
    return nil
  }

  func calculatedLength(frame: CGRect, context: any SVGLengthContext, mode: SVGLengthMode, unitType: SVGUnitType = .userSpaceOnUse, isPosition: Bool = false) -> CGFloat {
    let value = value(context: context, mode: mode, unitType: unitType)
    let viewBoxSize = context.viewBoxSize
    switch mode {
    case .height:
      let dy: CGFloat
      switch unitType {
      case .userSpaceOnUse:
        return min(value, 1.2 * viewBoxSize.height)
      case .objectBoundingBox:
        dy = frame.height * value
        return isPosition ? frame.minY + dy : dy
      }
    case .width:
      let dx: CGFloat
      switch unitType {
      case .userSpaceOnUse:
        return min(value, 1.2 * viewBoxSize.width)
      case .objectBoundingBox:
        dx = frame.width * value
        return isPosition ? frame.minX + dx : dx
      }
    case .other:
      let c = sqrt(pow(viewBoxSize.width, 2) + pow(viewBoxSize.height, 2)) / sqrt(2)
      switch unitType {
      case .userSpaceOnUse:
        return min(value, 1.2 * c)
      case .objectBoundingBox:
        return c * value
      }
    }
  }

  func value(context: any SVGLengthContext, mode: SVGLengthMode, unitType: SVGUnitType = .userSpaceOnUse) -> CGFloat {
    let total: CGFloat
    if case .percent = self {
      let size: CGSize
      switch unitType {
      case .userSpaceOnUse:
        size = context.viewBoxSize
      case .objectBoundingBox:
        size = CGSize(width: 1, height: 1)
      }
      switch mode {
      case .height:
        total = size.height
      case .width:
        total = size.width
      case .other:
        let h = size.height
        let w = size.width
        total = sqrt(pow(w, 2) + pow(h, 2)) / sqrt(2)
      }
    } else {
      total = 0
    }
    return value(total: total, context: context)
  }

  func fontValue(context: any SVGLengthContext) -> CGFloat {
    let total: CGFloat
    if case .percent = self {
      total = context.font?.sizeValue(context: context, textScale: 1.0) ?? 16.0
    } else {
      total = 0
    }
    return value(total: total, context: context)
  }

  func value(total: CGFloat, context: any SVGLengthContext) -> CGFloat {
    switch self {
    case .percent(let percent):
      return total * percent / 100.0
    case .pixel(let pixel), .number(let pixel):
      return pixel
    case .ems(let value):
      guard let font = context.font else { return 0 }
      switch font.size {
      case .length(.ems(let value)):
        let fontSize = SVGUIFont.Size.defaultFontSize
        return Self.ems(value: value, fontSize: fontSize)
      default:
        let fontSize = font.sizeValue(context: context)
        return Self.ems(value: value, fontSize: fontSize)
      }
    case .rems(let value):
      guard let font = context.rootFont else { return 0 }
      switch font.size {
      case .length(.rems(let value)):
        let fontSize = SVGUIFont.Size.defaultFontSize
        return Self.ems(value: value, fontSize: fontSize)
      default:
        let fontSize = font.sizeValue(context: context)
        return Self.ems(value: value, fontSize: fontSize)
      }
    case .exs(let value):
      guard let font = context.font else {
        return 0
      }
      switch font.size {
      case .length(.exs(value)):
        let ctFont = CTFont.standard(context: context)
        return Self.exs(value: value, ctFont: ctFont)
      default:
        let ctFont = font.ctFont(context: context)
        return Self.exs(value: value, ctFont: ctFont)
      }
    case .centimeters(let value):
      return value * Self.pixelsPerInch / 2.54
    case .millimeters(let value):
      return value * Self.pixelsPerInch / 25.4
    case .inches(let value):
      return value * Self.pixelsPerInch
    case .points(let value):
      return value * Self.pixelsPerInch / 72.0
    case .picas(let value):
      return value * Self.pixelsPerInch / 6.0
    case .chs(let value):
      guard let font = context.font else { return 0 }
      switch font.size {
      case .length(.chs(value)):
        let ctFont = CTFont.standard(context: context)
        return Self.chs(value: value, ctFont: ctFont)
      default:
        return Self.chs(value: value, ctFont: font.ctFont(context: context))
      }
    case .ic(let value):
      guard let font = context.font else { return 0 }
      switch font.size {
      case .length(.ic(value)):
        let ctFont = CTFont.standard(context: context)
        return Self.ic(value: value, ctFont: ctFont)
      default:
        return Self.ic(value: value, ctFont: font.ctFont(context: context))
      }
    case .lhs(let value):
      guard let font = context.font else { return 0 }
      switch font.size {
      case .length(.lhs(value)):
        let ctFont = CTFont.standard(context: context)
        return Self.lhs(value: value, ctFont: ctFont)
      default:
        let ctFont = font.ctFont(context: context)
        return Self.lhs(value: value, ctFont: ctFont)
      }
    case .rlhs(let value):
      guard let font = context.rootFont else { return 0 }
      switch font.size {
      case .length(.lhs(value)):
        let ctFont = CTFont.standard(context: context)
        return Self.lhs(value: value, ctFont: ctFont)
      default:
        let ctFont = font.ctFont(context: context)
        return Self.lhs(value: value, ctFont: ctFont)
      }
    case .vw(let value):
      return value * context.viewPort.width / 100.0
    case .vh(let value):
      return value * context.viewPort.height / 100.0
    case .vi(let value):
      let viewPort = context.viewPort
      let writingMode = context.writingMode ?? .horizontalTB
      let scale: CGFloat
      switch writingMode {
      case .horizontalTB:
        scale = viewPort.width / 100.0
      case .verticalLR, .verticalRL:
        scale = viewPort.height / 100.0
      }
      return value * scale
    case .vb(let value):
      let viewPort = context.viewPort
      let writingMode = context.writingMode ?? .horizontalTB
      let scale: CGFloat
      switch writingMode {
      case .horizontalTB:
        scale = viewPort.height / 100.0
      case .verticalLR, .verticalRL:
        scale = viewPort.width / 100.0
      }
      return value * scale
    case .vmin(let value):
      return value * min(context.viewPort.width, context.viewPort.height) / 100.0
    case .vmax(let value):
      return value * max(context.viewPort.width, context.viewPort.height) / 100.0
    case .q(let value):
      return value * Self.pixelsPerInch / (25.4 * 4.0)
    }
  }

  private static func ems(value: CGFloat, fontSize: CGFloat) -> CGFloat {
    value * fontSize
  }

  private static func exs(value: CGFloat, ctFont: CTFont) -> CGFloat {
    let xHeight = CTFontGetXHeight(ctFont)
    return value * xHeight
  }

  private static func chs(value: CGFloat, ctFont: CTFont) -> CGFloat {
    var glyph = CGGlyph()
    CTFontGetGlyphsForCharacters(ctFont, &Self.zeroCodePoint, &glyph, 1)
    var advance: CGSize = .zero
    CTFontGetAdvancesForGlyphs(ctFont, CTFontOrientation.default, &glyph, &advance, 1)
    let width = advance == .zero ? CTFontGetSize(ctFont) / 2.0 : advance.width
    return value * width
  }

  private static func ic(value: CGFloat, ctFont: CTFont) -> CGFloat {
    value * CTFontGetSize(ctFont)
  }

  private static func lhs(value: CGFloat, ctFont: CTFont) -> CGFloat {
    let ascent = CTFontGetAscent(ctFont)
    let lineGap = CTFontGetLeading(ctFont)
    let descent = CTFontGetDescent(ctFont)
    let lineSpacing = (ceil(ascent) + ceil(lineGap) + ceil(descent))
    return value * lineSpacing
  }
}

extension SVGLength: CustomStringConvertible {
  var description: String {
    switch self {
    case .number(let value): return "\(value)"
    case .pixel(let value): return "\(value)px"
    case .percent(let value): return "\(value)%"
    case .ems(let value): return "\(value)em"
    case .rems(let value): return "\(value)rem"
    case .exs(let value): return "\(value)ex"
    case .centimeters(let value): return "\(value)cm"
    case .millimeters(let value): return "\(value)mm"
    case .inches(let value): return "\(value)in"
    case .points(let value): return "\(value)pt"
    case .picas(let value): return "\(value)pc"
    case .chs(let value): return "\(value)ch"
    case .ic(let value): return "\(value)ic"
    case .lhs(let value): return "\(value)lh"
    case .rlhs(let value): return "\(value)rlh"
    case .vw(let value): return "\(value)vw"
    case .vh(let value): return "\(value)vh"
    case .vi(let value): return "\(value)vi"
    case .vb(let value): return "\(value)vb"
    case .vmin(let value): return "\(value)vmin"
    case .vmax(let value): return "\(value)vmax"
    case .q(let value): return "\(value)Q"
    }
  }
}

extension SVGLength: Codable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    switch self {
    case .number(let v):
      try container.encode(SVGLengthType.number.rawValue)
      try container.encode(v)
    case .pixel(let v):
      try container.encode(SVGLengthType.pixels.rawValue)
      try container.encode(v)
    case .percent(let v):
      try container.encode(SVGLengthType.percentage.rawValue)
      try container.encode(v)
    case .ems(let v):
      try container.encode(SVGLengthType.ems.rawValue)
      try container.encode(v)
    case .rems(let v):
      try container.encode(SVGLengthType.rems.rawValue)
      try container.encode(v)
    case .exs(let v):
      try container.encode(SVGLengthType.exs.rawValue)
      try container.encode(v)
    case .centimeters(let v):
      try container.encode(SVGLengthType.centimeters.rawValue)
      try container.encode(v)
    case .millimeters(let v):
      try container.encode(SVGLengthType.millimeters.rawValue)
      try container.encode(v)
    case .inches(let v):
      try container.encode(SVGLengthType.inches.rawValue)
      try container.encode(v)
    case .points(let v):
      try container.encode(SVGLengthType.points.rawValue)
      try container.encode(v)
    case .picas(let v):
      try container.encode(SVGLengthType.picas.rawValue)
      try container.encode(v)
    case .chs(let v):
      try container.encode(SVGLengthType.chs.rawValue)
      try container.encode(v)
    case .ic(let v):
      try container.encode(SVGLengthType.ic.rawValue)
      try container.encode(v)
    case .lhs(let v):
      try container.encode(SVGLengthType.lhs.rawValue)
      try container.encode(v)
    case .rlhs(let v):
      try container.encode(SVGLengthType.rlhs.rawValue)
      try container.encode(v)
    case .vw(let v):
      try container.encode(SVGLengthType.vw.rawValue)
      try container.encode(v)
    case .vh(let v):
      try container.encode(SVGLengthType.vh.rawValue)
      try container.encode(v)
    case .vi(let v):
      try container.encode(SVGLengthType.vi.rawValue)
      try container.encode(v)
    case .vb(let v):
      try container.encode(SVGLengthType.vb.rawValue)
      try container.encode(v)
    case .vmin(let v):
      try container.encode(SVGLengthType.vmin.rawValue)
      try container.encode(v)
    case .vmax(let v):
      try container.encode(SVGLengthType.vmax.rawValue)
      try container.encode(v)
    case .q(let v):
      try container.encode(SVGLengthType.q.rawValue)
      try container.encode(v)
    }
  }

  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let typeString = try container.decode(String.self)
    guard let type = SVGLengthType(rawValue: typeString) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
    }
    let value = try container.decode(Double.self)
    switch type {
    case .number:
      self = .number(value)
    case .pixels:
      self = .pixel(value)
    case .percentage:
      self = .percent(value)
    case .ems:
      self = .ems(value)
    case .rems:
      self = .rems(value)
    case .exs:
      self = .ems(value)
    case .centimeters:
      self = .centimeters(value)
    case .millimeters:
      self = .millimeters(value)
    case .inches:
      self = .inches(value)
    case .points:
      self = .points(value)
    case .picas:
      self = .picas(value)
    case .chs:
      self = .chs(value)
    case .ic:
      self = .ic(value)
    case .lhs:
      self = .lhs(value)
    case .rlhs:
      self = .rlhs(value)
    case .vw:
      self = .vw(value)
    case .vh:
      self = .vh(value)
    case .vi:
      self = .vi(value)
    case .vb:
      self = .vb(value)
    case .vmin:
      self = .vmin(value)
    case .vmax:
      self = .vmax(value)
    case .q:
      self = .q(value)
    case .unknown:
      self = .pixel(0)
    }
  }
}
