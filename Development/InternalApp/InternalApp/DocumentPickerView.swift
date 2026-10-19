import SwiftUI
import UniformTypeIdentifiers

/// Picks an SVG file, such as one that shows a rendering bug, to open outside the test suite.
///
/// The picker opens a copy of the file, so the app can read it without security-scoped access.
struct DocumentPickerView: UIViewControllerRepresentable {
  let onPick: (URL) -> Void

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
      self.onPick = onPick
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      if let url = urls.first {
        onPick(url)
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.svg], asCopy: true)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}
}
