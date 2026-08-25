# DIVE Online SDK Integration Guide

This guide covers integrating **DIVE Online SDK** into your Flutter application for full online verification workflows.

> **Prerequisites:** Complete the [Flutter Layer Setup](README.md#flutter-layer-setup) first.

## What You'll Need

| Credential | Description |
|------------|-------------|
| **API Token** | Authentication token (use `pk_*` in production, `sk_*` for demo only) |
| **Integration ID** | Your DIVE Online integration identifier |
| **Base URL** | DIVE Online API endpoint |

## Table of Contents

1. [Android Integration](#android-integration)
2. [iOS Integration](#ios-integration)
3. [Usage](#usage)
4. [Applicant Creation](#applicant-creation)

---

## Android Integration

### Step 1: Add Dependency

Edit `android/app/build.gradle.kts`:

```kotlin
dependencies {
    // DIVE Online SDK only
    implementation("net.idscan.components.android:dvsonline:2.0.0")
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
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
// DIVE Online SDK imports
import net.idscan.components.android.dvsonline.DvsOnlineConfig
import net.idscan.components.android.dvsonline.DvsOnlineException
import net.idscan.components.android.dvsonline.DvsOnlineFragment
import net.idscan.components.android.dvsonline.net.ApplicantInfo
import net.idscan.components.android.dvsonline.net.DvsOnlineClient
import net.idscan.components.android.dvsonline.net.ValidationResult
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.example.dive_demo_usage/dive_sdk"
    private val cameraPermissionCode = 1001

    private var methodChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null

    // DIVE Online SDK state
    private var pendingToken: String? = null
    private var pendingIntegrationId: String? = null
    private var pendingBaseUrl: String? = null
    private var pendingFirstName: String? = null
    private var pendingLastName: String? = null
    private var pendingPhone: String? = null
    private var pendingEmail: String? = null
    private var pendingReferenceId: String? = null
    private var pendingCallbackUrl: String? = null

    // Background executor for network calls
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup DIVE Online SDK result listener
        DvsOnlineFragment.setFragmentResultListener(
            supportFragmentManager,
            this,
            { result -> handleDvsOnlineResult(result) },
            { error -> handleDvsOnlineError(error) }
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
                "launchDiveOnline" -> handleLaunchDiveOnline(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleLaunchDiveOnline(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        val token = call.argument<String>("token")
        val integrationId = call.argument<String>("integrationId")
        val baseUrl = call.argument<String>("baseUrl")
        val firstName = call.argument<String>("firstName")
        val lastName = call.argument<String>("lastName")
        // Optional fields
        val phone = call.argument<String>("phone")
        val email = call.argument<String>("email")
        val referenceId = call.argument<String>("referenceId")
        val callbackUrl = call.argument<String>("callbackUrl")

        if (token == null || integrationId == null || baseUrl == null ||
            firstName == null || lastName == null) {
            result.error(
                "INVALID_ARGUMENTS",
                "Token, integrationId, baseUrl, firstName, and lastName are required",
                null
            )
            return
        }

        pendingResult = result
        pendingToken = token
        pendingIntegrationId = integrationId
        pendingBaseUrl = baseUrl
        pendingFirstName = firstName
        pendingLastName = lastName
        pendingPhone = phone
        pendingEmail = email
        pendingReferenceId = referenceId
        pendingCallbackUrl = callbackUrl

        checkCameraPermissionAndLaunch()
    }

    private fun checkCameraPermissionAndLaunch() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            launchDiveOnlineSDK()
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
                launchDiveOnlineSDK()
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

    private fun launchDiveOnlineSDK() {
        val token = pendingToken
        val integrationId = pendingIntegrationId
        val baseUrl = pendingBaseUrl
        val firstName = pendingFirstName
        val lastName = pendingLastName
        val phone = pendingPhone
        val email = pendingEmail
        val referenceId = pendingReferenceId
        val callbackUrl = pendingCallbackUrl

        if (token == null || integrationId == null || baseUrl == null ||
            firstName == null || lastName == null) {
            pendingResult?.error(
                "CONFIGURATION_ERROR",
                "Missing required parameters for DIVE Online SDK",
                null
            )
            clearPendingState()
            return
        }

        // ⚠️ DEMO ONLY: In production, applicant creation should be done by your backend
        executor.submit {
            try {
                val client = DvsOnlineClient(
                    baseUrl,
                    integrationId,
                    token,
                    DvsOnlineClient.DEFAULT_AGENT
                )

                val applicantInfo = ApplicantInfo(
                    firstName,
                    lastName,
                    phone ?: "",
                    email ?: "",
                    callbackUrl ?: "",
                    false   // sendLinkViaSms
                )
                // Note: referenceId can be passed via metadata if needed
                // Since 2.0.0 there is also a 7-argument constructor with a trailing
                // sendEmail flag: ApplicantInfo(..., sendSms, sendEmail)

                val callResult = client.createApplicant(applicantInfo).execute()

                if (callResult.isSuccess && callResult.result != null) {
                    val applicantId = callResult.result
                    mainHandler.post {
                        showDvsOnlineFragment(token, integrationId, applicantId, baseUrl)
                    }
                } else {
                    val errorMessage = callResult.error?.toString() ?: "Failed to create applicant"
                    mainHandler.post {
                        pendingResult?.error("APPLICANT_CREATION_ERROR", errorMessage, null)
                        clearPendingState()
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    pendingResult?.error(
                        "APPLICANT_CREATION_ERROR",
                        "Failed to create applicant: ${e.message}",
                        null
                    )
                    clearPendingState()
                }
            }
        }
    }

    private fun showDvsOnlineFragment(
        token: String,
        integrationId: String,
        applicantId: String,
        baseUrl: String
    ) {
        try {
            val config = DvsOnlineConfig.Builder(
                token,
                integrationId,
                applicantId,
                "IDScan"  // companyPrefix
            )
                .withCustomUrl(baseUrl)
                .build()

            val fragment = DvsOnlineFragment.newInstance(config)
            supportFragmentManager.beginTransaction()
                .setPrimaryNavigationFragment(fragment)
                .replace(android.R.id.content, fragment, "DVS_ONLINE_FRAGMENT")
                .addToBackStack("DVS_ONLINE_FRAGMENT")
                .commit()

        } catch (e: Exception) {
            pendingResult?.error(
                "SDK_ERROR",
                "Failed to launch DIVE Online SDK: ${e.message}",
                null
            )
            clearPendingState()
        }
    }

    private fun handleDvsOnlineResult(result: ValidationResult) {
        try {
            val fieldsMap = mutableMapOf<String, String>()
            result.documentFields.forEach { (key, value) ->
                fieldsMap[key.name] = value
            }

            val validationStatusMap = mapOf(
                "code" to result.validationStatus.code.name,
                "documentIsValid" to result.validationStatus.documentIsValid,
                "isExpired" to result.validationStatus.isExpired,
                "faceIsValid" to result.validationStatus.faceIsValid,
                "antiSpoofingIsValid" to result.validationStatus.antiSpoofingIsValid
            )

            val fullResultMap = mapOf(
                "attemptId" to result.attemptId,
                "attemptsLeft" to result.attemptsLeft,
                "documentType" to result.documentType.name,
                "validationStatus" to validationStatusMap,
                "documentFields" to fieldsMap
            )

            pendingResult?.success(mapOf(
                "success" to true,
                "requestKey" to result.attemptId.toString(),
                "fullResult" to fullResultMap
            ))
            clearPendingState()
            supportFragmentManager.popBackStack()

        } catch (e: Exception) {
            pendingResult?.error(
                "RESULT_PROCESSING_ERROR",
                "Error processing DIVE Online SDK result: ${e.message}",
                null
            )
            clearPendingState()
        }
    }

    private fun handleDvsOnlineError(error: DvsOnlineException) {
        pendingResult?.error(
            "SDK_ERROR",
            error.message ?: "Unknown DIVE Online SDK error",
            null
        )
        clearPendingState()
        supportFragmentManager.popBackStack()
    }

    private fun clearPendingState() {
        pendingResult = null
        pendingToken = null
        pendingIntegrationId = null
        pendingBaseUrl = null
        pendingFirstName = null
        pendingLastName = null
        pendingPhone = null
        pendingEmail = null
        pendingReferenceId = null
        pendingCallbackUrl = null
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        clearPendingState()
        executor.shutdown()
        super.onDestroy()
    }
}
```

**Key Points:**
- Uses `FlutterFragmentActivity` for Fragment support
- Creates applicant on background thread before launching SDK
- Returns full verification result with document fields

---

## iOS Integration

### Step 1: Add DIVE Online SDK via Swift Package Manager

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** project
3. Go to **File → Add Package Dependencies...**
4. Add: `https://github.com/IDScanNet/DIVE-SDK-iOS.git`
5. Select version **3.260728.1** or later (up to next major)
6. Add these products to **Runner** target:
   - `DIVEOnlineSDK`
   - `DIVESDKCommon`

### Step 2: Update Info.plist

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan identity documents</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is required to upload document images</string>
```

### Step 3: Implement AppDelegate

Replace `ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit
import DIVEOnlineSDK
import DIVESDKCommon

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var flutterResult: FlutterResult?
    private var diveOnlineSDK: DIVEOnlineSDK?

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
        case "launchDiveOnline":
            handleLaunchDiveOnline(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleLaunchDiveOnline(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let token = args["token"] as? String,
              let integrationId = args["integrationId"] as? String,
              let baseUrl = args["baseUrl"] as? String,
              let firstName = args["firstName"] as? String,
              let lastName = args["lastName"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Token, integrationId, baseUrl, firstName, and lastName are required",
                details: nil
            ))
            return
        }

        // Optional fields
        let phone = args["phone"] as? String
        let email = args["email"] as? String
        let referenceId = args["referenceId"] as? String
        let callbackUrl = args["callbackUrl"] as? String

        flutterResult = result

        // ⚠️ DEMO ONLY: In production, applicant creation should be done by your backend
        createApplicant(
            baseURL: baseUrl,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            email: email,
            referenceId: referenceId,
            callbackUrl: callbackUrl,
            integrationId: integrationId,
            token: token
        ) { [weak self] applicantResult in
            guard let self = self else { return }

            switch applicantResult {
            case .success(let applicantId):
                self.diveOnlineSDK = DIVEOnlineSDK(
                    applicantID: applicantId,
                    integrationID: integrationId,
                    token: token,
                    baseURL: baseUrl + "/public",
                    delegate: self
                )

                self.diveOnlineSDK?.updateLocation()
                self.diveOnlineSDK?.loadConfiguration { [weak self] error in
                    guard let self = self else { return }

                    if let error = error {
                        self.flutterResult?(FlutterError(
                            code: "CONFIGURATION_ERROR",
                            message: "Failed to load configuration: \(error.localizedDescription)",
                            details: nil
                        ))
                        self.flutterResult = nil
                        self.diveOnlineSDK = nil
                    } else {
                        DispatchQueue.main.async {
                            let controller = self.window?.rootViewController as! FlutterViewController
                            self.diveOnlineSDK?.start(from: controller)
                        }
                    }
                }

            case .failure(let error):
                self.flutterResult?(FlutterError(
                    code: "APPLICANT_CREATION_ERROR",
                    message: "Failed to create applicant: \(error.localizedDescription)",
                    details: nil
                ))
                self.flutterResult = nil
            }
        }
    }

    private func createApplicant(
        baseURL: String,
        firstName: String,
        lastName: String,
        phone: String?,
        email: String?,
        referenceId: String?,
        callbackUrl: String?,
        integrationId: String,
        token: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let urlString = baseURL + "/private/Applicants"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "AppDelegate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Build request body with required and optional fields
        var body: [String: Any] = [
            "integrationId": integrationId,
            "firstName": firstName,
            "lastName": lastName
        ]
        if let phone = phone { body["phone"] = phone }
        if let email = email { body["email"] = email }
        if let referenceId = referenceId { body["referenceId"] = referenceId }
        if let callbackUrl = callbackUrl { body["callbackUrl"] = callbackUrl }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AppDelegate", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP Error"])))
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let applicantId = json["applicantId"] as? String {
                    DispatchQueue.main.async { completion(.success(applicantId)) }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "AppDelegate", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "applicantId not found"])))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}

