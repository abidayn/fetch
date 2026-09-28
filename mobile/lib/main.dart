import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'api/api_client.dart';
import 'api/token_storage.dart';
import 'models/item.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/starter_folders_screen.dart';
import 'util/prefs.dart';
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

/// Routing between the app's top-level places, without a router package:
///   first launch   -> Onboarding -> Auth (sign up) -> Starter folders -> Library
///   logged out     -> Auth (log in) -> Library
///   logged in      -> Library
/// Each switch replaces the whole stack (pushAndRemoveUntil), except
/// Onboarding -> Auth, which keeps a way back.
class _FetchAppState extends State<FetchApp> {
  StreamSubscription? _shareSub;

  // Key to HomeScreen so a shared link can be added to the list from here.
  // Without it we'd need a state management library for rare one-way calls.
  final _homeKey = GlobalKey<HomeScreenState>();

  // Shares arrive from outside the widget tree (a plugin callback), so there's
  // no BuildContext at hand. This key gives access to MaterialApp's Navigator
  // to show the save sheet and switch screens from here.
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Same reason: snackbars from outside the widget tree.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  final _themeMode = ValueNotifier(ThemeMode.system);

  late final Future<Widget> _start = _decideStart();

  /// A link shared while logged out: saved right after logging in.
  String? _pendingUrl;

  ApiClient get _api => widget.apiClient;

  @override
  void initState() {
    super.initState();
    _listenForSharedLinks();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _themeMode.dispose();
    super.dispose();
  }

  Future<Widget> _decideStart() async {
    _themeMode.value = await Prefs.themeMode();
    if (await _api.hasToken()) return _home();
    if (await Prefs.onboardingSeen()) return _auth(login: true);
    return OnboardingScreen(onDone: _finishOnboarding);
  }

  // --- places ----------------------------------------------------------------------

  Widget _home() => HomeScreen(key: _homeKey, apiClient: _api, themeMode: _themeMode, onSignedOut: _signedOut);

  Widget _auth({required bool login}) => AuthScreen(
        apiClient: _api,
        startWithLogin: login,
        pendingShare: _pendingUrl != null,
        onAuthenticated: _authenticated,
      );

  void _replaceAll(Widget screen) {
    _navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => screen), (_) => false);
  }

  void _finishOnboarding({required bool login}) {
    Prefs.setOnboardingSeen();
    _navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => _auth(login: login)));
  }

  void _authenticated({required bool isNew}) {
    if (isNew) {
      _replaceAll(StarterFoldersScreen(apiClient: _api, onDone: _enterHome));
    } else {
      _enterHome();
    }
  }

  void _enterHome() {
    _replaceAll(_home());
    final url = _pendingUrl;
    if (url != null) {
      _pendingUrl = null;
      _saveShared(url);
    }
  }

  Future<void> _signedOut() async {
    await _api.logout();
    _replaceAll(_auth(login: true));
  }

  // --- shared links ------------------------------------------------------------------

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

    if (!await _api.hasToken()) {
      // Nowhere safe to save it yet: keep it until the user logs in, and say
      // so -- the link isn't lost.
      _pendingUrl = url;
      await _askToLogIn();
      return;
    }
    await _saveShared(url);
  }

  Future<void> _askToLogIn() async {
    await _waitForApp();
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Log in to save this link', style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text("Fetch will save it as soon as you're in."),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheet);
                _replaceAll(_auth(login: true));
              },
              child: const Text('Log in'),
            ),
            TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Not now')),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveShared(String url) async {
    try {
      final item = Item.fromJson(await _api.createItem(url));
      _homeKey.currentState?.upsert(item);
      await _showSaveSheet(item);
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

  Future<void> _showSaveSheet(Item item) async {
    await _waitForApp();
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    var latest = item;
    await showSaveResultSheet(
      ctx,
      _api,
      item,
      fromShare: true,
      onChanged: (it) {
        latest = it;
        _homeKey.currentState?.upsert(it);
      },
      onToast: (m) => _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m))),
    );
    // Closed before Fetch finished: tell the user where it went when it does.
    if (!latest.processed || latest.waitingForAi) _homeKey.currentState?.watchFiling(item.id);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        title: 'Fetch',
        // Placeholder look (Material + indigo) until the redesign lands.
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
        themeMode: mode,
        home: FutureBuilder<Widget>(
          future: _start,
          builder: (context, snapshot) =>
              snapshot.data ?? const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}
