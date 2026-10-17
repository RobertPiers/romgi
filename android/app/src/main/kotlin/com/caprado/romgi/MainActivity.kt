package com.caprado.romgi

import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
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
                        val platform = call.argument<String>("platform")
                        val extension = file.extension.lowercase()
                        val mime = MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(extension) ?: "application/octet-stream"
                        val storageRoot = Environment.getExternalStorageDirectory().absolutePath
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
                            val retroApplicationInfo = try {
                                packageManager.getApplicationInfo(retroArchPackage, 0)
                            } catch (_: Throwable) {
                                null
                            }
                            val retroExternalPath =
                                "$storageRoot/Android/data/$retroArchPackage/files"
                            val retro = Intent().apply {
                                setComponent(ComponentName(retroArchPackage, retroActivity))
                                putExtra(
                                    "CONFIGFILE",
                                    "$retroExternalPath/retroarch.cfg",
                                )
                                coreNameFor(platform, extension)?.let { coreName ->
                                    putExtra(
                                        "LIBRETRO",
                                        "/data/user/0/$retroArchPackage/cores/$coreName",
                                    )
                                }
                                putExtra("ROM", file.absolutePath)
                                // These are part of RetroArch's Android launch
                                // contract. MainMenuActivity supplies them
                                // when it starts RetroActivityFuture; without
                                // them some builds show only a black surface.
                                retroApplicationInfo?.dataDir?.let {
                                    putExtra("DATADIR", it)
                                }
                                retroApplicationInfo?.sourceDir?.let {
                                    putExtra("APK", it)
                                }
                                putExtra("SDCARD", storageRoot)
                                putExtra("EXTERNAL", retroExternalPath)
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
                                setDataAndType(uri, mime)
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
                } else if (call.method == "getInstalledRetroArchCores") {
                    queryInstalledRetroArchCores(result)
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

    private fun queryInstalledRetroArchCores(result: MethodChannel.Result) {
        val packages = listOf(
            "com.retroarch.aarch64",
            "com.retroarch",
            "com.retroarch.ra32",
            "org.libretro.retroarch",
        )
        val retroArchPackage = packages.firstOrNull { packageName ->
            try {
                packageManager.getPackageInfo(packageName, 0)
                true
            } catch (_: Throwable) {
                false
            }
        }

        if (retroArchPackage == null) {
            result.success(
                mapOf("installed" to false, "known" to false, "cores" to emptyList<String>()),
            )
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var finished = false
        var registered = false
        lateinit var receiver: BroadcastReceiver
        lateinit var timeout: Runnable

        fun finish(value: Map<String, Any>) {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            if (registered) {
                try {
                    unregisterReceiver(receiver)
                } catch (_: Throwable) {
                    // The activity may already be shutting down.
                }
            }
            result.success(value)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: Intent) {
                val cores = intent.getStringArrayExtra(RETROARCH_CORES_EXTRA)
                    ?.toList()
                    ?: emptyList()
                finish(
                    mapOf(
                        "installed" to true,
                        "known" to true,
                        "cores" to cores,
                    ),
                )
            }
        }
        timeout = Runnable {
            // Older/community RetroArch builds may not include the optional
            // receiver. Preserve catalog usability when that query is absent.
            finish(
                mapOf(
                    "installed" to true,
                    "known" to false,
                    "cores" to emptyList<String>(),
                ),
            )
        }

        try {
            val filter = IntentFilter(RETROARCH_CORES_RESULT)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
            registered = true
            sendBroadcast(
                Intent(RETROARCH_CORES_QUERY).setPackage(retroArchPackage),
            )
            handler.postDelayed(timeout, CORE_QUERY_TIMEOUT_MS)
        } catch (_: Throwable) {
            finish(
                mapOf(
                    "installed" to true,
                    "known" to false,
                    "cores" to emptyList<String>(),
                ),
            )
        }
    }

    private fun coreNameFor(platform: String?, extension: String): String? {
        val normalized = (platform ?: extension).lowercase().removePrefix(".")
        return when (normalized) {
            "nes" -> "fceumm_libretro_android.so"
            "fds" -> "fceumm_libretro_android.so"
            "snes", "sfc", "smc" -> "snes9x_libretro_android.so"
            "gb" -> "gambatte_libretro_android.so"
            "gbc" -> "gambatte_libretro_android.so"
            "gba" -> "mgba_libretro_android.so"
            "vb" -> "beetle_vb_libretro_android.so"
            "n64", "v64", "z64" ->
                "mupen64plus_next_libretro_android.so"
            "nds" -> "melonds_libretro_android.so"
            "gc" -> "dolphin_libretro_android.so"
            "wii" -> "dolphin_libretro_android.so"
            "ps1" -> "swanstation_libretro_android.so"
            "psp" -> "ppsspp_libretro_android.so"
            "sms" -> "genesis_plus_gx_libretro_android.so"
            "gg" -> "genesis_plus_gx_libretro_android.so"
            "smd", "md", "gen" -> "genesis_plus_gx_libretro_android.so"
            "scd" -> "genesis_plus_gx_libretro_android.so"
            "32x" -> "picodrive_libretro_android.so"
            "sat" -> "yabause_libretro_android.so"
            "dc" -> "flycast_libretro_android.so"
            "a26" -> "stella2023_libretro_android.so"
            "a52" -> "atari800_libretro_android.so"
            "a78" -> "prosystem_libretro_android.so"
            "lynx", "lnx" -> "handy_libretro_android.so"
            "jag", "j64" -> "virtualjaguar_libretro_android.so"
            "tg16", "pce" -> "mednafen_pce_fast_libretro_android.so"
            "tgcd" -> "mednafen_pce_fast_libretro_android.so"
            "pcfx" -> "mednafen_pcfx_libretro_android.so"
            "3do" -> "opera_libretro_android.so"
            "ngcd" -> "neocd_libretro_android.so"
            else -> null
        }
    }

    companion object {
        private const val OPEN_CHANNEL = "com.caprado.romgi/open"
        private const val RETROARCH_CORES_QUERY = "com.retroarch.QUERY_INSTALLED_CORES"
        private const val RETROARCH_CORES_RESULT = "com.retroarch.INSTALLED_CORES_RESULT"
        private const val RETROARCH_CORES_EXTRA = "CORES"
        private const val CORE_QUERY_TIMEOUT_MS = 1200L
    }
}
