package com.example.kaimono

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import dalvik.system.DexClassLoader
import java.io.File
import com.google.gson.Gson

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.kaimono/keiyoshi"
    private val extensionCache = mutableMapOf<String, Any>()
    private val gson = Gson()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchPopular" -> {
                    val apkPath = call.argument<String>("apkPath")!!
                    val className = call.argument<String>("className")!!
                    val page = call.argument<Int>("page") ?: 1

                    Thread {
                        try {
                            val jsonResponse = executeExtensionFetch(apkPath, className, page)
                            runOnUiThread { result.success(jsonResponse) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXT_ERROR", e.message, e.stackTraceToString()) }
                        }
                    }.start()
                }
                "fetchChapters" -> {
                    val apkPath = call.argument<String>("apkPath")!!
                    val className = call.argument<String>("className")!!
                    val entryUrl = call.argument<String>("entryUrl")!!

                    Thread {
                        try {
                            val jsonResponse = executeChapterFetch(apkPath, className, entryUrl)
                            runOnUiThread { result.success(jsonResponse) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXT_ERROR", e.message, e.stackTraceToString()) }
                        }
                    }.start()
                }
                "fetchPages" -> {
                    val apkPath = call.argument<String>("apkPath")!!
                    val className = call.argument<String>("className")!!
                    val chapterUrl = call.argument<String>("chapterUrl")!!

                    Thread {
                        try {
                            val jsonResponse = executePageFetch(apkPath, className, chapterUrl)
                            runOnUiThread { result.success(jsonResponse) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXT_ERROR", e.message, e.stackTraceToString()) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun executeExtensionFetch(apkPath: String, className: String, page: Int): String {
        val instance = loadExtensionInstance(apkPath, className)
        val sourceClass = instance.javaClass
        
        val fetchMethod = sourceClass.methods.find { it.name == "fetchPopularManga" }
            ?: throw Exception("Method fetchPopularManga not found in extension")
        
        val response = fetchMethod.invoke(instance, page)
        return gson.toJson(response)
    }

    private fun executeChapterFetch(apkPath: String, className: String, entryUrl: String): String {
        val instance = loadExtensionInstance(apkPath, className)
        val sourceClass = instance.javaClass
        
        // Tachiyomi extensions typically use fetchChapterList or similar signatures
        val fetchMethod = sourceClass.methods.find { it.name == "fetchChapterList" || it.name == "getChapterList" }
            ?: throw Exception("Chapter list method not found in extension")
        
        // Depending on the signature, we pass the entry URL or a stub SAn/SManga object
        val response = fetchMethod.invoke(instance, entryUrl)
        return gson.toJson(response)
    }

    private fun executePageFetch(apkPath: String, className: String, chapterUrl: String): String {
        val instance = loadExtensionInstance(apkPath, className)
        val sourceClass = instance.javaClass
        
        val fetchMethod = sourceClass.methods.find { it.name == "fetchPageList" || it.name == "getPageList" }
            ?: throw Exception("Page list method not found in extension")
        
        val response = fetchMethod.invoke(instance, chapterUrl)
        return gson.toJson(response)
    }

    private fun loadExtensionInstance(apkPath: String, className: String): Any {
        if (extensionCache.containsKey(className)) {
            return extensionCache[className]!!
        }

        val apkFile = File(apkPath)
        if (!apkFile.exists()) throw Exception("APK not found at $apkPath")

        val optimizedDir = context.codeCacheDir
        val classLoader = DexClassLoader(
            apkFile.absolutePath,
            optimizedDir.absolutePath,
            null,
            context.classLoader 
        )

        val sourceClass = classLoader.loadClass(className)
        val instance = sourceClass.getDeclaredConstructor().newInstance()
        
        extensionCache[className] = instance
        return instance
    }
}
