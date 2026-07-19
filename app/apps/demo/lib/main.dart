import 'dart:io' show Platform;

import 'package:demo_app/demo_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (kDebugMode && !isFlutterTest) {
    final logCollector = PrintLogCollector();
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: logCollector),
    );

    final defaultDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        logCollector.addLog(message);
      }
      defaultDebugPrint(message, wrapWidth: wrapWidth);
    };
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const DemoApp());
}
