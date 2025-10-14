protocol FontAccessor {
  func font(policy: ExternalResourceDownloadPolicy) -> Font
}

enum ExternalResourceDownloadPolicy {
  case forbid
  case allow
}

protocol FontSelector {
  func fontRangesForFamily(fontDescription: FontDescription, familyName: String) -> FontRanges
}
