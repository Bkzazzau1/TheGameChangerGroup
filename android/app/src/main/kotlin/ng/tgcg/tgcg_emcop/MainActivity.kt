package ng.tgcg.tgcg_emcop

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A picture from a video for the Social Forum (lib/tgcg/media/video_poster_io.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tgcg/video_poster")
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                if (call.method != "poster" || path == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val main = Handler(Looper.getMainLooper())
                Thread {
                    val poster = try {
                        posterOf(path)
                    } catch (error: Exception) {
                        null
                    }
                    main.post { result.success(poster) }
                }.start()
            }
    }

    /** A frame about a second in (upright, at most 720 pixels), the video's size and length. */
    private fun posterOf(path: String): Map<String, Any>? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            // A second in, or a tenth of a shorter clip (in microseconds).
            val at = min(1_000_000L, duration * 100L)
            val frame = retriever.getFrameAtTime(at, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            val scale = min(1.0, 720.0 / max(frame.width, frame.height))
            val small = if (scale < 1.0) {
                Bitmap.createScaledBitmap(
                    frame,
                    (frame.width * scale).roundToInt(),
                    (frame.height * scale).roundToInt(),
                    true,
                )
            } else {
                frame
            }
            val jpeg = ByteArrayOutputStream()
            small.compress(Bitmap.CompressFormat.JPEG, 80, jpeg)
            return mapOf(
                "jpeg" to jpeg.toByteArray(),
                "width" to frame.width,
                "height" to frame.height,
                "durationMs" to duration,
            )
        } finally {
            runCatching { retriever.release() }
        }
    }
}
