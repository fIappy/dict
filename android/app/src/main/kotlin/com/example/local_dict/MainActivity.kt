package com.example.local_dict

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipInputStream

/**
 * The numbers module speaks whole numbers through the device's own speech
 * synthesis ([android.speech.tts.TextToSpeech]) instead of playing its word
 * recordings one after another: recorded words keep each word's citation form,
 * so "24" comes out as "twenty … four" rather than "twenty-four".
 *
 * Dart reaches this through the `local_dict/sentence_voice` channel:
 *  - `voices`  -> the engine's installed voices
 *  - `speak`   -> speaks one utterance, answering when it has finished sounding
 *  - `stop`    -> silences whatever is speaking
 *
 * and through `local_dict/bundled_models`:
 *  - `install` -> unpacks the Piper voices that ship inside the APK
 *
 * The engine initialises asynchronously, and `voices` can arrive before it is
 * ready — that call is therefore parked and answered from the init callback
 * rather than failing.
 */
class MainActivity : FlutterActivity() {
    private var engine: TextToSpeech? = null
    @Volatile
    private var ready = false
    private val parkedVoices = mutableListOf<MethodChannel.Result>()
    private val speaking = ConcurrentHashMap<String, MethodChannel.Result>()
    private val modelsLock = Any()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        engine = TextToSpeech(this) { status ->
            val ok = status == TextToSpeech.SUCCESS
            if (ok) {
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        val pending = utteranceId?.let { speaking.remove(it) } ?: return
                        runOnUiThread { pending.success(true) }
                    }

                    @Deprecated("Superseded by onError(String, Int), still called on old engines")
                    override fun onError(utteranceId: String?) {
                        val pending = utteranceId?.let { speaking.remove(it) } ?: return
                        runOnUiThread { pending.success(false) }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        val pending = utteranceId?.let { speaking.remove(it) } ?: return
                        runOnUiThread { pending.success(false) }
                    }
                })
            }
            runOnUiThread {
                ready = ok
                val list = voiceList()
                val parked = parkedVoices.toList()
                parkedVoices.clear()
                parked.forEach { it.success(list) }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "voices" -> if (ready) result.success(voiceList()) else parkedVoices.add(result)
                    "speak" -> speak(
                        text = call.argument<String>("text").orEmpty(),
                        voiceName = call.argument<String>("voice"),
                        language = call.argument<String>("language"),
                        rate = (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        volume = (call.argument<Double>("volume") ?: 1.0).toFloat(),
                        result = result,
                    )
                    "stop" -> {
                        engine?.stop()
                        val keys = speaking.keys.toList()
                        keys.forEach { key ->
                            speaking.remove(key)?.success(false)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MODELS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Off the main thread: 45 MB of archive takes a moment on a
                    // phone and the first launch must not freeze.
                    "install" -> Thread {
                        val installed = installBundledModels()
                        runOnUiThread { result.success(installed) }
                    }.start()
                    else -> result.notImplemented()
                }
            }

        // Playback has to outlive the app being on screen: this service is what
        // keeps Android from freezing the process mid-clip.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startAudioBackground()
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, AudioBackgroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Starts the media-playback foreground service.
     *
     * Android 12+ throws ForegroundServiceStartNotAllowedException if the app
     * transitions to the background right as playback advances to the next clip.
     */
    private fun startAudioBackground() {
        val intent = Intent(this, AudioBackgroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            // Best-effort keepalive when in the foreground; ignore background start restriction.
            return
        }
        // Android 13+ hides the notification when this is not granted; the
        // service itself still runs, so a refusal is not fatal.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
        }
    }

    /**
     * Unpacks the Kokoro model that travels inside the APK into app storage,
     * where the Dart side looks for it.
     *
     * Unpacks into a temporary directory first and writes a `.complete` marker
     * after atomic promotion so an interrupted extraction cannot leave a
     * broken partial model behind.
     */
    private fun installBundledModels(): Boolean = synchronized(modelsLock) {
        val root = File(filesDir, "tts-models/kokoro")
        val marker = File(root, ".complete")
        if (marker.isFile && File(root, "model.onnx").isFile && File(root, "voices.bin").isFile) {
            return true
        }
        val staging = File(filesDir, "tts-models/kokoro.staging.${UUID.randomUUID()}")
        return try {
            val stagingPath = staging.canonicalPath + File.separator
            assets.open(MODELS_ASSET).use { input ->
                ZipInputStream(input).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        val target = File(staging, entry.name).canonicalFile
                        // A path escaping the archive is refused, not written.
                        if (!target.path.startsWith(stagingPath)) continue
                        if (entry.isDirectory) {
                            target.mkdirs()
                        } else {
                            target.parentFile?.mkdirs()
                            target.outputStream().use { out -> zip.copyTo(out) }
                        }
                    }
                }
            }
            if (root.exists()) root.deleteRecursively()
            staging.parentFile?.mkdirs()
            if (!staging.renameTo(root)) {
                return false
            }
            marker.writeText("ok")
            true
        } catch (e: Exception) {
            staging.deleteRecursively()
            false
        }
    }

    /**
     * The installed voices, each with the tag Dart matches accents on and whether
     * it can speak without the network (a cloud voice would break the offline
     * promise the recordings exist for).
     */
    private fun voiceList(): List<Map<String, Any>> {
        val voices = engine?.voices ?: return emptyList()
        return voices.map { voice ->
            mapOf(
                "name" to voice.name,
                "language" to voice.locale.toLanguageTag(),
                "offline" to !voice.isNetworkConnectionRequired,
            )
        }
    }

    private fun speak(
        text: String,
        voiceName: String?,
        language: String?,
        rate: Float,
        volume: Float,
        result: MethodChannel.Result,
    ) {
        val tts = engine
        if (!ready || tts == null || text.isBlank()) {
            result.success(false)
            return
        }

        val voice = voicesByName(voiceName)
        if (voice != null) {
            tts.voice = voice
        } else {
            val locale = language?.takeIf { it.isNotBlank() }?.let(Locale::forLanguageTag)
            if (locale == null || tts.isLanguageAvailable(locale) < TextToSpeech.LANG_AVAILABLE) {
                // No usable language installed: answer false so the recordings speak.
                result.success(false)
                return
            }
            tts.language = locale
        }

        tts.setSpeechRate(rate.coerceIn(0.1f, 3.0f))
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume.coerceIn(0.0f, 1.0f))
        }
        val utteranceId = UUID.randomUUID().toString()
        speaking[utteranceId] = result
        val queued = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        if (queued != TextToSpeech.SUCCESS) {
            speaking.remove(utteranceId)
            result.success(false)
        }
    }

    private fun voicesByName(name: String?) =
        name?.takeIf { it.isNotBlank() }?.let { wanted ->
            engine?.voices?.firstOrNull { it.name == wanted }
        }

    override fun onDestroy() {
        parkedVoices.forEach { it.success(emptyList<Map<String, Any>>()) }
        parkedVoices.clear()
        val keys = speaking.keys.toList()
        keys.forEach { key -> speaking.remove(key)?.success(false) }
        engine?.stop()
        engine?.shutdown()
        engine = null
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "local_dict/sentence_voice"
        const val MODELS_CHANNEL = "local_dict/bundled_models"
        const val MODELS_ASSET = "kokoro.zip"
        const val AUDIO_BACKGROUND_CHANNEL = "local_dict/audio_background"
        const val NOTIFICATION_REQUEST = 4211
    }
}
