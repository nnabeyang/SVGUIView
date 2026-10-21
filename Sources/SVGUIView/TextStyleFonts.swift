import CoreText
import UIKit

extension SVGUIView {
  /// Lets text styles, such as `UICTFontTextStyleBody`, use the user's preferred sizes, which only UIKit provides.
  static let installTextStyleFonts: Void = {
    SystemFontDatabaseCoreText.textStyleDescriptor = { textStyle in
      UIFontDescriptor.preferredFontDescriptor(withTextStyle: UIFont.TextStyle(rawValue: textStyle)) as CTFontDescriptor
    }
  }()
}
