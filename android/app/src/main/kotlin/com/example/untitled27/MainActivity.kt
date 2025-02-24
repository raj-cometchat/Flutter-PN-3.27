package com.example.untitled27

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity()
//{
//    private val CHANNEL = "com.example.untitled27"
//
//    fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        super.configureFlutterEngine(flutterEngine)
//        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
//            if (call.method == "getAppInfo") {
//                val appInfo = getAppInfo()
//                result.success(appInfo)
//            } else {
//                result.notImplemented()
//            }
//        }
//    }
//
//    private fun getAppInfo(): String {
//        return "Android ${Build.VERSION.RELEASE}"
//    }
//}