# DIVE SDK Flutter Demo

Example Flutter application demonstrating **DIVE SDK** and **DIVE Online SDK** integration for document verification on Android and iOS.

## Table of Contents

1. [Running the Demo](#running-the-demo)
2. [Integration Overview](#integration-overview)
3. [SDK Comparison](#sdk-comparison)
4. [Security Architecture](#security-architecture)
5. [Flutter Layer Setup](#flutter-layer-setup)
6. [Platform-Specific Guides](#platform-specific-guides)
7. [Troubleshooting](#troubleshooting)

---

## Running the Demo

### Prerequisites

- Flutter SDK 3.0+
- Android Studio / Xcode
- Android SDK command-line tools installed and licenses accepted (`flutter doctor`), JDK 17
- Android `minSdk` 23+ (required by DIVE Android SDK 2.0.0)
- Physical device (camera required for document scanning)

### Setup Steps

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd DIVEDemo
   ```

2. **Configure credentials:**

   Edit `lib/config/credentials.dart` with your DIVE credentials:

   ```dart
   class DiveCredentials {
     // For DIVE SDK (offline)
     static const String diveToken = 'YOUR_DIVE_TOKEN';
     static const String diveLicenseKey = 'YOUR_LICENSE_KEY';

     // For DIVE Online SDK
     static const String diveOnlineToken = 'YOUR_DIVE_ONLINE_TOKEN';
  /// Integration ID for DIVE Online SDK (iOS)
  /// Bound to iOS bundle ID
  static const String _diveOnlineIntegrationIdIOS =
      '<dive_online_sdk_integration_id_ios>';

  /// Integration ID for DIVE Online SDK (Android)
  /// Bound to Android application ID: com.example.dive_demo_usage
  static const String _diveOnlineIntegrationIdAndroid =
      '<dive_online_sdk_integration_id_android>';
     static const String diveOnlineBaseUrl = 'https://api-diveonline.idscan.net/api/v2';
   }
   ```

3. **Install dependencies:**
   ```bash
   flutter pub get
   ```

4. **Run on device:**
   ```bash
   flutter run
   ```

---

## Integration Overview

Choose the SDK based on your requirements:

| Choose | When to Use |
|--------|-------------|
| **[DIVE SDK Guide](DIVE_SDK_GUIDE.md)** | You need server-mode verification with request key |
| **[DIVE Online SDK Guide](DIVE_ONLINE_SDK_GUIDE.md)** | You need full online verification workflow with results |

---

## SDK Comparison

| Feature | DIVE SDK | DIVE Online SDK |
|---------|----------|-----------------|
| **Purpose** | Server-mode document verification | Full online verification workflow |
| **Result** | Request Key (for server-side lookup) | Complete verification result with fields |
| **Applicant** | Not required | Required (created before scanning) |
| **License Key** | Required | Not needed |
| **Integration ID** | Not needed | Required |
| **Best for** | Simple integrations, custom backend | Full verification flows |

---

## Security Architecture

### Key Types

| Key Type | Prefix | Usage | Storage |
|----------|--------|-------|---------|
| **Private Key** | `sk_*` | Create applicants, fetch results | Backend ONLY |
| **Public Key** | `pk_*` | Initialize SDK, public API calls | Mobile app OK |
| **License Key** | Base64 | SDK initialization | Mobile app OK |

### Production Security Flow

```
⚠️  SECURITY WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Creating applicants requires a PRIVATE KEY (sk_*).
Private keys must NEVER be stored in mobile applications.

If your private key is exposed, attackers can:
• Create unlimited applicants
• Access your verification data
• Incur charges on your account
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Production Architecture:**

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│   Mobile App    │         │  Your Backend   │         │   DIVE API      │
│  (Public Keys)  │         │ (Private Keys)  │         │                 │
└────────┬────────┘         └────────┬────────┘         └────────┬────────┘
         │                           │                           │
         │  1. Request verification  │                           │
         │ ─────────────────────────>│                           │
         │                           │  2. Create Applicant      │
         │                           │ ─────────────────────────>│
         │                           │  3. Return applicantId    │
         │                           │ <─────────────────────────│
         │  4. Return applicantId    │                           │
         │ <─────────────────────────│                           │
         │                           │                           │
         │  5. Launch SDK with       │                           │
         │     applicantId + pk_*    │                           │
         │ ─────────────────────────────────────────────────────>│
         │                           │                           │
```

---

## Flutter Layer Setup

This section covers the common Flutter code needed for both SDKs.

### Step 1: Create Result Models

Create `lib/models/dive_result.dart`:

```dart
/// Result models for DIVE SDK operations
sealed class DiveResult {
  const DiveResult();
}

/// Successful verification result
class DiveSuccess extends DiveResult {
  final String requestKey;
  final Map<String, dynamic>? fullResult;

  const DiveSuccess({
    required this.requestKey,
    this.fullResult,
  });

  @override
  String toString() => 'DiveSuccess(requestKey: $requestKey)';
}

/// Error result
class DiveError extends DiveResult {
  final String code;
  final String message;

  const DiveError({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'DiveError(code: $code, message: $message)';
}

/// User cancelled the operation
class DiveCancelled extends DiveResult {
  const DiveCancelled();

  @override
  String toString() => 'DiveCancelled()';
}
```

### Step 2: Create Platform Channel Service

Create `lib/services/dive_sdk_service.dart`:

```dart
import 'dart:async';
import 'package:flutter/services.dart';
import '../models/dive_result.dart';

/// Service for communicating with native DIVE SDK implementations
class DiveSDKService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.dive_demo_usage/dive_sdk',
  );

  /// Launch DIVE SDK for document scanning (offline mode)
  ///
  /// [token] - API authorization token
  /// [licenseKey] - License key for SDK
  static Future<DiveResult> launchDive({
    required String token,
    required String licenseKey,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'launchDive',
        {'token': token, 'licenseKey': licenseKey},
      );
      return _parseResult(result);
    } on PlatformException catch (e) {
      return DiveError(
        code: e.code,
        message: e.message ?? 'Platform error occurred',
      );
    } catch (e) {
      return DiveError(code: 'UNEXPECTED_ERROR', message: e.toString());
    }
  }

  /// Launch DIVE Online SDK for document scanning
  ///
  /// [token] - Public API token (pk_*)
  /// [integrationId] - Integration ID
  /// [baseUrl] - Base URL for DIVE Online API
  /// [firstName], [lastName], [phone] - Applicant info
  static Future<DiveResult> launchDiveOnline({
    required String token,
    required String integrationId,
    required String baseUrl,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'launchDiveOnline',
        {
          'token': token,
          'integrationId': integrationId,
          'baseUrl': baseUrl,
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
        },
      );
      return _parseResult(result);
    } on PlatformException catch (e) {
      return DiveError(
        code: e.code,
        message: e.message ?? 'Platform error occurred',
      );
    } catch (e) {
      return DiveError(code: 'UNEXPECTED_ERROR', message: e.toString());
    }
  }

  /// Parse result from native platform
  static DiveResult _parseResult(Map<Object?, Object?>? result) {
    if (result == null) {
      return const DiveError(
        code: 'NULL_RESULT',
        message: 'No result received from native SDK',
      );
    }

    final success = result['success'] as bool?;
    if (success == true) {
      final requestKey = result['requestKey'] as String? ?? '';
      final fullResult = result['fullResult'] as Map<Object?, Object?>?;

      Map<String, dynamic>? fullResultMap;
      if (fullResult != null) {
        fullResultMap = _convertToStringMap(fullResult);
      }

      if (fullResultMap != null || requestKey.isNotEmpty) {
        return DiveSuccess(requestKey: requestKey, fullResult: fullResultMap);
      }
      return const DiveError(
        code: 'MISSING_DATA',
        message: 'No result data received from SDK',
      );
    }

    final cancelled = result['cancelled'] as bool?;
    if (cancelled == true) {
      return const DiveCancelled();
    }

    final error = result['error'] as String?;
    final errorCode = result['errorCode'] as String? ?? 'UNKNOWN_ERROR';
    if (error != null) {
      return DiveError(code: errorCode, message: error);
    }

    return const DiveError(
      code: 'INVALID_RESULT',
      message: 'Invalid result format from native SDK',
    );
  }

  static Map<String, dynamic> _convertToStringMap(Map<Object?, Object?> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map<Object?, Object?>) {
        result[stringKey] = _convertToStringMap(value);
      } else if (value is List) {
        result[stringKey] = _convertList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  static List<dynamic> _convertList(List list) {
    return list.map((item) {
      if (item is Map<Object?, Object?>) {
        return _convertToStringMap(item);
      } else if (item is List) {
        return _convertList(item);
      }
      return item;
    }).toList();
  }
}
```

### Step 3: Create Credentials Configuration

Create `lib/config/credentials.dart`:

```dart
/// DIVE SDK Configuration
///
/// ⚠️ DEMO ONLY: In production, private keys (sk_*) must be on your backend.
class DiveCredentials {
  DiveCredentials._();

  // === DIVE SDK (offline) ===
  static const String diveToken = 'YOUR_DIVE_TOKEN';
  static const String diveLicenseKey = 'YOUR_LICENSE_KEY';

  // === DIVE Online SDK ===
  static const String diveOnlineToken = 'YOUR_DIVE_ONLINE_TOKEN';
  static const String diveOnlineIntegrationId = 'YOUR_INTEGRATION_ID';
  static const String diveOnlineBaseUrl = 'https://api-diveonline.idscan.net/api/v2';

  // === Demo Applicant Info ===
  static const String applicantFirstName = 'John';
  static const String applicantLastName = 'Doe';
  static const String applicantPhone = '+1234567890';
}
```

---

## Platform-Specific Guides

After setting up the Flutter layer, follow the guide for your chosen SDK:

| SDK | Guide | Dependencies |
|-----|-------|--------------|
| **DIVE SDK** | [DIVE_SDK_GUIDE.md](DIVE_SDK_GUIDE.md) | `net.idscan.components.android:dvs:2.0.0` (Android), `DIVESDK` (iOS) |
| **DIVE Online SDK** | [DIVE_ONLINE_SDK_GUIDE.md](DIVE_ONLINE_SDK_GUIDE.md) | `net.idscan.components.android:dvsonline:2.0.0` (Android), `DIVEOnlineSDK` (iOS) |

Both Android artifacts share the same transitive modules (`dvs-common`, `dvs-capture`, `dvs-net`), so they must always be bumped to the same version.

### Android 2.0.0 notes

`CaptureConfig.Builder` methods were renamed in 2.0.0 (see `DiveSDKActivity.launchOfflineSDK()`):

| 1.13.x | 2.0.0 |
|--------|-------|
| `withHints(true)` | `withPreviewAnimations(true)` |
| `withDocumentTypeSelector(false)` | `withShowDocumentTypeSelector(false)` |
| `withAutoSubmit(false)` | `showSubmitBtn(true)` |

The DIVE Online API (`DvsOnlineClient`, `DvsOnlineConfig`, `DvsOnlineFragment`, `ValidationResult`) is unchanged; `ApplicantInfo` gained an optional 7-argument constructor with a `sendEmail` flag. `DocumentType` added `IdentificationCard` and `EmploymentAuthorization`.

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| Camera permission not requested | Check AndroidManifest.xml / Info.plist |
| `CONFIGURATION_ERROR` | Verify license key matches bundle ID |
| `APPLICANT_CREATION_ERROR` | Check token and network connectivity |
| No such module (iOS) | Re-add Swift Package, clean build |

### Debug Logging

- **Android**: Check Logcat
- **iOS**: Check Xcode console

---

## Additional Resources

- [DIVE SDK Android](https://github.com/IDScanNet/DIVE-SDK-Android)
- [DIVE SDK iOS](https://github.com/IDScanNet/DIVE-SDK-iOS)
- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [IDScan.net Developer Docs](https://docs.idscan.net/dive/index.html)
