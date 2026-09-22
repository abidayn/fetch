import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Buka link item di app asalnya.
///
/// `externalApplication` = serahkan ke Android, bukan buka WebView di dalam
/// Fetch. Android lalu mencocokkan URL dengan "app link" yang didaftarkan app
/// lain: link youtube.com terbuka di app YouTube, tiktok.com di TikTok, dst.
/// Kalau app-nya tidak terpasang, Android jatuh ke browser default.
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null && uri.hasScheme) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false; // mis. tidak ada app sama sekali yang bisa membuka link ini
    }
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link tidak bisa dibuka.')),
    );
  }
}
