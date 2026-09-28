import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Sign up and log in on one screen, with a toggle. Signing up logs in
/// right away (the backend's register returns no token, so the app logs in
/// with the same details) and continues to starter folders.
class AuthScreen extends StatefulWidget {
  final ApiClient apiClient;
  final bool startWithLogin;

  /// A link was shared while logged out: it's saved right after this.
  final bool pendingShare;

  /// [isNew] = just created the account (-> starter folders).
  final void Function({required bool isNew}) onAuthenticated;

  const AuthScreen({
    super.key,
    required this.apiClient,
    this.startWithLogin = false,
    this.pendingShare = false,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late bool _register = !widget.startWithLogin;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_register) await widget.apiClient.register(email, password);
      await widget.apiClient.login(email, password);
      if (!mounted) return;
      widget.onAuthenticated(isNew: _register);
    } on ApiException catch (e) {
      // The backend's messages are written to be safe to show as they are
      // (e.g. login's single "Incorrect email or password.").
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Can't reach the server.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lead = widget.pendingShare
        ? 'Log in and the link you just shared will be saved.'
        : _register
            ? 'Your saves stay private to your account.'
            : 'Log in to see your saves.';
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Text(_register ? 'Create your Fetch account' : 'Welcome back', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(lead, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Sign up')),
              ButtonSegment(value: false, label: Text('Log in')),
            ],
            selected: {_register},
            onSelectionChanged: _loading ? null : (s) => setState(() {
              _register = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _register ? 'At least 8 characters.' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_register ? 'Create account' : 'Log in'),
          ),
        ]),
      ),
    );
  }
}
