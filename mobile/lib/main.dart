import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'api/api_client.dart';
import 'api/token_storage.dart';
import 'models/item.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/save_result_sheet.dart';

void main() {
  runApp(FetchApp());
}

class FetchApp extends StatefulWidget {
  FetchApp({super.key});

  final apiClient = ApiClient(TokenStorage());

  @override
  State<FetchApp> createState() => _FetchAppState();
}

class _FetchAppState extends State<FetchApp> {
  StreamSubscription? _shareSub;

  // Key to HomeScreen so refresh() can be called from here when a new link
  // arrives while HomeScreen is showing. Without it we'd need a state
  // management library just for rare one-way communication.
  final _homeKey = GlobalKey<HomeScreenState>();

  // Shares arrive from outside the widget tree (a plugin callback), so there's
  // no BuildContext at hand. This key gives access to MaterialApp's Navigator
  // to show the "Saved" sheet from here.
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Same reason: the "save failed" snackbar from outside the widget tree.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _listenForSharedLinks();
  }

  void _listenForSharedLinks() {
    // "Warm": the app is already open (foreground/background) when the user shares.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (err) => debugPrint('Share stream error: $err'),
    );

    // "Cold start": the app isn't running at all and is launched BY the share.
    // That's why it's checked separately from the stream above -- the stream
    // only catches shares that happen AFTER the app is alive and the listener
    // is attached; the share that launched the app would be missed if we
    // relied on the stream alone.
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
  }

  void _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final url = files.first.path;

    // reset() must be called -- without it, the same share is read AGAIN by
    // getInitialMedia() every time the app is reopened, not just once when
    // it happened.
    ReceiveSharingIntent.instance.reset();

    if (!await widget.apiClient.hasToken()) {
      // Not logged in -- there's nowhere safe to save this link. Links are
      // deliberately not queued for later; the user shares again after
      // logging in. But the user must KNOW the link wasn't saved.
      await _showMessage('Log in first, then share the link again.');
      return;
    }
    await _saveShared(url);
  }

  Future<void> _saveShared(String url) async {
    try {
      final item = Item.fromJson(await widget.apiClient.createItem(url));
      _homeKey.currentState?.refresh();
      await _showSavedSheet(item);
    } on ApiException catch (e) {
      // Without this, a failed share (server asleep, offline) disappears
      // silently and the user thinks the link was saved.
      await _showMessage("Couldn't save the link: ${e.message}",
          action: SnackBarAction(label: 'Try again', onPressed: () => _saveShared(url)));
    }
  }

  Future<void> _showMessage(String text, {SnackBarAction? action}) async {
    await _waitForApp();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 8)),
    );
  }

  /// Cold start: the share can be handled before MaterialApp has finished
  /// building its Navigator. Wait a little (max ~5 seconds) until it's ready.
  Future<void> _waitForApp() async {
    for (var i = 0; i < 25 && _navigatorKey.currentContext == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _showSavedSheet(Item item) async {
    await _waitForApp();
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showSaveResultSheet(ctx, widget.apiClient, item);
    _homeKey.currentState?.refresh(); // make sure the final result shows in the list
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Fetch',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // FutureBuilder at the root, rather than always showing LoginScreen --
      // so if a token is STORED from a previous session, the user doesn't
      // have to log in again every time they open the app.
      home: FutureBuilder<bool>(
        future: widget.apiClient.hasToken(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data!
              ? HomeScreen(key: _homeKey, apiClient: widget.apiClient, homeKey: _homeKey)
              : LoginScreen(apiClient: widget.apiClient, homeKey: _homeKey);
        },
      ),
    );
  }
}
