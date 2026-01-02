extension FixedWidthInteger {
  func checkedSub(_ other: Self) -> Self? {
    let (value, overflow) = self.subtractingReportingOverflow(other)
    return overflow ? nil : value
  }

  func checkedDiv(_ other: Self) -> Self? {
    if other == 0 {
      return nil
    }
    if Self.min < 0 && self == Self.min && other == -1 {
      return nil
    }
    return self / other
  }
}
