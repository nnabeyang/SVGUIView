@testable import _SelectorParser

struct TestVisitor: SelectorVisitor {
  typealias Impl = DummySelectorImpl
  var seen: [String]

  mutating func visitSimpleSelector(_ s: Component<Impl>) -> Bool {
    var dest = ""
    s.toCSS(to: &dest)
    seen.append(dest)
    return true
  }
}
