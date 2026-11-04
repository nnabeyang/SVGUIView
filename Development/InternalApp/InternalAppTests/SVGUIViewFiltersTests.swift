import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewFiltersTests {
    @Test(arguments: SVGFile.all(in: "basic", "filters", "color-interpolation-filters"))
    func colorInterpolationFilters(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feBlend"))
    func feBlend(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feColorMatrix"))
    func feColorMatrix(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feComponentTransfer"))
    func feComponentTransfer(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feComposite"))
    func feComposite(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feConvolveMatrix"))
    func feConvolveMatrix(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feDiffuseLighting"))
    func feDiffuseLighting(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feDisplacementMap"))
    func feDisplacementMap(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feDropShadow"))
    func feDropShadow(_ file: SVGFile) async throws {
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

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feImage"))
    func feImage(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feMerge"))
    func feMerge(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feMorphology"))
    func feMorphology(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feOffset"))
    func feOffset(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feTile"))
    func feTile(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "filters", "feTurbulence"))
    func feTurbulence(_ file: SVGFile) async throws {
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
