import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open an item's link in the app it came from.
///
/// `externalApplication` = hand it to Android, rather than opening a WebView
/// inside Fetch. Android then matches the URL against the "app links" other
/// apps registered: youtube.com links open in the YouTube app, tiktok.com in
/// TikTok, and so on. If that app isn't installed, Android falls back to the
/// default browser.
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null && uri.hasScheme) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false; // e.g. no app at all can open this link
    }
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open the link.")),
    );
  }
}
