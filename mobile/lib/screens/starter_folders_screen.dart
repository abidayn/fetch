import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Right after sign-up: "What do you save most?" One question that visibly
/// changes the app, and can be skipped. The picks become folders (one
/// POST /folders each); with none, Fetch proposes folder names as you save.
class StarterFoldersScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onDone;
  const StarterFoldersScreen({super.key, required this.apiClient, required this.onDone});

  @override
  State<StarterFoldersScreen> createState() => _StarterFoldersScreenState();
}

class _StarterFoldersScreenState extends State<StarterFoldersScreen> {
  static const _options = ['Recipes', 'Workouts', 'Coding', 'Travel', 'Career', 'Shopping', 'Reading', 'Music', 'Home'];
  final _picked = <String>{};
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    for (final name in _options.where(_picked.contains)) {
      try {
        await widget.apiClient.createFolder(name);
      } on ApiException {
        // Already exists (409) or a blip: the rest still get made, and the
        // user can add any missing one later.
      }
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _picked.length;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 16),
              Text('What do you save most?', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Fetch starts you with these as folders. Rename or delete them any time.',
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in _options)
                  FilterChip(
                    label: Text(o),
                    selected: _picked.contains(o),
                    onSelected: _busy ? null : (sel) => setState(() => sel ? _picked.add(o) : _picked.remove(o)),
                  ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton(
                onPressed: n == 0 || _busy ? null : _continue,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Continue with $n folder${n == 1 ? '' : 's'}'),
              ),
              TextButton(onPressed: _busy ? null : widget.onDone, child: const Text("Skip, I'll make my own")),
            ]),
          ),
        ]),
      ),
    );
  }
}
