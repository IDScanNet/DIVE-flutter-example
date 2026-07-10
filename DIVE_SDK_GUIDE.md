# DIVE SDK Integration Guide

This guide covers integrating **DIVE SDK** (offline/server-mode) into your Flutter application.

> **Prerequisites:** Complete the [Flutter Layer Setup](README.md#flutter-layer-setup) first.

## What You'll Need

| Credential | Description |
|------------|-------------|
| **API Token** | Authentication token for DIVE API |
| **License Key** | Platform-specific key bound to your bundle ID |

## Table of Contents

1. [Android Integration](#android-integration)
2. [iOS Integration](#ios-integration)
3. [Usage](#usage)
4. [UI Customization](#ui-customization)
5. [Document Types](#document-types)

---

## Android Integration

### Step 1: Add Dependency

Edit `android/app/build.gradle.kts`:

```kotlin
dependencies {
    // DIVE SDK only
    implementation("net.idscan.components.android:dvs:1.13.1")
}
```

### Step 2: Update AndroidManifest.xml

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-feature android:name="android.hardware.camera" android:required="true" />

    <application ...>
        ...
    </application>
</manifest>
```

### Step 3: Implement MainActivity

Replace `android/app/src/main/kotlin/.../MainActivity.kt`:

```kotlin
package com.example.dive_demo_usage

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
// DIVE SDK imports
import net.idscan.components.android.dvs.*
import net.idscan.components.android.dvs.capture.CaptureConfig
import net.idscan.components.android.dvs.common.DocumentType
import net.idscan.components.android.dvs.net.VerificationConfig
import net.idscan.components.android.dvs.net.VerificationRequest

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.example.dive_demo_usage/dive_sdk"
    private val cameraPermissionCode = 1001

    private var methodChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingToken: String? = null
    private var pendingLicenseKey: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup DIVE SDK result listener
        DvsFragment.setFragmentResultListener(
            supportFragmentManager,
            this,
            DvsFragment.RequestCallback { request -> handleDvsRequestResult(request) },
            DvsFragment.ErrorCallback { error -> handleDvsError(error) }
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchDive" -> handleLaunchDive(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleLaunchDive(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        val token = call.argument<String>("token")
        val licenseKey = call.argument<String>("licenseKey")

        if (token == null || licenseKey == null) {
            result.error("INVALID_ARGUMENTS", "Token and licenseKey are required", null)
            return
        }

        pendingResult = result
        pendingToken = token
        pendingLicenseKey = licenseKey

        checkCameraPermissionAndLaunch()
    }

    private fun checkCameraPermissionAndLaunch() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            launchDiveSDK()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                cameraPermissionCode
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == cameraPermissionCode) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchDiveSDK()
            } else {
                pendingResult?.error(
                    "PERMISSION_DENIED",
                    "Camera permission is required to scan documents",
                    null
                )
                clearPendingState()
            }
        }
    }

    private fun launchDiveSDK() {
        val token = pendingToken ?: run {
            pendingResult?.error("CONFIGURATION_ERROR", "Missing token", null)
            clearPendingState()
            return
        }
        val licenseKey = pendingLicenseKey ?: run {
            pendingResult?.error("CONFIGURATION_ERROR", "Missing license key", null)
            clearPendingState()
            return
        }

        try {
            val captureConfig = CaptureConfig.builder(licenseKey)
                .withHints(true)
                .withDocumentTypeSelector(false)
                .withAutoStart(false)
                .withAutoSubmit(false)
                // Driver License
                .withDocumentType(DocumentType.DriverLicense)
                    .withFront(true, true)
                    .withBack(true, true)
                    .withFace(true, true, true)
                    .complete()
                // Passport
                .withDocumentType(DocumentType.Passport)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                // Passport Card
                .withDocumentType(DocumentType.PassportCard)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                // Green Card
                .withDocumentType(DocumentType.GreenCard)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                // International ID
                .withDocumentType(DocumentType.InternationalId)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                .build()

            val verificationConfig = VerificationConfig()
            val config = DvsConfig.Builder(
                token,
                captureConfig,
                verificationConfig,
                VerificationMode.Server
            ).build()

            val dvsFragment = DvsFragment.newInstance(config)
            supportFragmentManager.beginTransaction()
                .replace(android.R.id.content, dvsFragment, "DVS_FRAGMENT")
                .addToBackStack(null)
                .commit()

        } catch (e: Exception) {
            pendingResult?.error("SDK_ERROR", "Failed to launch DIVE SDK: ${e.message}", null)
            clearPendingState()
        }
    }

    private fun handleDvsRequestResult(request: VerificationRequest) {
        pendingResult?.success(mapOf(
            "success" to true,
            "requestKey" to request.requestId
        ))
        clearPendingState()
        supportFragmentManager.popBackStack()
    }

    private fun handleDvsError(error: DvsException) {
        pendingResult?.error("SDK_ERROR", error.message ?: "Unknown SDK error", null)
        clearPendingState()
        supportFragmentManager.popBackStack()
    }

    private fun clearPendingState() {
        pendingResult = null
        pendingToken = null
        pendingLicenseKey = null
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        clearPendingState()
        super.onDestroy()
    }
}
```

**Key Points:**
- Uses `FlutterFragmentActivity` for Fragment support
- Handles camera permission at runtime
- Returns `requestKey` for server-side verification lookup

---

## iOS Integration

### Step 1: Add DIVE SDK via Swift Package Manager

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** project
3. Go to **File → Add Package Dependencies...**
4. Add: `https://github.com/IDScanNet/DIVE-SDK-iOS.git`
5. Select version **3.0.0** or later
6. Add these products to **Runner** target:
   - `DIVESDK`
   - `DIVESDKCommon`

### Step 2: Create Configuration File

Create `ios/Runner/DiveConfig.json`:

```json
{
    "autoContinue": false,
    "autoStart": false,
    "autoSubmit": false,
    "isShowDocumentTypeSelect": false,
    "realFaceMode": "auto",
    "documentTypes": [
        {
            "isActive": true,
            "type": "ID",
            "steps": [
                {"type": "front", "name": "Document Front", "mode": {"uploader": true, "video": true}},
                {"type": "pdf", "name": "Document PDF417 Barcode", "mode": {"uploader": true, "video": true}},
                {"type": "face", "name": "Face", "mode": {"uploader": true, "video": true}}
            ]
        },
        {
            "isActive": true,
            "type": "Passport",
            "steps": [
                {"type": "front", "name": "Document Front", "mode": {"uploader": true, "video": true}},
                {"type": "face", "name": "Face", "mode": {"uploader": true, "video": true}}
            ]
        },
        {
            "isActive": true,
            "type": "PassportCard",
            "steps": [
                {"type": "front", "name": "Document Front", "mode": {"uploader": true, "video": true}},
                {"type": "mrz", "name": "Document MRZ", "mode": {"uploader": true, "video": true}},
                {"type": "face", "name": "Face", "mode": {"uploader": true, "video": true}}
            ]
        },
        {
            "isActive": true,
            "type": "GreenCard",
            "steps": [
                {"type": "front", "name": "Document Front", "mode": {"uploader": true, "video": true}},
                {"type": "mrz", "name": "Document MRZ", "mode": {"uploader": true, "video": true}},
                {"type": "face", "name": "Face", "mode": {"uploader": true, "video": true}}
            ]
        },
        {
            "isActive": true,
            "type": "InternationalId",
            "steps": [
                {"type": "front", "name": "Document Front", "mode": {"uploader": true, "video": true}},
                {"type": "mrz", "name": "Document MRZ", "mode": {"uploader": true, "video": true}},
                {"type": "face", "name": "Face", "mode": {"uploader": true, "video": true}}
            ]
        }
    ],
    "licenseKey": ""
}
```

**Add to Xcode:**
1. Right-click **Runner** folder → **Add Files to "Runner"...**
2. Select `DiveConfig.json`
3. Ensure **Runner** target is checked
4. Click **Add**

### Step 3: Update Info.plist

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan identity documents</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is required to upload document images</string>
```

### Step 4: Implement AppDelegate

Replace `ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit
import DIVESDK
import DIVESDKCommon

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var flutterResult: FlutterResult?
    private var diveSDK: DIVESDK?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController

        methodChannel = FlutterMethodChannel(
            name: "com.example.dive_demo_usage/dive_sdk",
            binaryMessenger: controller.binaryMessenger
        )
        methodChannel?.setMethodCallHandler(handle)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "launchDive":
            handleLaunchDive(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleLaunchDive(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: String],
              let token = args["token"],
              let licenseKey = args["licenseKey"] else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Token and licenseKey are required",
                details: nil
            ))
            return
        }

        flutterResult = result

        guard var config = loadJson(filename: "DiveConfig") else {
            result(FlutterError(
                code: "CONFIGURATION_ERROR",
                message: "Failed to load DiveConfig.json",
                details: nil
            ))
            flutterResult = nil
            return
        }
        config["licenseKey"] = licenseKey

        diveSDK = DIVESDK(configuration: config, token: token, delegate: self)
        let controller = window?.rootViewController as! FlutterViewController
        diveSDK?.start(from: controller)
    }

    private func loadJson(filename: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// DIVE SDK Delegate
extension AppDelegate: DIVESDKDelegate {
    func diveSDKDataPrepaired(sdk: IDIVESDK, data: DIVESDKData) {
        sdk.close()
        sdk.sendData(data: data)
    }

    func diveSDKResult(sdk: IDIVESDK, result: [String: Any]) {
        let requestId = result["requestId"] as? String ?? ""
        flutterResult?([
            "success": true,
            "requestKey": requestId,
            "fullResult": result
        ])
        flutterResult = nil
        diveSDK = nil
    }

    func diveSDKError(sdk: IDIVESDK, error: Error) {
        if window?.rootViewController?.presentedViewController != nil {
            window?.rootViewController?.dismiss(animated: true) { [weak self] in
                self?.flutterResult?(FlutterError(
                    code: "SDK_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
                self?.flutterResult = nil
                self?.diveSDK = nil
            }
        } else {
            flutterResult?(FlutterError(
                code: "SDK_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
            flutterResult = nil
            diveSDK = nil
        }
    }

    func diveSDKSendingDataProgress(sdk: IDIVESDK, progress: Float, requestTime: TimeInterval) {
        // Optional: Handle upload progress
    }
}
```

---

## Usage

In your Flutter code:

```dart
import 'package:your_app/services/dive_sdk_service.dart';
import 'package:your_app/config/credentials.dart';

Future<void> startVerification() async {
  final result = await DiveSDKService.launchDive(
    token: DiveCredentials.diveToken,
    licenseKey: DiveCredentials.diveLicenseKey,
  );

  switch (result) {
    case DiveSuccess(:final requestKey):
      print('Verification successful! Request key: $requestKey');
      // Use requestKey to fetch results from your backend
      break;
    case DiveError(:final code, :final message):
      print('Error: $code - $message');
      break;
    case DiveCancelled():
      print('User cancelled verification');
      break;
  }
}
```

---

## UI Customization

### Android

The SDK uses Material Design 2 theming. Create a custom theme in `android/app/src/main/res/values/styles.xml`:

```xml
<style name="Theme.DiveDemo" parent="Theme.MaterialComponents.Light.NoActionBar">
    <item name="colorPrimary">@color/your_primary</item>
    <item name="colorOnSurface">@color/your_text_color</item>
</style>
```

For detailed theming options, see [DIVE SDK Android Documentation](https://github.com/IDScanNet/DIVE-SDK-Android).

### iOS

Customize via `DiveConfig.json` or SDK configuration options. See [DIVE SDK iOS Documentation](https://github.com/IDScanNet/DIVE-SDK-iOS).

---

## Document Types

| Type | Android Enum | iOS Config |
|------|--------------|------------|
| Driver License | `DocumentType.DriverLicense` | `"ID"` |
| Passport | `DocumentType.Passport` | `"Passport"` |
| Passport Card | `DocumentType.PassportCard` | `"PassportCard"` |
| Green Card | `DocumentType.GreenCard` | `"GreenCard"` |
| International ID | `DocumentType.InternationalId` | `"InternationalId"` |

---

## Error Codes

| Code | Description |
|------|-------------|
| `INVALID_ARGUMENTS` | Missing token or licenseKey |
| `PERMISSION_DENIED` | Camera permission denied |
| `CONFIGURATION_ERROR` | Invalid SDK configuration or license key |
| `SDK_ERROR` | DIVE SDK internal error |

---

## Additional Resources

- [DIVE SDK Android](https://github.com/IDScanNet/DIVE-SDK-Android)
- [DIVE SDK iOS](https://github.com/IDScanNet/DIVE-SDK-iOS)
- [IDScan.net Developer Docs](https://docs.idscan.net/dive/index.html)
