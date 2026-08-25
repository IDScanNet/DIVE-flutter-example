package com.example.dive_demo_usage

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import androidx.appcompat.app.AppCompatActivity
import net.idscan.components.android.dvs.*
import net.idscan.components.android.dvs.capture.CaptureConfig
import net.idscan.components.android.dvs.common.DocumentType
import net.idscan.components.android.dvs.net.VerificationConfig
import net.idscan.components.android.dvs.net.VerificationData
import net.idscan.components.android.dvs.net.VerificationRequest
import net.idscan.components.android.dvsonline.DvsOnlineConfig
import net.idscan.components.android.dvsonline.DvsOnlineException
import net.idscan.components.android.dvsonline.DvsOnlineFragment
import net.idscan.components.android.dvsonline.net.ApplicantInfo
import net.idscan.components.android.dvsonline.net.DvsOnlineClient
import net.idscan.components.android.dvsonline.net.ValidationResult
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Dedicated Activity for DIVE SDK with custom Material Design theme.
 * This activity hosts DvsFragment and DvsOnlineFragment with the Theme.DiveDemo styling.
 *
 * Must be an [AppCompatActivity], not a plain FragmentActivity: the SDK's layouts
 * declare their buttons as framework `<Button>` tags carrying Material attributes
 * (`style="?materialButtonStyle"`, `app:icon`) and rely on AppCompat's
 * MaterialComponentsViewInflater to inflate them as MaterialButton. Without the
 * AppCompat delegate that substitution never happens, so Theme.DiveDemo's button
 * styling (backgroundTint, cornerRadius, rippleColor, textAppearance) is silently
 * dropped and the SDK renders with default platform buttons.
 */
class DiveSDKActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_MODE = "mode"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_LICENSE_KEY = "licenseKey"
        const val EXTRA_INTEGRATION_ID = "integrationId"
        const val EXTRA_BASE_URL = "baseUrl"
        const val EXTRA_FIRST_NAME = "firstName"
        const val EXTRA_LAST_NAME = "lastName"
        const val EXTRA_PHONE = "phone"

        /** DIVE SDK, VerificationMode.Server — uploads and returns a request id */
        const val MODE_OFFLINE = "offline"

        /** DIVE SDK, VerificationMode.Standalone — captures on device, no network */
        const val MODE_STANDALONE = "standalone"

        /** DIVE Online SDK */
        const val MODE_ONLINE = "online"

        const val RESULT_REQUEST_KEY = "requestKey"
        const val RESULT_FULL_RESULT = "fullResult"
        const val RESULT_ERROR_CODE = "errorCode"
        const val RESULT_ERROR_MESSAGE = "errorMessage"

        /**
         * Standalone (capture-only) payload handover.
         *
         * It carries three base64 JPEGs and would blow past the ~1MB Binder
         * transaction limit if passed through the result Intent, so it is
         * handed over in-process instead. MainActivity drains it on RESULT_OK.
         */
        @Volatile
        var pendingStandaloneResult: HashMap<String, Any>? = null
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup fragment result listeners
        setupResultListeners()

        // Only launch SDK if this is a fresh start (not a configuration change)
        if (savedInstanceState == null) {
            launchSDK()
        }
    }

    private fun setupResultListeners() {
        // Setup fragment result listener for DvsFragment.
        // All DvsFragment callbacks must be registered in a single call: the
        // listener is keyed by DvsFragment.REQUEST_KEY, so a second
        // setFragmentResultListener() call would silently replace the first.
        DvsFragment.setFragmentResultListener(
            supportFragmentManager,
            this,
            DvsFragment.SuccessCallback { /* VerificationMode.Local only, unused */ },
            DvsFragment.RequestCallback { request -> handleDvsRequestResult(request) },
            DvsFragment.VerificationDataCallback { _, data -> handleDvsVerificationData(data) },
            DvsFragment.ErrorCallback { error -> handleDvsError(error) }
        )

        // Setup fragment result listener for DvsOnlineFragment
        DvsOnlineFragment.setFragmentResultListener(
            supportFragmentManager,
            this,
            { result -> handleDvsOnlineResult(result) },
            { error -> handleDvsOnlineError(error) }
        )
    }

    private fun launchSDK() {
        val mode = intent.getStringExtra(EXTRA_MODE)

        when (mode) {
            MODE_OFFLINE -> launchOfflineSDK(VerificationMode.Server)
            MODE_STANDALONE -> launchOfflineSDK(VerificationMode.Standalone)
            MODE_ONLINE -> launchOnlineSDK()
            else -> {
                finishWithError("INVALID_MODE", "Unknown SDK mode: $mode")
            }
        }
    }

    /**
     * Launches the DIVE SDK (non-online) capture flow.
     *
     * [verificationMode] selects what happens after capture:
     * - [VerificationMode.Server] uploads the data and returns a request id
     * - [VerificationMode.Standalone] returns the captured data locally and
     *   never touches the network
     */
    private fun launchOfflineSDK(verificationMode: VerificationMode) {
        val token = intent.getStringExtra(EXTRA_TOKEN)
        val licenseKey = intent.getStringExtra(EXTRA_LICENSE_KEY)

        if (token == null || licenseKey == null) {
            finishWithError("CONFIGURATION_ERROR", "Missing token or license key")
            return
        }

        try {
            val captureConfig = CaptureConfig.builder(licenseKey)
                .withPreviewAnimations(true)
                .withShowDocumentTypeSelector(false)
                .withAutoStart(false)
                .showSubmitBtn(true)
                .withDocumentType(DocumentType.DriverLicense)
                    .withFront(true, true)
                    .withBack(true, true)
                    .withFace(true, true, true)
                    .complete()
                .withDocumentType(DocumentType.Passport)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                .withDocumentType(DocumentType.PassportCard)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
                .withDocumentType(DocumentType.GreenCard)
                    .withFront(true, true)
                    .withFace(true, true, false)
                    .complete()
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
                verificationMode
            ).build()

            val dvsFragment = DvsFragment.newInstance(config)

            supportFragmentManager.beginTransaction()
                .replace(android.R.id.content, dvsFragment, "DVS_FRAGMENT")
                .commit()

        } catch (e: Exception) {
            finishWithError("SDK_ERROR", "Failed to launch DIVE SDK: ${e.message}")
        }
    }

    private fun launchOnlineSDK() {
        val token = intent.getStringExtra(EXTRA_TOKEN)
        val integrationId = intent.getStringExtra(EXTRA_INTEGRATION_ID)
        val baseUrl = intent.getStringExtra(EXTRA_BASE_URL)
        val firstName = intent.getStringExtra(EXTRA_FIRST_NAME)
        val lastName = intent.getStringExtra(EXTRA_LAST_NAME)
        val phone = intent.getStringExtra(EXTRA_PHONE)

        if (token == null || integrationId == null || baseUrl == null ||
            firstName == null || lastName == null || phone == null) {
            finishWithError("CONFIGURATION_ERROR", "Missing required parameters for DIVE Online SDK")
            return
        }

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
                    phone,
                    "",
                    "",
                    false
                )

                val callResult = client.createApplicant(applicantInfo).execute()

                if (callResult.isSuccess && callResult.result != null) {
                    val applicantId = callResult.result!!
                    mainHandler.post {
                        showDvsOnlineFragment(token, integrationId, applicantId, baseUrl)
                    }
                } else {
                    val errorMessage = callResult.error?.toString() ?: "Failed to create applicant"
                    mainHandler.post {
                        finishWithError("APPLICANT_CREATION_ERROR", errorMessage)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    finishWithError("APPLICANT_CREATION_ERROR", "Failed to create applicant: ${e.message}")
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
                "IDScan"
            )
                .withCustomUrl(baseUrl)
                .build()

            val fragment = DvsOnlineFragment.newInstance(config)

            supportFragmentManager.beginTransaction()
                .setPrimaryNavigationFragment(fragment)
                .replace(android.R.id.content, fragment, "DVS_ONLINE_FRAGMENT")
                .commit()

        } catch (e: Exception) {
            finishWithError("SDK_ERROR", "Failed to launch DIVE Online SDK: ${e.message}")
        }
    }

    private fun handleDvsRequestResult(request: VerificationRequest) {
        val resultIntent = Intent().apply {
            putExtra(RESULT_REQUEST_KEY, request.requestId)
        }
        setResult(Activity.RESULT_OK, resultIntent)
        finish()
    }

    /**
     * VerificationMode.Standalone result: everything the SDK produced on the
     * device, with nothing sent anywhere. There are no verification fields
     * here — only scans, the raw PDF417/MRZ string and the document type.
     */
    private fun handleDvsVerificationData(data: VerificationData) {
        try {
            val payload = HashMap<String, Any>().apply {
                put("mode", "standalone")
                put("documentType", data.documentType.name)
                data.trackString?.let { put("trackString", it) }
                data.frontImage?.toJpegBase64()?.let { put("frontImageBase64", it) }
                data.backImage?.toJpegBase64()?.let { put("backImageBase64", it) }
                data.faceImage?.toJpegBase64()?.let { put("faceImageBase64", it) }
                put("captureMethod", ArrayList(data.captureMethod.map { it.name }))
            }

            pendingStandaloneResult = payload
            setResult(Activity.RESULT_OK, Intent())
            finish()

        } catch (e: Exception) {
            finishWithError("RESULT_PROCESSING_ERROR", "Error processing captured data: ${e.message}")
        }
    }

    /**
     * Encodes a captured bitmap as a JPEG base64 string for the method channel.
     *
     * NO_WRAP matters: Dart's base64Decode rejects line breaks. Downscaling
     * keeps the payload small enough to cross the channel comfortably.
     */
    private fun Bitmap.toJpegBase64(maxDimension: Int = 1024, quality: Int = 80): String? {
        val scale = maxDimension.toFloat() / maxOf(width, height)
        val scaled = if (scale < 1f) {
            Bitmap.createScaledBitmap(this, (width * scale).toInt(), (height * scale).toInt(), true)
        } else {
            this
        }

        return try {
            ByteArrayOutputStream().use { stream ->
                scaled.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
            }
        } finally {
            if (scaled !== this) scaled.recycle()
        }
    }

    private fun handleDvsError(error: DvsException) {
        finishWithError("SDK_ERROR", error.message ?: "Unknown SDK error")
    }

    private fun handleDvsOnlineResult(result: ValidationResult) {
        try {
            val fieldsMap = HashMap<String, String>()
            result.documentFields.forEach { (key, value) ->
                fieldsMap[key.name] = value
            }

            val validationStatusMap = HashMap<String, Any>().apply {
                put("code", result.validationStatus.code.name)
                put("documentIsValid", result.validationStatus.documentIsValid as Any)
                put("isExpired", result.validationStatus.isExpired as Any)
                put("faceIsValid", result.validationStatus.faceIsValid as Any)
                put("antiSpoofingIsValid", result.validationStatus.antiSpoofingIsValid as Any)
            }

            val fullResultMap = HashMap<String, Any>().apply {
                put("attemptId", result.attemptId)
                put("attemptsLeft", result.attemptsLeft)
                put("documentType", result.documentType.name)
                put("validationStatus", validationStatusMap)
                put("documentFields", fieldsMap)
            }

            val resultIntent = Intent().apply {
                putExtra(RESULT_REQUEST_KEY, result.attemptId.toString())
                putExtra(RESULT_FULL_RESULT, fullResultMap)
            }
            setResult(Activity.RESULT_OK, resultIntent)
            finish()

        } catch (e: Exception) {
            finishWithError("RESULT_PROCESSING_ERROR", "Error processing result: ${e.message}")
        }
    }

    private fun handleDvsOnlineError(error: DvsOnlineException) {
        finishWithError("SDK_ERROR", error.message ?: "Unknown DIVE Online SDK error")
    }

    private fun finishWithError(code: String, message: String) {
        val resultIntent = Intent().apply {
            putExtra(RESULT_ERROR_CODE, code)
            putExtra(RESULT_ERROR_MESSAGE, message)
        }
        setResult(Activity.RESULT_CANCELED, resultIntent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        @Suppress("DEPRECATION")
        super.onBackPressed()
        finishWithError("USER_CANCELLED", "User cancelled the operation")
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
