/// Utility functions for token handling
class TokenUtils {
  /// Check if token is a public key (starts with pk_)
  static bool isPublicKey(String token) {
    return token.trim().startsWith('pk_');
  }
}
