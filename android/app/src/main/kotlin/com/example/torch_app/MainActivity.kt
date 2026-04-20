package com.example.torch_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vibrationChannel = "torch_app/vibration"
    private val torchChannel = "torch_app/torch"
    private val batteryChannel = "torch_app/battery"
    private val voiceChannel = "torch_app/voice"
    private val microphoneRequestCode = 72

    private lateinit var voiceMethodChannel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceListening = false
    private var pendingVoicePermissionResult: MethodChannel.Result? = null

    private val cameraManager: CameraManager by lazy {
        getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    private val torchCameraId: String? by lazy {
        cameraManager.cameraIdList.firstOrNull { cameraId ->
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            val isBackCamera =
                characteristics.get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK

            hasFlash && isBackCamera
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, vibrationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "click" -> {
                        vibrateClick()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torchChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBrightness" -> {
                        val brightness =
                            (call.argument<Double>("brightness") ?: 1.0).coerceIn(0.2, 1.0)
                        setTorchBrightness(brightness)
                        result.success(null)
                    }
                    "disable" -> {
                        disableTorch()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryPercent" -> result.success(getBatteryPercent())
                    else -> result.notImplemented()
                }
            }

        voiceMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
        voiceMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> startVoiceListening(result)
                "stopListening" -> {
                    stopVoiceListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != microphoneRequestCode) {
            return
        }

        val pendingResult = pendingVoicePermissionResult ?: return
        pendingVoicePermissionResult = null

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startVoiceListening(pendingResult)
        } else {
            pendingResult.error("MIC_PERMISSION_DENIED", "Microphone permission was denied.", null)
        }
    }

    override fun onDestroy() {
        stopVoiceListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        super.onDestroy()
    }

    private fun vibrateClick() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        if (!vibrator.hasVibrator()) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(
                    80,
                    VibrationEffect.DEFAULT_AMPLITUDE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(80)
        }
    }

    private fun setTorchBrightness(brightness: Double) {
        val cameraId = torchCameraId ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val maxLevel =
                characteristics.get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 1

            if (maxLevel > 1) {
                val level = (brightness * maxLevel).toInt().coerceIn(1, maxLevel)
                cameraManager.turnOnTorchWithStrengthLevel(cameraId, level)
                return
            }
        }

        cameraManager.setTorchMode(cameraId, true)
    }

    private fun disableTorch() {
        val cameraId = torchCameraId ?: return
        cameraManager.setTorchMode(cameraId, false)
    }

    private fun getBatteryPercent(): Int? {
        val batteryStatus: Intent =
            registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)

        if (level < 0 || scale <= 0) {
            return null
        }

        return (level * 100 / scale).coerceIn(0, 100)
    }

    private fun startVoiceListening(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingVoicePermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphoneRequestCode)
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("VOICE_UNAVAILABLE", "Speech recognition is not available.", null)
            return
        }

        voiceListening = true
        ensureSpeechRecognizer()
        listenForVoiceCommand()
        result.success(null)
    }

    private fun stopVoiceListening() {
        voiceListening = false
        mainHandler.removeCallbacksAndMessages(null)
        speechRecognizer?.stopListening()
        speechRecognizer?.cancel()
    }

    private fun ensureSpeechRecognizer() {
        if (speechRecognizer != null) {
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = handleSpeech(partialResults)
                override fun onEvent(eventType: Int, params: Bundle?) = Unit

                override fun onError(error: Int) {
                    restartVoiceListening()
                }

                override fun onResults(results: Bundle?) {
                    handleSpeech(results)
                    restartVoiceListening()
                }
            })
        }
    }

    private fun listenForVoiceCommand() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
        }

        speechRecognizer?.startListening(intent)
    }

    private fun restartVoiceListening() {
        if (!voiceListening) {
            return
        }

        mainHandler.postDelayed({ listenForVoiceCommand() }, 450)
    }

    private fun handleSpeech(results: Bundle?) {
        val matches = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?: return

        val phrase = matches.joinToString(" ").lowercase()
        val command = when {
            phrase.contains("lumos") || phrase.contains("light on") -> "on"
            phrase.contains("nox") || phrase.contains("turn off") || phrase.contains("light off") -> "off"
            else -> return
        }

        voiceMethodChannel.invokeMethod(
            "voiceCommand",
            mapOf(
                "command" to command,
                "phrase" to phrase,
            ),
        )
    }
}
