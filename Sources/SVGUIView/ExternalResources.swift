import Foundation

/// The files outside a document that a view reads for it, such as the image
/// files of `<image>` elements.
///
/// A document refers to other files by URLs relative to its own URL, which
/// is the view's ``SVGUIView/baseURL``. By default, a view reads only files:
/// it doesn't read the network, unless the setting allows it with
/// ``allowingNetwork()``. A document that the view has no base URL for, such
/// as one that's set as ``SVGUIView/data``, reads no files.
///
/// A file is read only if it's in the folder that the setting allows, after
/// `..` and symbolic links in its path are resolved, so that a document can't
/// read files outside the folder. By default, a view reads the files in the
/// folder of the document and in the folders inside it.
///
/// ```swift
/// // Read the images of a document from anywhere in the app's bundle.
/// svgView.configuration = SVGUIViewConfiguration(
///   externalResources: .folder(Bundle.main.bundleURL)
/// )
/// ```
public struct ExternalResources: Sendable, Equatable {
  /// The folders that a view reads files in.
  enum Files: Sendable, Equatable {
    case none
    case documentFolder
    case folder(URL)
  }

  let files: Files
  /// Whether the resources at `https` URLs are read.
  let network: Bool

  init(files: Files, network: Bool = false) {
    self.files = files
    self.network = network
  }

  /// The files in the folder of the document, and in the folders inside it.
  ///
  /// This is the default. A relative URL that leads out of the folder, such
  /// as `../image.png`, isn't read.
  public static let documentFolder = ExternalResources(files: .documentFolder)

  /// No files: a document shows only the images that it contains, as data
  /// URLs.
  public static let none = ExternalResources(files: .none)

  /// The files in a folder, and in the folders inside it.
  ///
  /// Use it to let documents read the files beside the folders that they're
  /// in, such as a folder of images shared by the documents in the folders
  /// inside it.
  ///
  /// - Parameter url: The file URL of the folder.
  public static func folder(_ url: URL) -> ExternalResources {
    ExternalResources(files: .folder(url))
  }

  /// The same files, and the resources of the network that a document
  /// refers to by `https` URLs.
  ///
  /// A view doesn't read the network unless its setting allows it. Allow it
  /// only for documents that you trust: showing a document then sends
  /// requests to the servers that the document names, which tells them that
  /// the document is shown, and from which address.
  ///
  /// ```swift
  /// svgView.configuration = SVGUIViewConfiguration(
  ///   externalResources: .documentFolder.allowingNetwork()
  /// )
  /// ```
  ///
  /// The view reads `https` URLs only: it doesn't read `http` URLs, and
  /// doesn't follow a redirection to one. The requests carry no cookies and
  /// no credentials of the app, and their responses aren't cached on the
  /// disk. A resource larger than 64 MB isn't read. Reading takes part of
  /// the time of a rendering, which
  /// ``SVGUIViewConfiguration/timeoutDuration`` limits.
  ///
  /// A document with an `https` URL as its ``SVGUIView/baseURL`` reads the
  /// resources that its relative URLs refer to from the network, and no
  /// files. A document without a base URL reads the resources of its
  /// absolute `https` URLs.
  public func allowingNetwork() -> ExternalResources {
    ExternalResources(files: files, network: true)
  }

  /// The folder whose files are read for a document, or `nil` if no file is read.
  ///
  /// - Parameter baseURL: The URL of the document.
  func folder(forDocumentAt baseURL: URL) -> URL? {
    switch files {
    case .none: nil
    case .documentFolder: baseURL.deletingLastPathComponent()
    case .folder(let url): url
    }
  }
}
