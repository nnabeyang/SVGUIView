import SVGUIView
import SVGView
import SwiftUI
import Testing
import UIKit

@MainActor
@Suite("SVGView")
struct SVGViewTests {
  /// A document whose size is 200 × 200 points, from its view box.
  private static let document = Data(
    #"<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg"><rect width="200" height="200"/></svg>"#.utf8)

  /// Lays out a SwiftUI view in a window and returns the size of the SVGUIView in it. SwiftUI makes the views
  /// of a representable only in a window.
  private func sizeOfSVGUIView(in rootView: some View) throws -> CGSize {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    window.rootViewController = UIHostingController(rootView: rootView)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    window.layoutIfNeeded()
    return try #require(Self.svgUIView(in: window)).bounds.size
  }

  private static func svgUIView(in view: UIView) -> SVGUIView? {
    if let view = view as? SVGUIView { return view }
    return view.subviews.lazy.compactMap(svgUIView(in:)).first
  }

  @Test("a view takes the size of a frame smaller or larger than its document", arguments: [CGFloat(80), 150, 300])
  func takesFrameSize(side: CGFloat) throws {
    let size = try sizeOfSVGUIView(in: SVGView(data: Self.document).frame(width: side, height: side))
    #expect(size == CGSize(width: side, height: side))
  }

  @Test("a view without a proposed size takes the size of its document")
  func takesDocumentSizeWithoutProposal() throws {
    let size = try sizeOfSVGUIView(in: SVGView(data: Self.document).fixedSize())
    #expect(size == CGSize(width: 200, height: 200))
  }
}
