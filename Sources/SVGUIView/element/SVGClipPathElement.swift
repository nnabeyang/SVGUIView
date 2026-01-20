import UIKit

final class SVGClipPathElement: SVGElement {
  static var type: SVGElementName {
    .clipPath
  }

  var type: SVGElementName {
    .clipPath
  }

  let base: SVGBaseElement
  let children: [any SVGElement]
  let transform: CGAffineTransform?
  let clipPathUnits: SVGUnitType?
  let clipRule: Bool?
  let clipPath: SVGClipPath?
  let id: String?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children

    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    clipPathUnits = SVGUnitType(rawValue: attributes["clipPathUnits", default: ""])
    clipRule = attributes["clip-rule"].map { $0.trimmingCharacters(in: .whitespaces) == "evenodd" }
    clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
    transform = CGAffineTransform(description: attributes["transform", default: ""])
  }

  init(other: SVGClipPathElement, css _: SVGUIStyle) {
    id = other.id
    base = other.base
    clipPathUnits = other.clipPathUnits
    clipRule = other.clipRule
    clipPath = other.clipPath
    transform = other.transform
    children = other.children
  }

  init(other: SVGClipPathElement, clipRule: Bool?) {
    id = other.id
    base = other.base
    clipPathUnits = other.clipPathUnits
    self.clipRule = other.clipRule ?? clipRule
    clipPath = other.clipPath
    children = other.children
    transform = other.transform
  }

  func clip(frame: CGRect, context: SVGContext, cgContext: CGContext) async -> Bool {
    guard let maskImage = await maskImage(frame: frame, context: context) else { return false }
    cgContext.clip(to: frame, mask: maskImage)
    return true
  }

  private func maskImage(frame: CGRect, context: SVGContext) async -> CGImage? {
    let size = frame.size
    let scale = await UIScreen.main.scale
    let frameWidth = Int((size.width * scale).rounded(.up))
    let frameHeight = Int((size.height * scale).rounded(.up))
    let bytesPerRow = 4 * frameWidth
    guard
      let graphics = CGContext(
        data: nil,
        width: frameWidth,
        height: frameHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
    else {
      return nil
    }

    let transform: CGAffineTransform
    let clipPathUnits = clipPathUnits ?? .userSpaceOnUse
    let t = (self.transform ?? .identity).concatenating(CGAffineTransform(scaleX: scale, y: scale))

    switch clipPathUnits {
    case .userSpaceOnUse:
      transform =
        t
        .translatedBy(x: -frame.minX, y: -frame.minY)
    case .objectBoundingBox:
      transform =
        t
        .scaledBy(x: size.width, y: size.height)
    }

    graphics.concatenate(transform)
    for content in children {
      guard let content = content as? (any SVGDrawableElement) else { continue }
      if content is SVGGroupElement || content is SVGLineElement || content is SVGImageElement {
        continue
      }
      if case .hidden = content.visibility {
        continue
      }
      if let display = content.display, case .none = display {
        continue
      }
      content.font.map {
        context.push(font: $0)
      }
      guard let bezierPath = await content.toBezierPath(context: context) else { continue }
      content.font.map { _ in
        _ = context.popFont()
      }
      graphics.saveGState()
      content.transform.map {
        graphics.concatenate($0)
      }

      await content.clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
      let clipRule = content.clipRule ?? clipRule ?? false
      graphics.addPath(bezierPath.cgPath)
      graphics.drawPath(using: clipRule ? .eoFill : .fill)
      graphics.restoreGState()
    }
    await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
    let image = graphics.makeImage()
    graphics.restoreGState()
    return image
  }

  func toBezierPath(context _: SVGContext, frame _: CGRect) -> UIBezierPath {
    fatalError()
  }

  func style(with _: Stylesheet) -> any SVGElement {
    Self(other: self, css: SVGUIStyle(decratations: [:]))
  }

  func clip(context: inout SVGBaseContext) {
    if let id = id, context.clipPaths[id] == nil {
      context.setClipPath(id: id, value: .init(other: self, clipRule: context.clipRule))
    }
  }
}

extension SVGClipPathElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
