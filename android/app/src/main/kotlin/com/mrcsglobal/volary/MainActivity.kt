package com.mrcsglobal.volary

import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.mrcsglobal.volary/sound"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "playTimerChime") {
                try {
                    mediaPlayer?.release()
                    mediaPlayer = null

                    val player = MediaPlayer().apply {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                                .build()
                        )
                    }

                    try {
                        val afd: AssetFileDescriptor = context.assets.openFd("flutter_assets/assets/sounds/timer_chime.wav")
                        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                        afd.close()
                    } catch (e: Exception) {
                        val input = context.assets.open("flutter_assets/assets/sounds/timer_chime.wav")
                        val tempFile = java.io.File(context.cacheDir, "timer_chime.wav")
                        tempFile.outputStream().use { input.copyTo(it) }
                        input.close()
                        player.setDataSource(tempFile.absolutePath)
                    }

                    player.setOnCompletionListener {
                        it.release()
                        if (mediaPlayer == it) {
                            mediaPlayer = null
                        }
                    }
                    player.prepare()
                    player.start()
                    mediaPlayer = player
                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }
}
