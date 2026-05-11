import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../main.dart';

class NewPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const NewPasswordScreen({super.key, required this.email});
  @override ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error, _session;

  @override void dispose() { _passCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  Future<void> _set() async {
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass != confirm)     { setState(() => _error = 'Passwords do not match'); return; }
    if (pass.length < 8)     { setState(() => _error = 'Minimum 8 characters'); return; }
    if (_session == null) {
      setState(() => _error = 'Session expired — please sign in again'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final user = await AuthService.instance.setNewPassword(widget.email, pass, _session!);
      ref.read(authProvider.notifier).setUser(user);
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Set new password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🔒', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          const Text('Create a new password', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
          Text('for ${widget.email}', style: const TextStyle(color: AppColors.text2)),
          const SizedBox(height: 24),
          TextField(
            controller: _passCtrl, obscureText: _obscure,
            style: const TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.text2, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl, obscureText: _obscure,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline, color: AppColors.text2, size: 20)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.wicket, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _set,
              child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
                : const Text('Set password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            )),
        ]),
      ),
    );
  }
}
