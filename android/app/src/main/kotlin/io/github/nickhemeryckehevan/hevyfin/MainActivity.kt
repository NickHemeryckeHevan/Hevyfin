package io.github.nickhemeryckehevan.hevyfin

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.speech.RecognizerIntent
import android.view.WindowManager
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Picture-in-picture: while the player is open, leaving the app shrinks the video
/// into a floating mini player instead of stopping it. The mini player has
/// back 10 s, play/pause and forward 10 s buttons, which are passed to Dart.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pipEnabled = false
    private var aspect = Rational(16, 9)
    private var playing = true

    /// Links opened from outside (Google TV's Continue watching row): hevyfin://play/<id>.
    private var linkChannel: MethodChannel? = null
    private var pendingLink: String? = null

    /// Waiting for the voice input activity to hand back what was said.
    private var voiceResult: MethodChannel.Result? = null

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.getStringExtra(EXTRA_ACTION) ?: return
            channel?.invokeMethod("action", action)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = intent?.dataString?.takeIf { it.startsWith("hevyfin://") }
        val filter = IntentFilter(ACTION_PIP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(actionReceiver, filter)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = intent.dataString?.takeIf { it.startsWith("hevyfin://") } ?: return
        linkChannel?.invokeMethod("open", link) ?: run { pendingLink = link }
    }

    override fun onDestroy() {
        unregisterReceiver(actionReceiver)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android TV / Google TV gets the remote-driven interface.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hevyfin/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK))
                // Surround formats the TV or soundbar on HDMI takes as they are (passthrough).
                "passthrough" -> result.success(passthrough())
                // The TV screensaver keeps the screen on while it shows the library.
                "keepScreenOn" -> {
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        linkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hevyfin/link").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // The link the app was opened with, once.
                    "initial" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    "watchNext" -> {
                        @Suppress("UNCHECKED_CAST")
                        val items = (call.arguments as? List<Map<String, Any?>>) ?: emptyList()
                        Thread {
                            try {
                                WatchNext.sync(this@MainActivity, items)
                            } catch (e: Exception) {
                                android.util.Log.w("hevyfin", "watch next: $e")
                            }
                        }.start()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Voice search: Android's own speech input (the remote's mic on a Google TV).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hevyfin/voice").setMethodCallHandler { call, result ->
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT, call.argument<String>("prompt") ?: "Say a title")
            when (call.method) {
                "available" -> result.success(intent.resolveActivity(packageManager) != null)
                "listen" -> {
                    voiceResult?.success(null)
                    voiceResult = result
                    try {
                        startActivityForResult(intent, VOICE_REQUEST)
                    } catch (e: Exception) {
                        voiceResult = null
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hevyfin/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        pipEnabled = call.argument<Boolean>("enabled") ?: false
                        val w = call.argument<Int>("width") ?: 16
                        val h = call.argument<Int>("height") ?: 9
                        // Android only accepts ratios between 1:2.39 and 2.39:1.
                        aspect = Rational(w, h).let {
                            when {
                                it.toFloat() > 2.39f -> Rational(239, 100)
                                it.toFloat() < 1 / 2.39f -> Rational(100, 239)
                                else -> it
                            }
                        }
                        updateParams()
                        result.success(null)
                    }
                    "setPlaying" -> {
                        playing = call.arguments as? Boolean ?: true
                        updateParams()
                        result.success(null)
                    }
                    "enter" -> result.success(enterPip())
                    else -> result.notImplemented()
                }
            }
        }
    }

    /// mpv's names for the compressed formats the HDMI output accepts, from its EDID.
    private fun passthrough(): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        val hdmi = setOf(
            android.media.AudioDeviceInfo.TYPE_HDMI,
            android.media.AudioDeviceInfo.TYPE_HDMI_ARC,
        ) + if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setOf(android.media.AudioDeviceInfo.TYPE_HDMI_EARC) else emptySet()
        val encodings = am.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type in hdmi }
            .flatMap { it.encodings.toList() }
            .toSet()
        val names = mapOf(
            android.media.AudioFormat.ENCODING_AC3 to "ac3",
            android.media.AudioFormat.ENCODING_E_AC3 to "eac3",
            android.media.AudioFormat.ENCODING_DTS to "dts",
        )
        return names.filterKeys { it in encodings }.values.toList()
    }

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(aspect).setActions(
            listOf(
                remote("back", R.drawable.ic_pip_replay, "Back 10 seconds", 1),
                if (playing) remote("toggle", R.drawable.ic_pip_pause, "Pause", 2) else remote("toggle", R.drawable.ic_pip_play, "Play", 2),
                remote("forward", R.drawable.ic_pip_forward, "Forward 10 seconds", 3),
            ),
        )
        // Android 12+: go to PiP smoothly on the home gesture.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) b.setAutoEnterEnabled(pipEnabled).setSeamlessResizeEnabled(true)
        return b.build()
    }

    private fun updateParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) params()?.let { setPictureInPictureParams(it) }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(params()!!)
        } catch (e: IllegalStateException) {
            false
        }
    }

    // Older Android (8–11) has no auto-enter, so do it when the user leaves.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEnabled && Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S) enterPip()
    }

    @Deprecated("Flutter's activity still delivers results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VOICE_REQUEST) {
            val heard = if (resultCode == RESULT_OK) data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null
            voiceResult?.success(heard)
            voiceResult = null
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("changed", isInPictureInPictureMode)
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.O)
    private fun remote(action: String, icon: Int, title: String, code: Int): RemoteAction {
        val intent = Intent(ACTION_PIP).setPackage(packageName).putExtra(EXTRA_ACTION, action)
        val pending = PendingIntent.getBroadcast(this, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pending)
    }

    companion object {
        private const val ACTION_PIP = "io.github.nickhemeryckehevan.hevyfin.PIP_ACTION"
        private const val EXTRA_ACTION = "action"
        private const val VOICE_REQUEST = 4711
    }
}
