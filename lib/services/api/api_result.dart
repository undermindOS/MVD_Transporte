/// Why a call to the backend gave no data; the UI picks the message
/// (docs/design/contrato-v1.md, "Errores").
enum ApiFailure {
  /// No connection (SocketException, ClientException).
  offline,

  /// The request or the proxy's upstream took too long (504).
  timeout,

  /// The stop does not exist, or its number is not a valid stop id.
  notFound,

  /// Rate limited (429) or the official API budget is spent (503
  /// upstream_busy): try again after `retryAfter`.
  busy,

  /// Not offered by this build (no proxy) or not configured on the proxy.
  unavailable,

  /// Anything else: server error, unexpected answer, a bug.
  failed,
}

/// The answer of one call: the value, or why there is none.
sealed class ApiResult<T> {
  const ApiResult();

  /// The value, or null on failure.
  T? get valueOrNull;
}

final class ApiOk<T> extends ApiResult<T> {
  const ApiOk(this.value);

  final T value;

  @override
  T? get valueOrNull => value;
}

final class ApiError<T> extends ApiResult<T> {
  const ApiError(this.failure, {this.retryAfter});

  final ApiFailure failure;

  /// For [ApiFailure.busy]: how long to wait before asking again.
  final Duration? retryAfter;

  @override
  T? get valueOrNull => null;
}
