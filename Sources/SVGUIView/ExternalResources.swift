import Foundation

/// The files outside a document that a view reads for it, such as the image
/// files of `<image>` elements.
///
/// A document refers to other files by URLs relative to its own URL, which
/// is the view's ``SVGUIView/baseURL``. A view reads only files: it doesn't
/// read the network. A document that the view has no base URL for, such as
/// one that's set as ``SVGUIView/data``, reads no files.
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
