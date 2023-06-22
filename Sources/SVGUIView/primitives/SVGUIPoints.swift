import UIKit
struct SVGUIPoints: Encodable {
    let points: [CGPoint]

    init(description: String) {
        var data = description
        let points = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanPoints()
        }
        self.points = points
    }

    var polygon: UIBezierPath? {
        guard let path = polyline else { return nil }
        path.close()
        return path
    }

    var polyline: UIBezierPath? {
        guard points.count >= 2, let first = points.first else { return nil }
        let path = UIBezierPath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
