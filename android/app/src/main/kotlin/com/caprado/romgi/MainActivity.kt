package com.caprado.romgi

import android.content.Intent
import android.content.ComponentName
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.caprado.romgi.ncch_decrypt.NcchDecryptHostApi
import com.caprado.romgi.ncch_decrypt.NcchDecryptServiceImpl
import com.caprado.romgi.seven_zip.SevenZipHostApi
import com.caprado.romgi.seven_zip.SevenZipServiceImpl
import com.caprado.romgi.torrent.TorrentHostApi
import com.caprado.romgi.torrent.TorrentServiceImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var torrentService: TorrentServiceImpl? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val service = TorrentServiceImpl(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        torrentService = service
        TorrentHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, service)

        val sevenZipService = SevenZipServiceImpl(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        SevenZipHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, sevenZipService)

        NcchDecryptHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, NcchDecryptServiceImpl())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openWithChooser") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file,
                        )
                        // ACTION_VIEW + createChooser forces the system
                        // app picker every time, ignoring the user's
                        // saved default for this MIME type.
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "*/*")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(view, "Open with").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(null)
                    } catch (t: Throwable) {
                        result.error("OPEN_FAILED", t.message, null)
                    }
                } else if (call.method == "launchRetroArch") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists() || !file.isFile) {
                            result.error("FILE_MISSING", "content file does not exist", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file,
                        )
                        val extension = file.extension.lowercase()
                        val mime = MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(extension) ?: "application/octet-stream"
                        val packages = listOf(
                            "com.retroarch.aarch64",
                            "com.retroarch",
                            "com.retroarch.ra32",
                            "org.libretro.retroarch",
                        )
                        val retroActivity =
                            "com.retroarch.browser.retroactivity.RetroActivityFuture"

                        var launched = false
                        for (retroArchPackage in packages) {
                            val retro = Intent().apply {
                                component = ComponentName(retroArchPackage, retroActivity)
                                putExtra("ROM", file.absolutePath)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            }
                            try {
                                startActivity(retro)
                                launched = true
                                break
                            } catch (_: Throwable) {
                                // Try the next known RetroArch package.
                            }
                        }

                        // Some community builds expose only ACTION_VIEW. Keep
                        // the file-provider fallback for those variants.
                        if (!launched) {
                            val view = Intent(Intent.ACTION_VIEW).apply {
                                data = uri
                                type = mime
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                startActivity(view)
                                launched = true
                            } catch (_: Throwable) {
                                // Report the install/launch error below.
                            }
                        }

                        if (launched) {
                            result.success(null)
                        } else {
                            result.error(
                                "RETROARCH_NOT_INSTALLED",
                                "Install RetroArch before launching games",
                                null,
                            )
                        }
                    } catch (t: Throwable) {
                        result.error("RETROARCH_LAUNCH_FAILED", t.message, null)
                    }
                } else if (call.method == "getNativeLibraryDir") {
                    // pkg2zip is bundled as jniLibs/<abi>/libpkg2zip.so (a real
                    // executable, not a loadable native library) so Android's APK
                    // packaging places it here; Dart invokes it directly as a
                    // subprocess rather than through JNI. See
                    // src/main/cpp/CMakeLists.txt and
                    // lib/services/vita_decrypt_service.dart.
                    result.success(applicationInfo.nativeLibraryDir)
                } else if (call.method == "getWebViewCookies") {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("ARG", "url is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val cookies = CookieManager.getInstance().getCookie(url) ?: ""
                        result.success(cookies)
                    } catch (t: Throwable) {
                        result.error("COOKIE_FAILED", t.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        torrentService?.shutdown()
        torrentService = null
        super.onDestroy()
    }

    companion object {
        private const val OPEN_CHANNEL = "com.caprado.romgi/open"
    }
}
