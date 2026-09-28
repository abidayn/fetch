import 'package:flutter/material.dart';

/// The square platform mark on rows, the item menu and item detail. There
/// are no thumbnails (the backend stores no image URLs), so the platform is
/// the visual anchor. Placeholder colours until the redesign.
class PlatformBadge extends StatelessWidget {
  /// Item.platformKey: 'youtube' | 'tiktok' | 'instagram' | 'web'.
  final String platform;
  final double size;
  const PlatformBadge({super.key, required this.platform, this.size = 44});

  static IconData iconFor(String platform) => switch (platform) {
        'youtube' => Icons.smart_display_outlined,
        'tiktok' => Icons.music_note_outlined,
        'instagram' => Icons.camera_alt_outlined,
        _ => Icons.public,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = switch (platform) {
      'youtube' => scheme.primaryContainer,
      'tiktok' => scheme.tertiaryContainer,
      'instagram' => scheme.secondaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.25)),
      child: Icon(iconFor(platform), size: size * 0.55, color: scheme.onSurface),
    );
  }
}
