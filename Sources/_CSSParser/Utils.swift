func matchIgnoreAsciiCase<T, E: Error>(_ input: String, handler: @escaping (String) -> Result<T, E>) -> Result<T, E> {
  handler(input.lowercased())
}
