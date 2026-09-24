import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';

/// Tampilkan umpan balik setelah link tersimpan: "Saved — AI is organizing
/// this…" lalu berubah jadi hasil AI begitu pengayaan di backend selesai.
///
/// Copy sengaja Bahasa Inggris (keputusan user, 2026-09-21), walau sisa UI
/// masih Bahasa Indonesia.
Future<void> showSaveResultSheet(BuildContext context, ApiClient apiClient, Item item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _SaveResultSheet(apiClient: apiClient, initial: item),
  );
}

class _SaveResultSheet extends StatefulWidget {
  final ApiClient apiClient;
  final Item initial;
  const _SaveResultSheet({required this.apiClient, required this.initial});

  @override
  State<_SaveResultSheet> createState() => _SaveResultSheetState();
}

class _SaveResultSheetState extends State<_SaveResultSheet> {
  // Pengayaan normalnya 4-9 detik, tapi bisa ~20 detik kalau Gemini sedang
  // retry (429/503). Lewat 60 detik, sheet berhenti menunggu -- item tetap
  // akan ter-update sendiri di daftar home.
  static const _pollInterval = Duration(seconds: 3);
  static const _maxWait = Duration(seconds: 60);

  late Item _item = widget.initial;
  final _started = DateTime.now();
  Timer? _timer;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    if (!_item.processed) _schedulePoll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _timer = Timer(_pollInterval, _poll);
  }

  Future<void> _poll() async {
    try {
      final fresh = Item.fromJson(await widget.apiClient.getItem(_item.id));
      if (!mounted) return;
      setState(() => _item = fresh);
    } catch (_) {
      // Gangguan jaringan sesaat: coba lagi di putaran berikutnya.
    }
    if (!mounted || _item.processed) return;
    if (DateTime.now().difference(_started) >= _maxWait) {
      setState(() => _gaveUp = true);
    } else {
      _schedulePoll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _item.processed;
    final hasSummary = _item.summary != null;

    final String heading;
    final Widget body;
    if (!done && !_gaveUp) {
      heading = 'Saved';
      body = Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text('AI is organizing this…', style: theme.textTheme.bodyMedium)),
      ]);
    } else if (!done) {
      heading = 'Saved';
      body = Text(
        "Still organizing — it'll update in your list when it's ready.",
        style: theme.textTheme.bodyMedium,
      );
    } else if (hasSummary) {
      heading = _item.category != null ? 'Saved to ${_item.category}' : 'Saved';
      body = Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_item.displayTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(_item.summary!, style: theme.textTheme.bodyMedium),
          ]),
        ),
      );
    } else if (_item.hasContent) {
      // Isi link terbaca, tapi Gemini gagal (kuota/timeout). Bisa diulang
      // di backend (backfill_enrichment.py) -- beda dari link tak terbaca.
      heading = 'Saved';
      body = Text(
        "Saved, but the AI summary didn't come through this time. "
        'You can add a title and summary yourself via Edit.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      // Sudah diproses tapi kontennya tidak terbaca (post privat/terhapus, dll).
      heading = 'Saved';
      body = Text(
        "Couldn't read much from this link, so it's saved as-is.",
        style: theme.textTheme.bodyMedium,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(heading, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              _item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            body,
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
