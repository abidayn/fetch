import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../util/prefs.dart';
import 'folders_screen.dart';

/// Account, folders, appearance, privacy, version, delete account. Reached
/// from the avatar on home. Folders are managed where they're used (chip
/// long-press, a folder's ⋮, All folders); the row here is a second way in.
class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<Item> items;
  final int folderCount;
  final ValueNotifier<ThemeMode> themeMode;
  final ValueChanged<String> onOpenFolder;
  final VoidCallback onSignedOut;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.items,
    required this.folderCount,
    required this.themeMode,
    required this.onOpenFolder,
    required this.onSignedOut,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _email;
  String? _version;

  @override
  void initState() {
    super.initState();
    widget.apiClient.myEmail().then((e) {
      if (mounted) setState(() => _email = e);
    }).catchError((_) {});
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    }).catchError((_) {});
  }

  Future<void> _logout() async {
    await widget.apiClient.logout();
    widget.onSignedOut();
  }

  Future<void> _setTheme(ThemeMode mode) async {
    widget.themeMode.value = mode;
    await Prefs.setThemeMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _deleteAccount() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DeleteAccountSheet(
        apiClient: widget.apiClient,
        saves: widget.items.length,
        folders: widget.folderCount,
      ),
    );
    if (deleted != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted')));
    widget.onSignedOut();
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
        child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _email;
    final saves = widget.items.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        _label(theme, 'Account'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(
              leading: CircleAvatar(child: Text((email ?? '?').substring(0, 1).toUpperCase())),
              title: Text(email ?? '…'),
              subtitle: Text('$saves save${saves == 1 ? '' : 's'} · ${widget.folderCount} '
                  'folder${widget.folderCount == 1 ? '' : 's'}'),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: _logout),
          ]),
        ),
        _label(theme, 'Folders'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('All folders'),
            subtitle: const Text('Browse, rename, delete or add folders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  FoldersScreen(apiClient: widget.apiClient, items: widget.items, onOpenFolder: widget.onOpenFolder),
            )),
          ),
        ),
        _label(theme, 'Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {widget.themeMode.value},
            onSelectionChanged: (s) => _setTheme(s.first),
          ),
        ),
        _label(theme, 'Privacy'),
        const Card(
          margin: EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Fetch stores your links, their titles and summaries. To write summaries and answers, the content '
              'of each link is sent to Google Gemini, or Groq when Gemini is unavailable. Nothing is shared with '
              'other users.',
            ),
          ),
        ),
        _label(theme, 'About'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListTile(title: const Text('Version'), trailing: Text(_version ?? '…')),
        ),
        const SizedBox(height: 24),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: ListTile(
            title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
            onTap: _deleteAccount,
          ),
        ),
      ]),
    );
  }
}

class _DeleteAccountSheet extends StatefulWidget {
  final ApiClient apiClient;
  final int saves;
  final int folders;
  const _DeleteAccountSheet({required this.apiClient, required this.saves, required this.folders});

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.apiClient.deleteAccount(_ctrl.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Delete your account?', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('This permanently deletes your account, ${widget.saves} saves and ${widget.folders} folders. '
            "It can't be undone."),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          obscureText: true,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Type your password to confirm',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: _busy || _ctrl.text.isEmpty ? null : _delete,
              child: const Text('Delete account'),
            ),
          ),
        ]),
      ]),
    );
  }
}
