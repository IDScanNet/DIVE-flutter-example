import 'dart:io' show Platform;

/// DIVE SDK Configuration and Credentials
///
/// This file contains all the necessary credentials and configuration
/// for both DIVE SDK and DIVE Online SDK.
class DiveCredentials {
  // Private constructor to prevent instantiation
  DiveCredentials._();

  // ============================================================================
  // DIVE SDK Configuration
  // ============================================================================

  /// API Token for DIVE SDK authentication
  static const String diveToken = '<dive_sdk_api_token>';

  /// License Key for DIVE SDK (Android/iOS)
  /// This key is bound to the Android/iOS bundle ID
  static const String diveLicenseKey =
      '<dive_sdk_license_key>';

  // ============================================================================
  // DIVE Online SDK Configuration
  // ============================================================================

  /// API Token for DIVE Online SDK authentication
  static const String diveOnlineToken =
      '<dive_online_sdk_api_token>';

  /// Integration ID for DIVE Online SDK (iOS)
  /// Bound to iOS bundle ID
  static const String _diveOnlineIntegrationIdIOS =
      '<dive_online_sdk_integration_id_ios>';

  /// Integration ID for DIVE Online SDK (Android)
  /// Bound to Android application ID: com.example.dive_demo_usage
  static const String _diveOnlineIntegrationIdAndroid =
      '<dive_online_sdk_integration_id_android>';

  /// Integration ID for DIVE Online SDK (platform-specific)
  static String get diveOnlineIntegrationId =>
      Platform.isIOS ? _diveOnlineIntegrationIdIOS : _diveOnlineIntegrationIdAndroid;

  /// Base URL for DIVE Online SDK API
  static const String diveOnlineBaseUrl =
      'https://api-diveonline.idscan.net/api/v2';

  // ============================================================================
  // Applicant Information (for DIVE Online SDK)
  // ============================================================================

  /// First name for creating applicants
  static const String applicantFirstName = 'John';

  /// Last name for creating applicants
  static const String applicantLastName = 'Doe';

  /// Phone number for creating applicants
  static const String applicantPhone = '+1234567890';
}
