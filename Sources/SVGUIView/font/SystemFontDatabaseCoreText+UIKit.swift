import CoreText
import UIKit

extension SystemFontDatabaseCoreText {
  /// The font descriptor for a text style, such as `UICTFontTextStyleBody`, at the user's preferred size.
  ///
  /// Only UIKit provides it, so this is the only place outside `SVGUIView.swift` that uses UIKit.
  static func preferredFontDescriptor(textStyle: String) -> CTFontDescriptor {
    UIFontDescriptor.preferredFontDescriptor(withTextStyle: UIFont.TextStyle(rawValue: textStyle)) as CTFontDescriptor
  }
}
