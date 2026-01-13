import Accelerate
import UIKit

enum SVGUnitType: String {
  case userSpaceOnUse
  case objectBoundingBox
}

struct SVGPatternElement: SVGDrawableElement {
  var base: SVGBaseElement
  let colorInterpolation: SVGColorInterpolation?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let patternContentUnits: SVGUnitType?
  let patternTransform: CGAffineTransform?
  let preserveAspectRatio: PreserveAspectRatio?
  let viewBox: SVGElementRect?
  let parentId: String?

  var type: SVGElementName {
    .pattern
  }

  var transform: CGAffineTransform {
    .identity
  }

  let contentIds: [Int]
  let patternUnits: SVGUnitType?

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(attributes: [String: String], contentIds: [Int]) {
    base = SVGBaseElement(attributes: attributes)
    colorInterpolation = SVGColorInterpolation(rawValue: attributes["color-interpolation", default: ""])
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(style: base.style[.width], value: attributes["width"])
    height = SVGLength(style: base.style[.height], value: attributes["height"])

    patternTransform = CGAffineTransform(description: attributes["patternTransform", default: ""])
    patternUnits = SVGUnitType(rawValue: attributes["patternUnits", default: ""])
    patternContentUnits = SVGUnitType(rawValue: attributes["patternContentUnits", default: ""])
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    viewBox = Self.parseViewBox(attributes["viewBox"])
    parentId = Self.parseLink(description: attributes["href"])

    self.contentIds = contentIds
  }

  init(other: Self, index _: Int, css _: SVGUIStyle) {
    base = other.base
    colorInterpolation = other.colorInterpolation
    x = other.x
    y = other.y
    width = other.width
    height = other.height
    patternTransform = other.patternTransform
    patternUnits = other.patternUnits
    patternContentUnits = other.patternContentUnits
    preserveAspectRatio = other.preserveAspectRatio
    viewBox = other.viewBox
    parentId = other.parentId
    contentIds = other.contentIds
  }

  init(lhs: Self, rhs: Self) {
    base = rhs.base
    colorInterpolation = lhs.colorInterpolation ?? rhs.colorInterpolation
    x = lhs.x ?? rhs.x
    y = lhs.y ?? rhs.y
    width = lhs.width ?? rhs.width
    height = lhs.height ?? rhs.height
    patternTransform = lhs.patternTransform ?? rhs.patternTransform
    patternUnits = lhs.patternUnits ?? rhs.patternUnits
    patternContentUnits = lhs.patternContentUnits ?? rhs.patternContentUnits
    preserveAspectRatio = lhs.preserveAspectRatio ?? rhs.preserveAspectRatio
    viewBox = lhs.viewBox ?? rhs.viewBox
    parentId = rhs.parentId
    if !rhs.contentIds.isEmpty {
      contentIds = rhs.contentIds
    } else {
      contentIds = lhs.contentIds
    }
  }

  var colorSpace: CGColorSpace {
    let colorIntepolation = colorInterpolation ?? .sRGB
    switch colorIntepolation {
    case .sRGB:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    case .linearRGB:
      return CGColorSpace(name: CGColorSpace.linearSRGB)!
    }
  }

  func toBezierPath(context _: SVGContext) -> UIBezierPath? {
    fatalError()
  }

