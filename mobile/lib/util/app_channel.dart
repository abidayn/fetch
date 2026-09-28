import 'package:flutter/services.dart';

/// The one native call Fetch needs: "Back to TikTok" on the save sheet sends
/// Fetch to the background, which returns the user to the app they shared
/// from (Android keeps it right below in the task stack). Implemented in
/// MainActivity.kt with moveTaskToBack.
const _channel = MethodChannel('fetch/app');

/// Returns false if it couldn't (e.g. not on Android) -- the caller then just
/// closes the sheet.
Future<bool> moveAppToBack() async {
  try {
    return await _channel.invokeMethod<bool>('moveToBack') ?? false;
  } catch (_) {
    return false;
  }
}
