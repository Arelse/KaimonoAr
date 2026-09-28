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

                    // Run on a background thread so the UI doesn't freeze
                    Thread {
                        try {
                            val jsonResponse = executeExtensionFetch(apkPath, className, page)
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
        
        // Find the "fetchPopularManga" method inside the loaded extension
        val fetchMethod = sourceClass.methods.find { it.name == "fetchPopularManga" }
            ?: throw Exception("Method fetchPopularManga not found in extension")
        
        // Execute the Kotlin method dynamically
        val response = fetchMethod.invoke(instance, page)

        // Convert the response to JSON text and send it back to Dart
        return gson.toJson(response)
    }

    private fun loadExtensionInstance(apkPath: String, className: String): Any {
        if (extensionCache.containsKey(className)) {
            return extensionCache[className]!!
        }

        val apkFile = File(apkPath)
        if (!apkFile.exists()) throw Exception("APK not found at $apkPath")

        // DexClassLoader extracts the bytecode from the Keiyoshi APK
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
