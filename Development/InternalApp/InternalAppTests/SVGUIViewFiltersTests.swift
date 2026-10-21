import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewFiltersTests {
    @Test(arguments: SVGFile.all(in: "basic", "filters", "feBlend"))
    func feBlend(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feFlood"))
    func feFlood(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feGaussianBlur"))
    func feGaussianBlur(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feMerge"))
    func feMerge(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feOffset"))
    func feOffset(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "filter"))
    func filter(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "flood-color"))
    func floodColor(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "flood-opacity"))
    func floodOpacity(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
