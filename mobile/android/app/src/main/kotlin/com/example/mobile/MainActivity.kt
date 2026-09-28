package com.example.mobile

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // installSplashScreen() is called explicitly (instead of relying on
    // Flutter's implicit mechanism) to fix the splash screen freezing forever
    // when this Activity is created via Android's share-sheet trampoline
    // (ACTION_SEND) rather than a launcher tap. It ties dismissal to the
    // Activity's first draw at the Android level, consistent across every
    // launch path -- not to Flutter's first-frame detection, which doesn't
    // always fire on that trampoline path.
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    // "Back to TikTok" on the save sheet (lib/util/app_channel.dart): send
    // Fetch to the background, which returns the user to the app they shared
    // from -- it sits right below Fetch in the task stack.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fetch/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
    }
}