// DIVE Online SDK Delegate
extension AppDelegate: DIVEOnlineSDKDelegate {
    func diveOnlineSDKResult(sdk: IDIVEOnlineSDK, result: DIVEOnlineResult) {
        var fieldsMap: [String: String] = [:]
        for (key, value) in result.documentFields {
            fieldsMap[key.rawValue] = value
        }

        let validationStatusMap: [String: Any] = [
            "code": result.validationStatus.code.rawValue,
            "documentIsValid": result.validationStatus.documentIsValid,
            "isExpired": result.validationStatus.isExpired,
            "faceIsValid": result.validationStatus.faceIsValid,
            "antiSpoofingIsValid": result.validationStatus.antiSpoofingIsValid
        ]

        let fullResultMap: [String: Any] = [
            "attemptId": result.attemptId,
            "attemptsLeft": result.attemptsLeft,
            "documentType": result.documentType.rawValue,
            "validationStatus": validationStatusMap,
            "documentFields": fieldsMap
        ]

        flutterResult?([
            "success": true,
            "requestKey": String(result.attemptId),
            "fullResult": fullResultMap
        ])
        flutterResult = nil
        diveOnlineSDK = nil
    }

    func diveOnlineSDKError(sdk: IDIVEOnlineSDK, error: Error) {
        if window?.rootViewController?.presentedViewController != nil {
            window?.rootViewController?.dismiss(animated: true) { [weak self] in
                self?.flutterResult?(FlutterError(
                    code: "SDK_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
                self?.flutterResult = nil
                self?.diveOnlineSDK = nil
            }
        } else {
            flutterResult?(FlutterError(
                code: "SDK_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
            flutterResult = nil
            diveOnlineSDK = nil
        }
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
  final result = await DiveSDKService.launchDiveOnline(
    // Required fields
    token: DiveCredentials.diveOnlineToken,
    integrationId: DiveCredentials.diveOnlineIntegrationId,
    baseUrl: DiveCredentials.diveOnlineBaseUrl,
    firstName: 'John',
    lastName: 'Doe',
    // Optional fields
    phone: '+1234567890',
    email: 'john.doe@example.com',
    referenceId: 'user-12345',              // Your internal user ID
    callbackUrl: 'https://your-backend.com/webhook/dive',  // Webhook URL
  );

  switch (result) {
    case DiveSuccess(:final requestKey, :final fullResult):
      print('Verification successful! Attempt ID: $requestKey');

      // Access verification details
      if (fullResult != null) {
        final status = fullResult['validationStatus'];
        final fields = fullResult['documentFields'];

        print('Document valid: ${status['documentIsValid']}');
        print('Face valid: ${status['faceIsValid']}');
        print('First name: ${fields['FirstName']}');
        print('Anti-Spoofing valid: ${status['antiSpoofingIsValid']}');
      }
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

### Applicant Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | Yes | API authentication token |
| `integrationId` | Yes | Your DIVE Online integration identifier |
| `baseUrl` | Yes | DIVE Online API endpoint |
| `firstName` | Yes | Applicant's first name |
| `lastName` | Yes | Applicant's last name |
| `phone` | No | Applicant's phone number (for SMS notifications) |
| `email` | No | Applicant's email address |
| `referenceId` | No | Your internal reference ID to link verification with your system |
| `callbackUrl` | No | Webhook URL to receive verification status updates |

---

## Troubleshooting

### Configuration Error: Document List Empty

If you encounter this error:

```
DIVE SDK Error: Configuration error: document list is empty or document models are wrong in config
```

**Solution:**

1. Go to [DIVE Online Bundles](https://diveonline.idscan.net/bundles)
2. Find your bundle (integration)
3. Open the bundle settings
4. Click **"Accept Settings"** button
5. Restart the verification flow

This error occurs when the bundle configuration hasn't been finalized or document models need to be re-accepted after changes.

---

## Applicant Creation

### Production Architecture

In production, **never create applicants from the mobile app**. Your backend should:

1. Receive verification request from mobile app
2. Create applicant using private key (`sk_*`)
3. Return `applicantId` to mobile app
4. Mobile app launches SDK with `applicantId`

Details: [DIVE Online API Manual](https://docs.idscan.net/dive/dive-online/api-manual.html)

---

## Additional Resources

- [DIVE SDK Android](https://github.com/IDScanNet/DIVE-SDK-Android)
- [DIVE SDK iOS](https://github.com/IDScanNet/DIVE-SDK-iOS)
- [IDScan.net Developer Docs](https://docs.idscan.net/dive/index.html)
