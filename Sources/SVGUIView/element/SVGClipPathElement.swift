import CoreGraphics
import Foundation

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
  let clipPath: SVGClipPath?
  let id: String?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children

    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    clipPathUnits = SVGUnitType(rawValue: attributes["clipPathUnits", default: ""])
    clipPath = base.style.clipPath
    transform = base.style.transform
  }

  func clip(frame: CGRect, context: SVGContext, cgContext: CGContext) async -> Bool {
    guard let maskImage = await maskImage(frame: frame, context: context) else { return false }
    cgContext.clip(to: frame, mask: maskImage)
    return true
  }

  private func maskImage(frame: CGRect, context: SVGContext) async -> CGImage? {
    let size = frame.size
    let scale = context.scale
    guard let graphics = CGContext.bitmap(size: size, scale: scale, space: CGColorSpaceCreateDeviceRGB()) else { return nil }

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
      if Task.isCancelled { break }
      await Task.yield()
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
      guard let path = await content.toPath(context: context.styled(by: content)) else { continue }
      graphics.saveGState()
      content.transform.map {
        graphics.concatenate($0)
      }

      await content.clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
      graphics.addPath(path)
      graphics.drawPath(using: content.style.clipRule == .evenodd ? .eoFill : .fill)
      graphics.restoreGState()
    }
    await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
    let image = graphics.makeImage()
    graphics.restoreGState()
    return image
  }

  func toPath(context _: SVGContext, frame _: CGRect) -> CGPath {
    fatalError()
  }

  func clip(context: inout SVGBaseContext) {
    if let id = id, context.clipPaths[id] == nil {
      context.setClipPath(id: id, value: self)
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
