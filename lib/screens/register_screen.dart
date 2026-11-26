import 'package:flutter/material.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/driver_profile.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final password = _password.text;
    String? error;
    if (name.length < 2) {
      error = 'Enter your full name.';
    } else if (!email.contains('@') || !email.contains('.')) {
      error = 'Enter a valid email.';
    } else if (phone.length < 10) {
      error = 'Enter a valid 10-digit mobile number.';
    } else if (password.length < 6) {
      error = 'Password must be at least 6 characters.';
    }
    setState(() => _error = error);
    if (error != null) return;

    final draft = DriverRegistrationDraft()
      ..fullName = name
      ..email = email
      ..phone = phone
      ..password = password;

    try {
      await DriverScope.of(context).registerPartner(draft);
      if (!mounted) return;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (failure) {
      if (!mounted) return;
      setState(() => _error = explainError(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create partner account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            const Text(
              'Create your partner account with name, email, password, and mobile number. You can go online right after signup. Document and OTP checks will be added later.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 20),
            _Field(controller: _name, label: 'Full name', textInputAction: TextInputAction.next),
            _Field(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            _Field(
              controller: _phone,
              label: 'Mobile number',
              keyboardType: TextInputType.phone,
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
              onPressed: session.busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.hotPink,
                minimumSize: const Size.fromHeight(54),
              ),
              child: session.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create account'),
            ),
          ],
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
        decoration: InputDecoration(labelText: label, suffixIcon: suffix),
      ),
    );
  }
}