  static func parseViewBox(_ value: String?) -> SVGElementRect? {
    guard let value = value?.trimmingCharacters(in: .whitespaces) else { return nil }
    let nums = value.components(separatedBy: .whitespaces)
    if nums.count == 4,
      let x = Double(nums[0]),
      let y = Double(nums[1]),
      let width = Double(nums[2]),
      let height = Double(nums[3])
    {
      return SVGElementRect(x: x, y: y, width: width, height: height)
    }
    return nil
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  func size(frame: CGRect, context: SVGContext) -> CGSize {
    let patternUnits = patternUnits ?? .objectBoundingBox
    let width = width?.value(context: context, mode: .width, unitType: patternUnits) ?? 0
    let height = height?.value(context: context, mode: .height, unitType: patternUnits) ?? 0
    switch patternUnits {
    case .userSpaceOnUse:
      return CGSize(width: width, height: height)
    case .objectBoundingBox:
      return CGSize(width: width * frame.width, height: height * frame.height)
    }
  }

  func pattern(path: UIBezierPath, frame: CGRect, context: SVGContext, cgContext: CGContext, mode: DrawMode) async -> Bool {
    if let parentId = parentId,
      let parent = context.patterns[parentId],
      context.check(patternId: parentId)
    {
      let pattern = SVGPatternElement(lhs: self, rhs: parent)
      let result = await pattern.pattern(path: path, frame: frame, context: context, cgContext: cgContext, mode: mode)
      context.remove(patternId: parentId)
      return result
    }
    let transform = patternTransform ?? .identity
    let imageSize = size(frame: frame, context: context).applying(transform.scale)
    guard let tileImage = await tileImage(frame: frame, context: context, size: imageSize, transform: transform, isRoot: mode == .root || mode == .filter(isRoot: true)) else { return false }
    let drawPattern: CGPatternDrawPatternCallback = { info, context in
      guard let info = info else { return }
      let image = Unmanaged<CGImage>.fromOpaque(info).takeUnretainedValue()
      let size = CGSize(width: image.width, height: image.height)
      context.draw(image, in: CGRect(origin: .zero, size: size))
    }
    let releaseInfo: CGPatternReleaseInfoCallback = { info in
      guard let info = info else { return }
      Unmanaged<CGImage>.fromOpaque(info).release()
    }
    var callbacks = CGPatternCallbacks(
      version: 0,
      drawPattern: drawPattern, releaseInfo: releaseInfo
    )
    let x: CGFloat
    let y: CGFloat
    let patternUnits = patternUnits ?? .objectBoundingBox
    switch patternUnits {
    case .userSpaceOnUse:
      x = self.x?.value(context: context, mode: .width, unitType: patternUnits) ?? 0
      y = self.y?.value(context: context, mode: .height, unitType: patternUnits) ?? 0
    case .objectBoundingBox:
      x = (self.x?.value(context: context, mode: .width, unitType: patternUnits) ?? 0) * frame.width + frame.minX
      y = (self.y?.value(context: context, mode: .height, unitType: patternUnits) ?? 0) * frame.height + frame.minY
    }

    let scaleX = imageSize.width / CGFloat(tileImage.width)
    let scaleY = imageSize.height / CGFloat(tileImage.height)
    guard
      let pattern = CGPattern(
        info: Unmanaged.passRetained(tileImage).toOpaque(),
        bounds: CGRect(origin: .zero, size: frame.size),
        matrix: transform.withoutScaling
          .translatedBy(x: x, y: y)
          .scaledBy(x: scaleX, y: scaleY)
          .concatenating(context.graphics.ctm),
        xStep: CGFloat(tileImage.width),
        yStep: CGFloat(tileImage.height),
        tiling: .constantSpacing,
        isColored: true,
        callbacks: &callbacks
      )
    else { return false }
    var alpha: CGFloat = 1
    guard let patternSpace = CGColorSpace(patternBaseSpace: nil) else { return false }

    cgContext.addPath(path.cgPath)
    cgContext.setFillColorSpace(patternSpace)
    cgContext.setFillPattern(pattern, colorComponents: &alpha)
    cgContext.drawPath(using: .fill)
    return true
  }

  private func tileImage(frame: CGRect, context: SVGContext, size: CGSize, transform: CGAffineTransform, isRoot: Bool) async -> CGImage? {
    let scale = await UIScreen.main.scale
    let frameWidth = Int((size.width * scale).rounded(.up))
    let frameHeight = Int((size.height * scale).rounded(.up))
    if frameWidth == 0 || frameHeight == 0 { return nil }
    let bytesPerRow = 4 * frameWidth
    guard
      let graphics = CGContext(
        data: nil,
        width: frameWidth,
        height: frameHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
    else {
      return nil
    }

    let maskContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort, other: context)
    let patternContentUnits: SVGUnitType
    if viewBox != nil {
      patternContentUnits = .userSpaceOnUse
    } else {
      patternContentUnits = self.patternContentUnits ?? .userSpaceOnUse
    }
    maskContext.push(patternContentUnit: patternContentUnits)
    defer {
      maskContext.popPatternContentUnit()
    }
    graphics.concatenate(transform.scaledBy(x: scale, y: scale).scale)
    switch patternContentUnits {
    case .userSpaceOnUse:
      if let viewBox = viewBox?.toCGRect() {
        let transform = getTransform(viewBox: viewBox, size: size)
        graphics.concatenate(transform)
        maskContext.push(viewBox: viewBox)
      } else {
        maskContext.push(viewBox: context.viewBox)
      }

    case .objectBoundingBox:
      maskContext.push(viewBox: frame)
    }
    if isRoot {
      maskContext.pushTagIdStack()
      maskContext.pushClipIdStack()
      maskContext.pushMaskIdStack()
    }
    for index in contentIds {
      guard let content = context.contents[index] as? (any SVGDrawableElement) else { continue }
      if content is SVGGroupElement || content is SVGLineElement {
        continue
      }
      if case .hidden = content.visibility {
        continue
      }
      if let display = content.display, case .none = display {
        continue
      }
      maskContext.saveGState()
      await content.draw(maskContext, index: index, mode: .normal)
      maskContext.restoreGState()
    }
    await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
    if isRoot {
      maskContext.popTagIdStack()
      maskContext.popClipIdStack()
      maskContext.popMaskIdStack()
    }
    guard let image = graphics.makeImage() else { return nil }
    graphics.restoreGState()
    return image
  }

  func draw(_: SVGContext, index _: Int, mode _: DrawMode) async {}

  func style(with _: Stylesheet, at index: Int) -> any SVGElement {
    Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
  }

  func pattern(context: inout SVGBaseContext) {
    if let id = id, context.patterns[id] == nil {
      context.setPattern(id: id, value: self)
    }
  }

  func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
    let preserveAspectRatio = preserveAspectRatio ?? .init(xAlign: .mid, yAlign: .mid, option: .meet)
    return preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
  }
}

extension SVGPatternElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
