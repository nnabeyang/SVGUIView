import Testing

extension SnapshotTests {
  /// The SVG reftests of web-platform-tests, which compare the renderings of two documents instead of a rendering
  /// and a reference image, by the folders of web-platform-tests.
  @MainActor
  @Suite
  struct SVGUIViewWPTTests {
    @Test(arguments: Reftest.all(in: "svg", "coordinate-systems"))
    func coordinateSystems(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "embedded"))
    func embedded(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "fonts"))
    func fonts(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "geometry"))
    func geometry(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "linking"))
    func linking(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "painting"))
    func painting(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "path"))
    func path(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "pservers"))
    func pservers(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "render"))
    func render(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "shapes"))
    func shapes(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "struct"))
    func structure(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "styling"))
    func styling(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "svg", "text"))
    func text(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "css", "css-masking"))
    func cssMasking(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }

    @Test(arguments: Reftest.all(in: "css", "filter-effects"))
    func filterEffects(_ test: Reftest) async throws {
      try await assertSVGReftest(test)
    }
  }

  /// Tests that reftests are read and compared as web-platform-tests reads and compares them.
  @Suite
  struct ReftestTests {
    @Test(
      "the content of fuzzy is read with and without names and for one reference",
      arguments: [
        ("0-1;0-11", nil, Reftest.Range(lowerBound: 0, upperBound: 1), Reftest.Range(lowerBound: 0, upperBound: 11)),
        (
          "maxDifference=0-127; totalPixels=0-1220", nil, Reftest.Range(lowerBound: 0, upperBound: 127),
          Reftest.Range(lowerBound: 0, upperBound: 1220)
        ),
        (
          "option-ref.svg:10-15;200-300", "option-ref.svg", Reftest.Range(lowerBound: 10, upperBound: 15),
          Reftest.Range(lowerBound: 200, upperBound: 300)
        ),
        ("15;300", nil, Reftest.Range(lowerBound: 15, upperBound: 15), Reftest.Range(lowerBound: 300, upperBound: 300)),
      ] as [(String, String?, Reftest.Range, Reftest.Range)])
    func fuzzy(content: String, reference: String?, maxDifference: Reftest.Range, totalPixels: Reftest.Range) throws {
      let (parsedReference, fuzziness) = try #require(Reftest.parseFuzzy(content))
      #expect(parsedReference == reference)
      #expect(fuzziness == Reftest.Fuzziness(maxDifference: maxDifference, totalPixels: totalPixels))
    }

    @Test("differences are within a fuzziness as wptrunner decides it")
    func withinFuzziness() {
      let fuzziness = Reftest.Fuzziness(
        maxDifference: .init(lowerBound: 10, upperBound: 15), totalPixels: .init(lowerBound: 200, upperBound: 300))
      #expect(ImageDifference(maxDifference: 0, totalPixels: 0).isWithin(nil))
      #expect(!ImageDifference(maxDifference: 1, totalPixels: 1).isWithin(nil))
      #expect(ImageDifference(maxDifference: 12, totalPixels: 250).isWithin(fuzziness))
      #expect(!ImageDifference(maxDifference: 16, totalPixels: 250).isWithin(fuzziness))
      #expect(!ImageDifference(maxDifference: 12, totalPixels: 100).isWithin(fuzziness))
      // A range that starts at 0 allows no difference of that kind at all.
      let fromZero = Reftest.Fuzziness(
        maxDifference: .init(lowerBound: 0, upperBound: 2), totalPixels: .init(lowerBound: 0, upperBound: 10))
      #expect(ImageDifference(maxDifference: 0, totalPixels: 0).isWithin(fromZero))
      #expect(ImageDifference(maxDifference: 2, totalPixels: 10).isWithin(fromZero))
    }
  }
}
