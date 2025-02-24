import 'package:flutter/services.dart';
Map<String, String> info = {};
class GetInfo{

  // get app info
  static Future<Map<String, String>> initAppInfo() async {
    try {
      final Map<String, String> appInfo = Map<String, String>.from(await const MethodChannel('com.example.untitled27').invokeMethod('getAppInfo'));
      return appInfo;
    } on PlatformException {
      return {'bundleId': "", 'version': ""};
    }
  }
}