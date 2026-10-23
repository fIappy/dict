package com.example.local_dict

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID
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
    private var ready = false
    private var parkedVoices: MethodChannel.Result? = null
    private val speaking = HashMap<String, MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        engine = TextToSpeech(this) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        speaking.remove(utteranceId)?.success(true)
                    }

                    @Deprecated("Superseded by onError(String, Int), still called on old engines")
                    override fun onError(utteranceId: String?) {
                        speaking.remove(utteranceId)?.success(false)
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        speaking.remove(utteranceId)?.success(false)
                    }
                })
            }
            parkedVoices?.let { parked ->
                parkedVoices = null
                parked.success(voiceList())
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "voices" -> if (ready) result.success(voiceList()) else parkedVoices = result
                    "speak" -> speak(
                        text = call.argument<String>("text").orEmpty(),
                        voiceName = call.argument<String>("voice"),
                        language = call.argument<String>("language"),
                        rate = (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        result = result,
                    )
                    "stop" -> {
                        engine?.stop()
                        speaking.values.forEach { it.success(false) }
                        speaking.clear()
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
     * Only ever called while the app is visible — playback starts from the UI,
     * which is the one moment Android allows a foreground service to be started.
     */
    private fun startAudioBackground() {
        val intent = Intent(this, AudioBackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
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
     * Scoped storage keeps the app from reading a model another tool wrote into
     * its data directory, and a phone that never touches a computer cannot import
     * one either — so the archive ships in the APK and is unpacked here. Its
     * files land under `files/tts-models/kokoro/`, the layout `findKokoroModel`
     * probes. Idempotent: with the model already unpacked it does nothing and
     * answers true.
     */
    private fun installBundledModels(): Boolean {
        val root = File(filesDir, "tts-models/kokoro")
        if (File(root, "model.onnx").isFile && File(root, "voices.bin").isFile) return true
        val rootPath = root.canonicalPath + File.separator
        return try {
            assets.open(MODELS_ASSET).use { input ->
                ZipInputStream(input).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        val target = File(root, entry.name).canonicalFile
                        // A path escaping the archive is refused, not written.
                        if (!target.path.startsWith(rootPath)) continue
                        if (entry.isDirectory) {
                            target.mkdirs()
                        } else {
                            target.parentFile?.mkdirs()
                            target.outputStream().use { out -> zip.copyTo(out) }
                        }
                    }
                }
            }
            true
        } catch (e: Exception) {
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
        val utteranceId = UUID.randomUUID().toString()
        speaking[utteranceId] = result
        val queued = tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
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
        speaking.values.forEach { it.success(false) }
        speaking.clear()
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
