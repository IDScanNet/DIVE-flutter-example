import Flutter
import UIKit
import DIVESDK
import DIVEOnlineSDK
import DIVESDKCommon

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var flutterResult: FlutterResult?
  private var diveSDK: DIVESDK?
  private var diveOnlineSDK: DIVEOnlineSDK?

  /// Capture-only mode: stop after capture and never call `sendData`. The iOS
  /// SDK has no VerificationMode equivalent — since `sendData` both requests
  /// verification and holds the only network call, skipping it *is* Android's
  /// Standalone mode.
  private var standaloneMode = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Setup method channel
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(
      name: "com.example.dive_demo_usage/dive_sdk",
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel?.setMethodCallHandler(handle)

    // Setup event channel for upload progress
    eventChannel = FlutterEventChannel(
      name: "com.example.dive_demo_usage/dive_sdk/upload_progress",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel?.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Method channel handler
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "launchDive":
      handleLaunchDive(call, result: result)
    case "launchDiveOnline":
      handleLaunchDiveOnline(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Handle launchDive method
  private func handleLaunchDive(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Note: [String: Any], not [String: String] — the standalone flag is a Bool
    guard let args = call.arguments as? [String: Any],
          let token = args["token"] as? String,
          let licenseKey = args["licenseKey"] as? String else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Token and licenseKey are required",
        details: nil
      ))
      return
    }

    // Store result callback
    flutterResult = result
    standaloneMode = args["standalone"] as? Bool ?? false

    // Load config JSON and replace licenseKey
    guard var config = loadJson(filename: "DiveConfig") else {
      result(FlutterError(
        code: "CONFIGURATION_ERROR",
        message: "Failed to load DiveConfig.json. Please ensure the file is added to Xcode project as a resource.",
        details: nil
      ))
      flutterResult = nil
      return
    }
    config["licenseKey"] = licenseKey

    // Create and launch SDK
    diveSDK = DIVESDK(configuration: config, token: token, delegate: self)
    let controller = window?.rootViewController as! FlutterViewController
    diveSDK?.start(from: controller)
  }

  // Handle launchDiveOnline method
  private func handleLaunchDiveOnline(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: String],
          let token = args["token"],
          let integrationId = args["integrationId"],
          let baseUrl = args["baseUrl"],
          let firstName = args["firstName"],
          let lastName = args["lastName"],
          let phone = args["phone"] else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Token, integrationId, baseUrl, firstName, lastName, and phone are required",
        details: nil
      ))
      return
    }

    // Store result callback
    flutterResult = result
    standaloneMode = false

    // Step 1: Create applicant using custom method (pattern from original demo)
    createApplicant(
      baseURL: baseUrl,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      integrationId: integrationId,
      token: token
    ) { [weak self] applicantResult in
      guard let self = self else { return }

      switch applicantResult {
      case .success(let applicantId):
        // Step 2: Create DIVEOnlineSDK instance with applicantId
        self.diveOnlineSDK = DIVEOnlineSDK(
          applicantID: applicantId,
          integrationID: integrationId,
          token: token,
          baseURL: baseUrl + "/public",
          delegate: self
        )

        // Step 3: Update location (as in original demo)
        self.diveOnlineSDK?.updateLocation()

        // Step 4: Load configuration (as in original demo)
        self.diveOnlineSDK?.loadConfiguration { [weak self] error in
          guard let self = self else { return }

          if let error = error {
            // Configuration load failed
            print("❌ Failed to load configuration: \(error.localizedDescription)")
            self.flutterResult?(FlutterError(
              code: "CONFIGURATION_ERROR",
              message: "Failed to load configuration: \(error.localizedDescription)",
              details: nil
            ))
            self.flutterResult = nil
            self.diveOnlineSDK = nil
          } else {
            // Configuration loaded successfully - now start SDK
            print("✅ Configuration loaded successfully")
            DispatchQueue.main.async {
              let controller = self.window?.rootViewController as! FlutterViewController
              self.diveOnlineSDK?.start(from: controller)
            }
          }
        }

      case .failure(let error):
        // Failed to create applicant
        print("❌ Failed to create applicant: \(error.localizedDescription)")
        self.flutterResult?(FlutterError(
          code: "APPLICANT_CREATION_ERROR",
          message: "Failed to create applicant: \(error.localizedDescription)",
          details: nil
        ))
        self.flutterResult = nil
      }
    }
  }

  // Load JSON configuration file
  private func loadJson(filename: String) -> [String: Any]? {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
      print("❌ Could not find \(filename).json in bundle")
      print("📦 Bundle path: \(Bundle.main.bundlePath)")
      if let resourcePath = Bundle.main.resourcePath {
        print("📁 Resource path: \(resourcePath)")
        do {
          let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
          print("📄 Files in bundle: \(files.filter { $0.hasSuffix(".json") })")
        } catch {
          print("❌ Could not list files: \(error)")
        }
      }
      return nil
    }

    guard let data = try? Data(contentsOf: url) else {
      print("❌ Could not read data from \(filename).json")
      return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      print("❌ Could not parse JSON from \(filename).json")
      return nil
    }

    print("✅ Successfully loaded \(filename).json")
    return json
  }
}

