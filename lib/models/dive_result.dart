/// Result models for DIVE SDK operations
sealed class DiveResult {
  const DiveResult();
}

/// Successful verification result from DIVE SDK
class DiveSuccess extends DiveResult {
  final String requestKey;
  final Map<String, dynamic>? fullResult;

  const DiveSuccess({required this.requestKey, this.fullResult});

  @override
  String toString() =>
      'DiveSuccess(requestKey: $requestKey, hasFullResult: ${fullResult != null})';
}

/// Error result from DIVE SDK
class DiveError extends DiveResult {
  final String code;
  final String message;

  const DiveError({required this.code, required this.message});

  @override
  String toString() => 'DiveError(code: $code, message: $message)';
}

/// User cancelled the DIVE SDK operation
class DiveCancelled extends DiveResult {
  const DiveCancelled();

  @override
  String toString() => 'DiveCancelled()';
}
