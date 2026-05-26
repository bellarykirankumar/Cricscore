import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;
  String? _error;
  bool _showForgot = false;
  bool _showSignup = false;

  @override void dispose() {
    _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).signIn(email, pass);
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      if (e.message == 'NEW_PASSWORD_REQUIRED') {
        if (mounted) context.push('/new-password?email=$email');
        return;
      }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentFaint,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: const Center(child: Text('🏏', style: TextStyle(fontSize: 40))),
            ),
            const SizedBox(height: 20),
            const Text('CricScore', style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.accent)),
            const Text('AI-powered cricket scoring', style: TextStyle(
              color: AppColors.text2, fontSize: 14)),
            const SizedBox(height: 32),

            if (!_showSignup) ...[
              // Login form
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.text2, size: 20),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, color: AppColors.text2, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.text2, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.wicketFaint, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.wicket.withOpacity(0.3))),
                  child: Text(_error!, style: const TextStyle(color: AppColors.wicket, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
                    : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? ", style: TextStyle(color: AppColors.text2)),
                GestureDetector(
                  onTap: () => setState(() { _showSignup = true; _error = null; }),
                  child: const Text('Sign up', style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ]),
            ] else ...[
              _SignupForm(
                onDone: () => setState(() { _showSignup = false; _error = null; }),
                onLogin: () => setState(() => _showSignup = false),
              ),
            ],

          ]),
        )),
      ),
    );
  }
}

class _SignupForm extends StatefulWidget {
  final VoidCallback onDone, onLogin;
  const _SignupForm({required this.onDone, required this.onLogin});
  @override State<_SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<_SignupForm> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  bool _codeSent = false;
  String? _error;

  @override void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose(); _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'All fields required'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.signUp(
        _emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim());
      setState(() { _codeSent = true; _loading = false; });
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _confirm() async {
    if (_codeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter verification code'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.confirmSignUp(
        _emailCtrl.text.trim(), _codeCtrl.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account confirmed! Sign in now.')));
      widget.onDone();
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override Widget build(BuildContext context) {
    return Column(children: [
      const Text('Create account', style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
      const SizedBox(height: 16),
      if (!_codeSent) ...[
        TextField(controller: _nameCtrl, style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline, color: AppColors.text2, size: 20))),
        const SizedBox(height: 10),
        TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.text2, size: 20))),
        const SizedBox(height: 10),
        TextField(controller: _passCtrl, obscureText: _obscure,
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.text2, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.text2, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure)))),
      ] else ...[
        const Icon(Icons.mark_email_read_outlined, color: AppColors.accent, size: 48),
        const SizedBox(height: 8),
        const Text('Check your email for a code', style: TextStyle(color: AppColors.text2)),
        const SizedBox(height: 12),
        TextField(controller: _codeCtrl,
          keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(labelText: 'Verification code')),
      ],
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: AppColors.wicket, fontSize: 13)),
      ],
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _loading ? null : (_codeSent ? _confirm : _signUp),
          child: _loading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
            : Text(_codeSent ? 'Confirm' : 'Sign up',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        )),
      const SizedBox(height: 12),
      TextButton(onPressed: widget.onLogin,
        child: const Text('← Back to sign in', style: TextStyle(color: AppColors.text2))),
    ]);
  }
}
