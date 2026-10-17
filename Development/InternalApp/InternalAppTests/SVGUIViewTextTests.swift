import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewTextTests {
    @Test(arguments: SVGFile.all(in: "basic", "text", "text"))
    func text(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "font-weight"))
    func fontWeight(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "font-family"))
    func fontFamily(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "font-size"))
    func fontSize(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