// DIVE SDK Delegate implementation
extension AppDelegate: DIVESDKDelegate {
  func diveSDKDataPrepaired(sdk: IDIVESDK, data: DIVESDKData) {
    // Dismiss the DIVE SDK UI once capture is done
    sdk.close()

    // Capture-only mode: return what was captured and stop here. sendData()
    // is what requests verification, and it holds the SDK's only network
    // call, so not calling it means nothing leaves the device.
    if standaloneMode {
      print("📴 DIVE SDK: Capture finished, no verification will be requested")

      var payload: [String: Any] = [
        "mode": "standalone",
        // The iOS SDK exposes the document type as a raw Int only — there is
        // no enum to map it to a name like on Android
        "documentTypeInt": data.documentType
      ]
      if let trackString = data.trackString {
        payload["trackString"] = trackString
      }
      if let front = data.frontImage?.jpegBase64() {
        payload["frontImageBase64"] = front
      }
      if let back = data.backImage?.jpegBase64() {
        payload["backImageBase64"] = back
      }
      if let face = data.faceImage?.jpegBase64() {
        payload["faceImageBase64"] = face
      }

      flutterResult?([
        "success": true,
        "requestKey": "",
        "fullResult": payload
      ])
      flutterResult = nil
      diveSDK = nil
      standaloneMode = false
      return
    }

    // Server mode: upload and wait for the verification result
    print("📤 DIVE SDK: Data prepared, sending to server...")
    sdk.sendData(data: data)
  }

  func diveSDKResult(sdk: IDIVESDK, result: [String: Any]) {
    // Extract request key and request ID from result
    let requestId = result["requestId"] as? String ?? ""
    print("✅ DIVE SDK: Success with requestId: \(requestId)")

    // Prepare result with all data
    let flutterResultData: [String: Any] = [
      "success": true,
      "requestKey": requestId,
      "fullResult": result
    ]

    // Return result to Flutter
    flutterResult?(flutterResultData)
    flutterResult = nil
    diveSDK = nil
    diveOnlineSDK = nil
    standaloneMode = false
  }

  func diveSDKError(sdk: IDIVESDK, error: Error) {
    // Log error
    print("❌ DIVE SDK Error: \(error.localizedDescription)")

    // Check if the SDK UI is still presented and dismiss if needed
    if window?.rootViewController?.presentedViewController != nil {
      window?.rootViewController?.dismiss(animated: true) { [weak self] in
        self?.flutterResult?(FlutterError(
          code: "SDK_ERROR",
          message: error.localizedDescription,
          details: nil
        ))
        self?.flutterResult = nil
        self?.diveSDK = nil
        self?.diveOnlineSDK = nil
        self?.standaloneMode = false
      }
    } else {
      // UI already dismissed, just return error
      flutterResult?(FlutterError(
        code: "SDK_ERROR",
        message: error.localizedDescription,
        details: nil
      ))
      flutterResult = nil
      diveSDK = nil
      diveOnlineSDK = nil
      standaloneMode = false
    }
  }

  func diveSDKSendingDataProgress(sdk: IDIVESDK, progress: Float, requestTime: TimeInterval) {
    // Log progress
    print("⏳ DIVE SDK: Upload progress: \(Int(progress * 100))%")

    // Send progress to Flutter via event channel
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(Double(progress))
    }
  }
}

// Image encoding for the method channel
private extension UIImage {
  /// Encodes the image as JPEG base64 for the method channel.
  ///
  /// No `data:` prefix and no line breaks: that keeps the string starting with
  /// `/9j/`, which is what the Flutter result renderer detects as an image, and
  /// Dart's `base64Decode` rejects wrapped base64. Downscaling keeps the
  /// payload small.
  func jpegBase64(maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> String? {
    let scale = maxDimension / max(size.width, size.height)
    let image: UIImage
    if scale < 1 {
      let newSize = CGSize(width: size.width * scale, height: size.height * scale)
      let renderer = UIGraphicsImageRenderer(size: newSize)
      image = renderer.image { _ in
        self.draw(in: CGRect(origin: .zero, size: newSize))
      }
    } else {
      image = self
    }

    return image.jpegData(compressionQuality: quality)?.base64EncodedString()
  }
}

// Flutter Stream Handler implementation
extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}

// Helper method to create applicant (pattern from DIVEOnlineSDK demo)
extension AppDelegate {
  private func createApplicant(
    baseURL: String,
    firstName: String,
    lastName: String,
    phone: String,
    integrationId: String,
    token: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    // Create URL for applicant creation endpoint
    let urlString = baseURL + "/private/Applicants"
    guard let url = URL(string: urlString) else {
      completion(.failure(NSError(
        domain: "AppDelegate",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"]
      )))
      return
    }

    // Create request
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    // Create request body
    let body: [String: Any] = [
      "integrationId": integrationId,
      "firstName": firstName,
      "lastName": lastName,
      "phone": phone
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      completion(.failure(error))
      return
    }

    // Make network request
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let data = data else {
        completion(.failure(NSError(
          domain: "AppDelegate",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "No data received"]
        )))
        return
      }

      // Check HTTP response
      if let httpResponse = response as? HTTPURLResponse {
        guard (200...299).contains(httpResponse.statusCode) else {
          let errorMessage = "HTTP Error: \(httpResponse.statusCode)"
          completion(.failure(NSError(
            domain: "AppDelegate",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
          )))
          return
        }
      }

      // Parse JSON response
      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let applicantId = json["applicantId"] as? String {
          completion(.success(applicantId))
        } else {
          completion(.failure(NSError(
            domain: "AppDelegate",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "applicantId not found in response"]
          )))
        }
      } catch {
        completion(.failure(error))
      }
    }

    task.resume()
  }
}
