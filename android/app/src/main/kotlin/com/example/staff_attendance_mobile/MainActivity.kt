package com.example.staff_attendance_mobile

import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.UnrecoverableKeyException
import java.security.InvalidKeyException
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executor

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "staff_attendance/secure_signing"
    private val keyAlias = "staff_attendance_signing_key_v1"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attendance/clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "elapsedRealtime") {
                    result.success(SystemClock.elapsedRealtime())
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canSign" -> {
                        try {
                            val authenticators =
                                BiometricManager.Authenticators.BIOMETRIC_STRONG
                            result.success(
                                BiometricManager.from(this).canAuthenticate(authenticators) ==
                                    BiometricManager.BIOMETRIC_SUCCESS
                            )
                        } catch (error: Exception) {
                            logNativeFailure("canSign", error)
                            result.error(
                                "BIOMETRIC_UNAVAILABLE",
                                "Strong biometric authentication is unavailable.",
                                null
                            )
                        }
                    }
                    "createKey" -> {
                        try {
                            val replaceExisting = call.argument<Boolean>("replaceExisting") ?: false
                            result.success(mapOf("publicKey" to createKeyPair(replaceExisting)))
                        } catch (error: Exception) {
                            logNativeFailure("createKey", error)
                            result.error(
                                nativeErrorCode(error, "KEY_CREATION_FAILED"),
                                userMessageFor("KEY_CREATION_FAILED"),
                                null
                            )
                        }
                    }
                    "generateNewKeyPairString" -> {
                        try {
                            result.success(generateNewRsaKeyPair())
                        } catch (error: Exception) {
                            logNativeFailure("generateNewKeyPairString", error)
                            result.error(
                                nativeErrorCode(error, "KEY_CREATION_FAILED"),
                                userMessageFor("KEY_CREATION_FAILED"),
                                null
                            )
                        }
                    }
                    "deviceUuid" -> {
                        val deviceUuid = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID
                        )
                        if (deviceUuid.isNullOrBlank()) {
                            result.error(
                                "DEVICE_ID_UNAVAILABLE",
                                "The Android device identifier is unavailable.",
                                null
                            )
                        } else {
                            result.success(deviceUuid)
                        }
                    }
                    "sign" -> {
                        val message = call.argument<String>("message")
                        if (message.isNullOrEmpty() || message.length > 4096) {
                            result.error("INVALID_MESSAGE", "Signing data is invalid.", null)
                        } else {
                            signWithBiometrics(message, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createKeyPair(replaceExisting: Boolean): String {
        val keyStore = loadKeyStore()
        val existing = keyStore.getCertificate(keyAlias)
        if (existing != null && !replaceExisting) {
            return pem(existing.publicKey.encoded)
        }
        if (existing != null) keyStore.deleteEntry(keyAlias)

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG
            )
        } else {
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        generator.initialize(builder.build())
        val publicKey = generator.generateKeyPair().public
        return pem(publicKey.encoded)
    }

    private fun generateNewRsaKeyPair(): String {
        val keyStore = loadKeyStore()
        keyStore.deleteEntry(keyAlias)

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG
            )
        } else {
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        generator.initialize(builder.build())
        val publicKey = generator.generateKeyPair().public
        return Base64.getEncoder().encodeToString(publicKey.encoded)
    }

    private fun signWithBiometrics(message: String, result: MethodChannel.Result) {
        val completed = AtomicBoolean(false)

        try {
            val keyStore = loadKeyStore()
            val privateKey = keyStore.getKey(keyAlias, null) as? java.security.PrivateKey
            if (privateKey == null) {
                completeOnce(completed) {
                    result.error(
                        "DEVICE_NOT_ENROLLED",
                        "This device has no secure signing key.",
                        null
                    )
                }
                return
            }

            val signatureAlgorithm = when (privateKey.algorithm) {
                KeyProperties.KEY_ALGORITHM_EC -> "SHA256withECDSA"
                KeyProperties.KEY_ALGORITHM_RSA -> "SHA256withRSA"
                else -> throw InvalidKeyException("Unsupported signing key algorithm.")
            }
            val signature = Signature.getInstance(signatureAlgorithm)
            signature.initSign(privateKey)
            val executor: Executor = ContextCompat.getMainExecutor(this)
            val prompt = BiometricPrompt(
                this,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authenticationResult: BiometricPrompt.AuthenticationResult
                    ) {
                        completeOnce(completed) {
                            try {
                                val authorizedSignature =
                                    authenticationResult.cryptoObject?.signature
                                        ?: throw IllegalStateException(
                                            "Biometric signing was not authorized."
                                        )
                                authorizedSignature.update(message.toByteArray(Charsets.UTF_8))
                                result.success(
                                    mapOf(
                                        "signature" to Base64.getEncoder()
                                            .encodeToString(authorizedSignature.sign())
                                    )
                                )
                            } catch (error: Exception) {
                                logNativeFailure("sign", error)
                                result.error(
                                    nativeErrorCode(error, "SIGNING_FAILED"),
                                    userMessageFor("SIGNING_FAILED"),
                                    null
                                )
                            }
                        }
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        completeOnce(completed) {
                            val code = when (errorCode) {
                                BiometricPrompt.ERROR_USER_CANCELED,
                                BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                                BiometricPrompt.ERROR_CANCELED -> "BIOMETRIC_CANCELLED"
                                BiometricPrompt.ERROR_NO_BIOMETRICS -> "BIOMETRIC_NOT_ENROLLED"
                                BiometricPrompt.ERROR_HW_NOT_PRESENT,
                                BiometricPrompt.ERROR_HW_UNAVAILABLE ->
                                    "BIOMETRIC_UNAVAILABLE"
                                BiometricPrompt.ERROR_LOCKOUT -> "BIOMETRIC_LOCKOUT"
                                BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                                    "BIOMETRIC_LOCKOUT_PERMANENT"
                                else -> "BIOMETRIC_FAILED"
                            }
                            result.error(code, userMessageFor(code), null)
                        }
                    }

                    override fun onAuthenticationFailed() {
                        // BiometricPrompt remains active for another attempt.
                    }
                }
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Confirm attendance")
                .setSubtitle("Authenticate to securely sign this attendance action")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                .setNegativeButtonText("Cancel")
                .build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(signature))
        } catch (error: Exception) {
            logNativeFailure("sign", error)
            completeOnce(completed) {
                result.error(
                    nativeErrorCode(error, "SIGNING_FAILED"),
                    userMessageFor("SIGNING_FAILED"),
                    null
                )
            }
        }
    }

    private fun loadKeyStore(): KeyStore {
        return KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }

    private fun pem(encodedKey: ByteArray): String {
        val body = Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(encodedKey)
        return "-----BEGIN PUBLIC KEY-----\n$body\n-----END PUBLIC KEY-----"
    }

    private fun nativeErrorCode(error: Exception, fallback: String): String =
        if (error is InvalidKeyException || error is UnrecoverableKeyException) {
            "KEY_INVALIDATED"
        } else {
            fallback
        }

    private fun userMessageFor(code: String): String =
        when (code) {
            "BIOMETRIC_CANCELLED" ->
                "Biometric confirmation was cancelled."
            "BIOMETRIC_NOT_ENROLLED" ->
                "Set up a strong fingerprint or face biometric in Android Settings, then try again."
            "BIOMETRIC_UNAVAILABLE" ->
                "Strong biometric authentication is unavailable on this device. Try again later or use a supported device."
            "BIOMETRIC_LOCKOUT" ->
                "Biometric authentication is temporarily locked. Wait and try again."
            "BIOMETRIC_LOCKOUT_PERMANENT" ->
                "Biometric authentication is locked. Unlock the device with its screen lock, then try again."
            "DEVICE_NOT_ENROLLED" ->
                "This device has no secure signing key."
            "KEY_INVALIDATED" ->
                "The device signing key is no longer available. Contact your administrator for secure device recovery."
            "KEY_CREATION_FAILED" ->
                "A secure signing key could not be created on this device."
            else -> "Secure biometric signing could not be completed."
        }

    private fun logNativeFailure(operation: String, error: Exception) {
        if (BuildConfig.DEBUG) {
            Log.e(
                "StaffDeviceSecurity",
                "$operation failed (${error.javaClass.simpleName})",
                error
            )
        }
    }

    private inline fun completeOnce(
        completed: AtomicBoolean,
        completion: () -> Unit
    ) {
        if (completed.compareAndSet(false, true)) completion()
    }
}
