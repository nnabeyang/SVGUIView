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

    @Test(arguments: SVGFile.all(in: "basic", "text", "letter-spacing"))
    func letterSpacing(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "word-spacing"))
    func wordSpacing(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "text-anchor"))
    func textAnchor(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "text-decoration"))
    func textDecoration(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "text-rendering"))
    func textRendering(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "tspan"))
    func tspan(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "baseline-shift"))
    func baselineShift(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "dominant-baseline"))
    func dominantBaseline(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "text", "alignment-baseline"))
    func alignmentBaseline(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
