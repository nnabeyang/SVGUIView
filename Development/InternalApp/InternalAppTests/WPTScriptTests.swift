import Foundation
import SVGUIView
import Testing
import UIKit

/// Tests of the JavaScriptCore bridge that runs the scripts of the reftests of web-platform-tests.
@MainActor
@Suite
struct WPTScriptTests {
  /// Runs the scripts of a document of 100 × 100 with a rect, and gives the view and the runner.
  private func run(_ content: String, rootAttributes: String = "") async throws -> (SVGUIView, WPTScriptRunner) {
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:h="http://www.w3.org/1999/xhtml" width="100" height="100" \
      \(rootAttributes)>
      <h:script src="/common/reftest-wait.js"/>
      <rect id="r" width="100" height="100" fill="red"/>
      \(content)
      </svg>
      """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".svg")
    try Data(svg.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let scripts = try #require(WPTScripts(url: url))
    let view = try #require(SVGUIView(contentsOf: url))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: renderingPatience, animation: .paused)
    view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let runner = WPTScriptRunner(view: view, url: url)
    await runner.run(scripts, url: url)
    return (view, runner)
  }

  /// The red, green and blue of the middle of the view at its time.
  private func middle(of view: SVGUIView) async throws -> [UInt8] {
    let image = try #require(try await view.takeSnapshot(at: view.currentTime, scale: 1).cgImage)
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: -50, y: -50, width: image.width, height: image.height))
    return Array(pixel[0..<3])
  }

  @Test("the scripts change the document, and it's rendered once the root element no longer waits")
  func changes() async throws {
    let (view, runner) = try await run(
      """
      <script>
        waitForAtLeastOneFrame().then(() => {
          document.getElementById("r").setAttribute("fill", "green");
          takeScreenshot();
        });
      </script>
      """, rootAttributes: #"class="reftest-wait""#)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    #expect(try await middle(of: view) == [0, 128, 0])
    #expect(view.document.rootElement?.classList.contains("reftest-wait") == false)
  }

  @Test("tasks, timers and the callbacks of frames run in the order of a page, with promises between them")
  func order() async throws {
    let (view, runner) = try await run(
      """
      <script>
        const log = [];
        setTimeout(() => log.push("timeout 10"), 10);
        setTimeout(() => log.push("timeout 0"), 0);
        requestAnimationFrame(() => {
          log.push("frame");
          Promise.resolve().then(() => log.push("promise"));
          requestAnimationFrame(() => {
            log.push("next frame");
            document.documentElement.setAttribute("data-log", log.join(","));
            document.documentElement.classList.remove("reftest-wait");
          });
        });
      </script>
      """, rootAttributes: #"class="reftest-wait""#)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    #expect(
      view.document.rootElement?.attribute("data-log") == "timeout 0,frame,promise,timeout 10,next frame")
  }

  @Test("an element is the same object however it's found, and the load events run the onload attributes")
  func identityAndLoad() async throws {
    let (view, runner) = try await run(
      """
      <script><![CDATA[
        function loaded() {
          const same = document.getElementById("r") === document.querySelector("rect")
            && document.documentElement.querySelector("#r") === document.getElementsByTagName("rect")[0];
          document.documentElement.setAttribute("data-same", String(same));
        }
      ]]></script>
      """, rootAttributes: #"onload="loaded()""#)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    #expect(view.document.rootElement?.attribute("data-same") == "true")
  }

  @Test("attributes in namespaces, classes and inline styles go through the API of the document")
  func attributesAndStyles() async throws {
    let (view, runner) = try await run(
      """
      <script>
        const rect = document.getElementById("r");
        rect.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:title", "a");
        rect.classList.add("one", "two");
        rect.classList.toggle("one");
        rect.style.fillOpacity = "0.5";
        rect.style.setProperty("fill", "green", "important");
      </script>
      """)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    let rect = try #require(view.document.element(id: "r"))
    #expect(rect.attribute("xlink:title") == "a")
    #expect(rect.classList.names == ["two"])
    #expect(rect.style.property("fill-opacity") == "0.5")
    #expect(rect.style.priority("fill") == .important)
  }

  @Test("getComputedStyle reads the computed values of an element, from its style sheets and presentation attributes")
  func computedStyle() async throws {
    let (view, runner) = try await run(
      """
      <style>#r { stroke-width: 2 }</style>
      <script>
        const style = getComputedStyle(document.getElementById("r"));
        document.documentElement.setAttribute("data-values", [style.fill, style.getPropertyValue("stroke-width"), style.strokeOpacity].join(" "));
      </script>
      """)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    #expect(view.document.rootElement?.attribute("data-values") == "rgb(255, 0, 0) 2px 1")
  }

  @Test("setCurrentTime moves the time of the animations, which beginElement begins at")
  func time() async throws {
    let (view, runner) = try await run(
      """
      <animate id="a" href="#r" attributeName="fill" to="green" dur="1s" begin="indefinite" fill="freeze"/>
      <script>
        document.documentElement.pauseAnimations();
        document.getElementById("a").beginElement();
        document.documentElement.setCurrentTime(2);
      </script>
      """)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    #expect(view.currentTime == .seconds(2))
    #expect(try await middle(of: view) == [0, 128, 0])
  }

  @Test("elements are created, inserted, removed and inserted again through the API of the document")
  func treeChanges() async throws {
    let (view, runner) = try await run(
      """
      <g id="layer"/>
      <script><![CDATA[
        const svg = "http://www.w3.org/2000/svg";
        const layer = document.getElementById("layer");
        const green = document.createElementNS(svg, "rect");
        green.setAttribute("id", "green");
        green.setAttribute("width", "100");
        green.setAttribute("height", "100");
        green.setAttribute("fill", "green");
        const circle = document.createElementNS(svg, "svg:circle");
        circle.setAttribute("id", "circle");
        layer.appendChild(green);
        layer.insertBefore(circle, green);
        const root = document.documentElement;
        root.setAttribute("data-order", Array.from(layer.children).map((e) => e.id).join(","));
        let threw = false;
        try {
          document.createElementNS("http://www.w3.org/1999/xhtml", "div");
        } catch (error) {
          threw = true;
        }
        root.setAttribute("data-threw", String(threw));
        requestAnimationFrame(() => {
          green.remove();
          layer.removeChild(circle);
          root.setAttribute("data-removed", String(layer.children.length));
          requestAnimationFrame(() => {
            layer.appendChild(green);
            takeScreenshot();
          });
        });
      ]]></script>
      """, rootAttributes: #"class="reftest-wait""#)
    #expect(runner.errors.isEmpty, "\(runner.errors)")
    let root = try #require(view.document.rootElement)
    #expect(root.attribute("data-order") == "circle,green")
    #expect(root.attribute("data-threw") == "true")
    #expect(root.attribute("data-removed") == "0")
    #expect(try await middle(of: view) == [0, 128, 0])
  }

  @Test("errors of the scripts, and a root element that never stops waiting, are recorded")
  func errors() async throws {
    let (_, thrown) = try await run("<script>notAFunction();</script>")
    #expect(thrown.errors.count == 1 && thrown.errors[0].contains("notAFunction"), "\(thrown.errors)")
    let (_, waiting) = try await run("", rootAttributes: #"class="reftest-wait""#)
    #expect(waiting.errors.count == 1 && waiting.errors[0].contains("reftest-wait"), "\(waiting.errors)")
  }
}
