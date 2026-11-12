import CoreGraphics
import Foundation
import Synchronization
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `setData(_:)` parses SVG data off the main actor and shows only the latest data.
@MainActor
@Suite("Data loading", .serialized)
struct DataLoadingTests {
  /// A document of the given size, from its view box.
  private static func document(width: Int, height: Int) -> Data {
    Data(
      #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(width)" height="\#(height)" viewBox="0 0 \#(width) \#(height)"><rect width="1" height="1"/></svg>"#
        .utf8)
  }

  private func makeView() -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Self.document(width: 10, height: 10))
    view.configuration = SVGUIViewConfiguration(animation: .none)
    return view
  }

  @Test("setData(_:) replaces the data, the document and the size of the view")
  func replacesDocument() async {
    let view = makeView()
    let oldDocument = view.document
    let data = Self.document(width: 30, height: 40)
    await view.setData(data)
    #expect(view.data == data)
    #expect(view.document !== oldDocument)
    #expect(view.intrinsicContentSize == CGSize(width: 30, height: 40))
  }

  @Test("setData(_:) parses the data off the main thread")
  func parsesOffMainThread() async {
    let parsedOnMain = Mutex<[Bool]>([])
    let view = makeView()
    await SVGUIView.$parseObserver.withValue({ parsedOnMain.withLock { $0.append(Thread.isMainThread) } }) {
      await view.setData(Self.document(width: 30, height: 40))
    }
    #expect(parsedOnMain.withLock { $0 } == [false])
  }

  /// Holds the parsing of `setData(_:)` in the tasks that it starts until a test lets it go on, and tells the test
  /// when the parsing starts, so that the test gives other data while the parsing is in progress. The parsing waits
  /// without blocking a thread, also with one thread in the cooperative pool.
  private final class ParseGate: Sendable {
    private let started: AsyncStream<Void>.Continuation
    let starts: AsyncStream<Void>
    private let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])

    init() {
      (starts, started) = AsyncStream.makeStream()
    }

    /// Starts a task whose parsing waits until the gate opens.
    func task(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
      SVGUIView.$parseObserver.withValue({ [self] in
        await withCheckedContinuation { continuation in
          waiting.withLock { $0.append(continuation) }
          started.yield()
        }
      }) {
        Task { await operation() }
      }
    }

    /// Lets the parsings that wait go on.
    func open() {
      for continuation in waiting.withLock({ list in
        defer { list = [] }
        return list
      }) {
        continuation.resume()
      }
    }
  }

  @Test("only the data given last is shown, by setData(_:) or by setting data")
  func showsLatestData() async {
    let view = makeView()
    let first = Self.document(width: 30, height: 30)
    let second = Self.document(width: 40, height: 40)
    var gate = ParseGate()
    var starts = gate.starts.makeAsyncIterator()
    let firstLoad = gate.task { await view.setData(first) }
    await starts.next()
    let secondLoad = gate.task { await view.setData(second) }
    await starts.next()
    gate.open()
    await firstLoad.value
    await secondLoad.value
    #expect(view.data == second)

    // Setting data while setData(_:) parses replaces the data that it parses.
    let latest = Self.document(width: 50, height: 50)
    gate = ParseGate()
    starts = gate.starts.makeAsyncIterator()
    let load = gate.task { await view.setData(Self.document(width: 60, height: 60)) }
    await starts.next()
    view.data = latest
    gate.open()
    await load.value
    #expect(view.data == latest)
    #expect(view.intrinsicContentSize == CGSize(width: 50, height: 50))
  }

  @Test("the data of a canceled setData(_:) isn't shown")
  func canceledLoad() async {
    let view = makeView()
    let data = view.data
    let load = Task { await view.setData(Self.document(width: 30, height: 30)) }
    load.cancel()
    await load.value
    #expect(view.data == data)
  }

  @Test("setData(_:) with the data that the view displays keeps its document")
  func sameData() async {
    let view = makeView()
    let document = view.document
    await view.setData(view.data)
    #expect(view.document === document)
  }
}
