import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Tidak ada di plan.md Fase 2 secara eksplisit -- ditambahkan karena login
/// tidak ada gunanya tanpa cara membuat akun. Amandemen kecil, dicatat di
/// plan.md.
class RegisterScreen extends StatefulWidget {
  final ApiClient apiClient;
  const RegisterScreen({super.key, required this.apiClient});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.apiClient.register(_emailCtrl.text.trim(), _passwordCtrl.text);
      // Register sukses TIDAK otomatis login -- backend cuma bikin user,
      // tidak mengembalikan token (lihat routers/auth.py: register return
      // 201 + UserPublic, bukan TokenResponse). Jadi user diarahkan balik
      // ke layar login untuk masuk pakai akun barunya.
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun dibuat. Silakan masuk.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa terhubung ke server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (min. 8 karakter)'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Daftar'),
            ),
          ],
        ),
      ),
    );
  }
}
