package com.carriez.flutter_hbb

/**
 * All neodesk-specific Android plumbing, kept OUT of RustDesk's [MainActivity]
 * so the upstream Activity stays close to vanilla and is easy to re-merge when
 * RustDesk updates. [MainActivity] only registers this bridge and forwards a few
 * Activity-lifecycle callbacks (`dispatchKeyEvent`, `onActivityResult`,
 * `onPictureInPictureModeChanged`) to it — everything else lives here.
 *
 * Channels:
 *  - `neodesk/pip`       enter picture-in-picture; pushes "changed".
 *  - `neodesk/volkey`    intercept volume keys; pushes "key" per press.
 *  - `neodesk/installapk` launch the package installer on a downloaded APK.
 *  - `neodesk/applock`   confirm device credential; toggle FLAG_SECURE.
 */

import android.app.Activity
import android.app.KeyguardManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.util.Rational
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class NeodeskBridge(private val activity: FlutterActivity) {
    companion object {
        private const val logTag = "NeodeskBridge"
        const val REQ_APP_LOCK = 0xA10C
    }

    private var pipChannel: MethodChannel? = null
    private var volkeyChannel: MethodChannel? = null
    private var appLockResult: MethodChannel.Result? = null

    @Volatile private var interceptVolUp = false
    @Volatile private var interceptVolDown = false

    /// Register the neodesk method channels on the Flutter engine.
    fun configureChannels(messenger: BinaryMessenger) {
        // Picture-in-picture (Moonlight-style small window): Flutter calls "enter".
        pipChannel = MethodChannel(messenger, "neodesk/pip").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "enter") result.success(enterPip())
                else result.notImplemented()
            }
        }
        // Volume-key interception: Flutter calls "set" {up,down}.
        volkeyChannel = MethodChannel(messenger, "neodesk/volkey").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    interceptVolUp = call.argument<Boolean>("up") ?: false
                    interceptVolDown = call.argument<Boolean>("down") ?: false
                    result.success(null)
                } else result.notImplemented()
            }
        }
        // In-app update: launch the system package installer on a downloaded APK.
        MethodChannel(messenger, "neodesk/installapk").setMethodCallHandler { call, result ->
            if (call.method == "install") {
                val path = call.argument<String>("path")
                result.success(if (path != null) installApk(path) else false)
            } else result.notImplemented()
        }
        // App lock: confirm the device credential, and a privacy flag for recents.
        MethodChannel(messenger, "neodesk/applock").setMethodCallHandler { call, result ->
            when (call.method) {
                "authenticate" -> authenticateAppLock(result)
                "setSecure" -> {
                    setSecure(call.argument<Boolean>("secure") ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---- Activity lifecycle forwards (called from MainActivity) ----

    /// Returns true if the key was a mapped volume key (forwarded + consumed).
    fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val dir = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> if (interceptVolUp) "up" else null
            KeyEvent.KEYCODE_VOLUME_DOWN -> if (interceptVolDown) "down" else null
            else -> null
        } ?: return false
        val phase = when {
            event.action == KeyEvent.ACTION_UP -> "up"
            event.repeatCount > 0 -> "repeat"
            else -> "down"
        }
        activity.runOnUiThread {
            volkeyChannel?.invokeMethod("key", mapOf("key" to dir, "phase" to phase))
        }
        return true
    }

    /// Returns true if [requestCode] was the app-lock request (consumed).
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQ_APP_LOCK) return false
        appLockResult?.success(resultCode == Activity.RESULT_OK)
        appLockResult = null
        return true
    }

    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        activity.runOnUiThread {
            pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
        }
    }

    // ---- Implementations ----

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            activity.enterPictureInPictureMode(params)
        } catch (e: Exception) {
            Log.e(logTag, "enterPip failed: ${e.message}", e)
            false
        }
    }

    // Launch the system package installer on a downloaded APK (via a FileProvider
    // content:// URI). The user is prompted to allow "install unknown apps" the
    // first time. Returns false if the intent couldn't be started.
    private fun installApk(path: String): Boolean {
        return try {
            val uri = FileProvider.getUriForFile(
                activity, "${activity.packageName}.fileprovider", File(path))
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(logTag, "installApk failed: ${e.message}", e)
            false
        }
    }

    // App lock: prompt the system credential confirmation (biometric / PIN /
    // pattern). Resolves the channel with false if the device has no secure lock
    // set, or when the user cancels.
    private fun authenticateAppLock(result: MethodChannel.Result) {
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val secure = if (Build.VERSION.SDK_INT >= 23) km.isDeviceSecure else km.isKeyguardSecure
        if (!secure) { result.success(false); return }
        val intent = km.createConfirmDeviceCredentialIntent(
            "Unlock NeoDesk", "Confirm your identity to continue")
        if (intent == null) { result.success(false); return }
        appLockResult?.success(false) // resolve any stale pending request
        appLockResult = result
        activity.startActivityForResult(intent, REQ_APP_LOCK)
    }

    // Privacy: while the app lock is on, mark the window secure so the remote
    // content is excluded from the recent-apps thumbnail / screenshots.
    private fun setSecure(on: Boolean) {
        activity.runOnUiThread {
            if (on) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }
}
