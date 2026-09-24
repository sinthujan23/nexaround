package com.nexaround.nexaround_app

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.facebook.share.model.ShareLinkContent
import com.facebook.share.widget.ShareDialog
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val SIGNATURE_CHANNEL = "com.nexaround.app/signature"
    private val APP_SHARE_CHANNEL = "com.nexaround.app/share"
    private val SOCIAL_SHARE_CHANNEL = "com.nexaround.app/social_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_SHARE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "shareToApp") {
                try {
                    result.success(
                        shareToApp(
                            call.argument<String>("package")!,
                            call.argument<ByteArray>("image"),
                            call.argument<String>("mimeType") ?: "image/jpeg",
                            call.argument<String>("text"),
                            call.argument<String>("title") ?: "Share",
                        )
                    )
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOCIAL_SHARE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "facebookLink" -> {
                        val url = call.argument<String>("url")
                        result.success(url != null && shareToFacebook(url))
                    }
                    "instagramStory" -> {
                        val image = call.argument<ByteArray>("image")
                        result.success(image != null && shareToInstagramStory(image))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIGNATURE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSignatureSha1") {
                try {
                    val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                    }

                    val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.signingInfo?.apkContentsSigners
                    } else {
                        @Suppress("DEPRECATION")
                        packageInfo.signatures
                    }

                    if (certs != null && certs.isNotEmpty()) {
                        val md = MessageDigest.getInstance("SHA-1")
                        val sha1Bytes = md.digest(certs[0].toByteArray())
                        val sha1 = sha1Bytes.joinToString(":") { String.format("%02X", it) }
                        result.success(sha1)
                    } else {
                        result.success("UNKNOWN")
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /** Facebook's share dialog: the Facebook app's post screen when it is
     *  installed, Facebook's web dialog when it is not. */
    private fun shareToFacebook(url: String): Boolean {
        if (!ShareDialog.canShow(ShareLinkContent::class.java)) return false
        val content = ShareLinkContent.Builder().setContentUrl(Uri.parse(url)).build()
        ShareDialog(this).show(content)
        return true
    }

    /** Instagram's "Sharing to Stories": a new story with [image] as a sticker
     *  on a brand-colour background. Instagram needs the Facebook App ID as
     *  the source and a content URI it is allowed to read. */
    private fun shareToInstagramStory(image: ByteArray): Boolean {
        val dir = File(cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "story.jpg").apply { writeBytes(image) }
        val uri = FileProvider.getUriForFile(this, "$packageName.shareprovider", file)

        val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
            putExtra("source_application", getString(R.string.facebook_app_id))
            type = "image/*"
            putExtra("interactive_asset_uri", uri)
            putExtra("top_background_color", "#00A3A6")
            putExtra("bottom_background_color", "#005E60")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (packageManager.resolveActivity(intent, 0) == null) return false
        startActivity(intent)
        return true
    }

    /**
     * Hands [image] (or [text] alone) to one app with a plain ACTION_SEND, the
     * way the system share sheet does. The receiving app then offers its own
     * choices: Instagram lists Feed, Stories and Chats as separate targets, X
     * lists Post and Direct Message, so when [pkg] has more than one we show a
     * chooser limited to that app. Returns false when the app isn't installed.
     */
    private fun shareToApp(
        pkg: String,
        image: ByteArray?,
        mimeType: String,
        text: String?,
        title: String,
    ): Boolean {
        val send = Intent(Intent.ACTION_SEND).setPackage(pkg)
        if (image != null) {
            val dir = File(cacheDir, "share").apply { mkdirs() }
            val ext = if (mimeType == "image/png") "png" else "jpg"
            val file = File(dir, "nexaround_share.$ext").apply { writeBytes(image) }
            val uri = FileProvider.getUriForFile(this, "$packageName.shareimages", file)
            send.type = mimeType
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.clipData = ClipData.newRawUri(null, uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            send.type = "text/plain"
        }
        if (text != null) send.putExtra(Intent.EXTRA_TEXT, text)

        val targets = packageManager.queryIntentActivities(send, 0)
        if (targets.isEmpty()) return false
        startActivity(if (targets.size == 1) send else Intent.createChooser(send, title))
        return true
    }
}
