package com.example.local_dict

import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

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
    }
}
