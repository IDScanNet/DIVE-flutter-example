package com.example.dive_demo_usage

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.example.dive_demo_usage/dive_sdk"
    private val cameraPermissionCode = 1001

    private var methodChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null

    // Pending parameters for SDK launch
    private var pendingToken: String? = null
    private var pendingLicenseKey: String? = null
    private var pendingIntegrationId: String? = null
    private var pendingBaseUrl: String? = null
    private var pendingFirstName: String? = null
    private var pendingLastName: String? = null
    private var pendingPhone: String? = null
    private var isOnlineMode: Boolean = false

    /** DIVE SDK capture-only mode: VerificationMode.Standalone, no network */
    private var isStandaloneMode: Boolean = false

    // Activity result launcher for DiveSDKActivity
    private lateinit var diveSDKLauncher: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register activity result launcher
        diveSDKLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            handleSDKResult(result.resultCode, result.data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchDive" -> {
                    val token = call.argument<String>("token")
                    val licenseKey = call.argument<String>("licenseKey")

                    if (token == null || licenseKey == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "Token and licenseKey are required",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    pendingResult = result
                    pendingToken = token
                    pendingLicenseKey = licenseKey
                    isOnlineMode = false
                    isStandaloneMode = call.argument<Boolean>("standalone") ?: false

                    checkCameraPermissionAndLaunch()
                }
                "launchDiveOnline" -> {
                    val token = call.argument<String>("token")
                    val integrationId = call.argument<String>("integrationId")
                    val baseUrl = call.argument<String>("baseUrl")
                    val firstName = call.argument<String>("firstName")
                    val lastName = call.argument<String>("lastName")
                    val phone = call.argument<String>("phone")

                    if (token == null || integrationId == null || baseUrl == null ||
                        firstName == null || lastName == null || phone == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "Token, integrationId, baseUrl, firstName, lastName, and phone are required",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    pendingResult = result
                    pendingToken = token
                    pendingIntegrationId = integrationId
                    pendingBaseUrl = baseUrl
                    pendingFirstName = firstName
                    pendingLastName = lastName
                    pendingPhone = phone
                    isOnlineMode = true
                    isStandaloneMode = false

                    checkCameraPermissionAndLaunch()
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkCameraPermissionAndLaunch() {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            launchDiveSDKActivity()
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
                launchDiveSDKActivity()
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

    private fun launchDiveSDKActivity() {
        val intent = Intent(this, DiveSDKActivity::class.java).apply {
            if (isOnlineMode) {
                putExtra(DiveSDKActivity.EXTRA_MODE, DiveSDKActivity.MODE_ONLINE)
                putExtra(DiveSDKActivity.EXTRA_TOKEN, pendingToken)
                putExtra(DiveSDKActivity.EXTRA_INTEGRATION_ID, pendingIntegrationId)
                putExtra(DiveSDKActivity.EXTRA_BASE_URL, pendingBaseUrl)
                putExtra(DiveSDKActivity.EXTRA_FIRST_NAME, pendingFirstName)
                putExtra(DiveSDKActivity.EXTRA_LAST_NAME, pendingLastName)
                putExtra(DiveSDKActivity.EXTRA_PHONE, pendingPhone)
            } else {
                putExtra(
                    DiveSDKActivity.EXTRA_MODE,
                    if (isStandaloneMode) DiveSDKActivity.MODE_STANDALONE
                    else DiveSDKActivity.MODE_OFFLINE
                )
                putExtra(DiveSDKActivity.EXTRA_TOKEN, pendingToken)
                putExtra(DiveSDKActivity.EXTRA_LICENSE_KEY, pendingLicenseKey)
            }
        }

        diveSDKLauncher.launch(intent)
    }

    private fun handleSDKResult(resultCode: Int, data: Intent?) {
        // Standalone (capture-only) payload is handed over in-process, not
        // through the Intent — base64 scans would exceed the Binder limit.
        // Always drain it so a cancelled run can't leak into the next one.
        val standaloneResult = DiveSDKActivity.pendingStandaloneResult
        DiveSDKActivity.pendingStandaloneResult = null

        when (resultCode) {
            Activity.RESULT_OK -> {
                if (isStandaloneMode) {
                    if (standaloneResult != null) {
                        pendingResult?.success(
                            mapOf(
                                "success" to true,
                                "requestKey" to "",
                                "fullResult" to standaloneResult
                            )
                        )
                    } else {
                        pendingResult?.error(
                            "MISSING_DATA",
                            "Captured data was lost before it reached Flutter",
                            null
                        )
                    }
                    clearPendingState()
                    return
                }

                val requestKey = data?.getStringExtra(DiveSDKActivity.RESULT_REQUEST_KEY)

                @Suppress("UNCHECKED_CAST")
                val fullResult = data?.getSerializableExtra(DiveSDKActivity.RESULT_FULL_RESULT) as? HashMap<String, Any>

                if (fullResult != null) {
                    // Online mode result
                    pendingResult?.success(
                        mapOf(
                            "success" to true,
                            "requestKey" to requestKey,
                            "fullResult" to fullResult
                        )
                    )
                } else {
                    // DIVE SDK server mode result
                    pendingResult?.success(
                        mapOf(
                            "success" to true,
                            "requestKey" to requestKey
                        )
                    )
                }
            }
            Activity.RESULT_CANCELED -> {
                val errorCode = data?.getStringExtra(DiveSDKActivity.RESULT_ERROR_CODE) ?: "CANCELLED"
                val errorMessage = data?.getStringExtra(DiveSDKActivity.RESULT_ERROR_MESSAGE) ?: "Operation cancelled"

                pendingResult?.error(errorCode, errorMessage, null)
            }
        }
        clearPendingState()
    }

    private fun clearPendingState() {
        pendingResult = null
        pendingToken = null
        pendingLicenseKey = null
        pendingIntegrationId = null
        pendingBaseUrl = null
        pendingFirstName = null
        pendingLastName = null
        pendingPhone = null
        isOnlineMode = false
        isStandaloneMode = false
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        clearPendingState()
        super.onDestroy()
    }
}
