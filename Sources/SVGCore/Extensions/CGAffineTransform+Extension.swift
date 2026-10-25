import CoreGraphics

extension CGAffineTransform {
  package var scale: CGAffineTransform {
    let scaleX = sqrt(pow(a, 2) + pow(c, 2))
    let scaleY = sqrt(pow(b, 2) + pow(d, 2))
    return CGAffineTransform(scaleX: scaleX, y: scaleY)
  }

  var invertedScale: CGAffineTransform {
    let scaleX = sqrt(pow(a, 2) + pow(c, 2))
    let scaleY = sqrt(pow(b, 2) + pow(d, 2))
    return CGAffineTransform(scaleX: 1.0 / scaleX, y: 1.0 / scaleY)
  }

  package var withoutScaling: CGAffineTransform {
    concatenating(invertedScale)
  }
}
