extension Result {
  package func mapError<F: Error>(operation: (Failure) -> F) -> Result<Success, F> {
    switch self {
    case .success(let value):
      .success(value)
    case .failure(let error):
      .failure(operation(error))
    }
  }
}
