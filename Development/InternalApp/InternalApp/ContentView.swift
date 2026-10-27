import SVGTestSuite
import SwiftUI

/// Lists the SVG files of the test suite by folder, and opens one to compare how SVGView and a web view
/// render it.
///
/// The app is also the host of the snapshot tests, so it loads no SVG file and no web view until one is
/// opened.
struct ContentView: View {
  @State private var path = NavigationPath()
  @State private var showingPicker = false

  var body: some View {
    NavigationStack(path: $path) {
      FolderView(folder: .testSuite)
        .navigationDestination(for: Folder.self) { FolderView(folder: $0) }
        .navigationDestination(for: Comparison.self) { ComparisonView(comparison: $0) }
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Open File…") { showingPicker = true }
          }
        }
    }
    .sheet(isPresented: $showingPicker) {
      DocumentPickerView { url in
        path.append(Comparison(documents: [SVGDocument(url: url)], index: 0))
      }
    }
  }
}

/// A folder of the test suite.
struct Folder: Hashable {
  let url: URL
  let title: String

  static var testSuite: Folder {
    Folder(url: TestSuite.bundle.bundleURL, title: "Test Suite")
  }

  /// The folders at the top of the test suite: `w3c` for the tests from other projects, `custom` for the ones
  /// written for SVGUIView, and `benchmark` for the documents that measure playback. The bundle has other files
  /// beside them.
  private static let topLevelFolders = ["w3c", "custom", "benchmark"]

  /// The subfolders and SVG files directly in the folder, sorted by name.
  func contents() -> (folders: [Folder], documents: [SVGDocument]) {
    if url == Self.testSuite.url {
      return (Self.topLevelFolders.map { Folder(url: url.appending(component: $0), title: $0) }, [])
    }
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let folders = sorted.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map { Folder(url: $0, title: $0.lastPathComponent) }
    let documents = sorted.filter { $0.pathExtension == "svg" }
      .map { SVGDocument(url: $0) }
    return (folders, documents)
  }
}

/// An SVG file to compare.
struct SVGDocument: Hashable {
  let url: URL

  var name: String { url.deletingPathExtension().lastPathComponent }
}

/// The SVG files that a comparison can step through, and the one that it shows first.
struct Comparison: Hashable {
  let documents: [SVGDocument]
  let index: Int
}

private struct FolderView: View {
  let folder: Folder
  @State private var contents: (folders: [Folder], documents: [SVGDocument]) = ([], [])

  var body: some View {
    List {
      if !contents.folders.isEmpty {
        Section("Folders") {
          ForEach(contents.folders, id: \.self) { folder in
            NavigationLink(value: folder) {
              Label(folder.title, systemImage: "folder")
            }
          }
        }
      }
      if !contents.documents.isEmpty {
        Section("Files") {
          ForEach(Array(contents.documents.enumerated()), id: \.element) { index, document in
            NavigationLink(value: Comparison(documents: contents.documents, index: index)) {
              Text(document.name)
            }
          }
        }
      }
    }
    .navigationTitle(folder.title)
    .onAppear {
      contents = folder.contents()
    }
  }
}

#Preview {
  ContentView()
}
