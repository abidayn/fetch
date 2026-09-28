import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Paste a link": the fallback when an app has no share-to-Fetch button.
/// Returns the link to save, or null if closed. The http(s) check happens
/// here so the backend never stores something that can't be opened.
Future<String?> showPasteSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PasteSheet(),
  );
}

class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _ctrl.text = text);
  }

  void _submit() {
    final url = _ctrl.text.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      setState(() => _error = 'Paste a full link that starts with http:// or https://');
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Paste a link', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Link',
                hintText: 'https://',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _paste, child: const Text('Paste')),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submit, child: const Text('Save link')),
      ]),
    );
  }
}
