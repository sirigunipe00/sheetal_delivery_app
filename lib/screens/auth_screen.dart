import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/screens/register_wizard_screen.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    String? error;
    if (email.isEmpty) {
      error = 'Enter your email (or phone@partners.sheetal.app if you skipped email).';
    } else if (password.length < 6) {
      error = 'Password must be at least 6 characters.';
    }
    setState(() => _error = error);
    if (error != null) return;

    try {
      await DriverScope.of(context).login(email: email, password: password);
    } catch (failure) {
      if (!mounted) return;
      setState(() => _error = explainError(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            children: [
              const Icon(Icons.two_wheeler, color: AppColors.hotPink, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Sheetal Delivery Partner',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.plum,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Log in after registration. New partners must complete OTP + documents and wait for admin approval before going online.',
                style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 28),
              _Field(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              _Field(
                controller: _password,
                label: 'Password',
                obscure: _hidePassword,
                textInputAction: TextInputAction.done,
                suffix: IconButton(
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.3)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: session.busy ? null : _login,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.hotPink,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: session.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterWizardScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Register as delivery partner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
