import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewStructureTests {
    @Test(arguments: SVGFile.all(in: "basic", "structure", "a"))
    func a(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "defs"))
    func defs(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "g"))
    func g(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "image"))
    func image(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "style"))
    func style(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "style-attribute"))
    func styleAttribute(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "svg"))
    func svg(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "switch"))
    func `switch`(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "symbol"))
    func symbol(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "systemLanguage"))
    func systemLanguage(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "transform"))
    func transform(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "structure", "use"))
    func use(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
