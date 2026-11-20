import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/driver_profile.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';
import 'package:sheetal_driver_app/widgets/upper_case_formatter.dart';

class RegisterWizardScreen extends StatefulWidget {
  const RegisterWizardScreen({super.key});

  @override
  State<RegisterWizardScreen> createState() => _RegisterWizardScreenState();
}

class _RegisterWizardScreenState extends State<RegisterWizardScreen> {
  final _draft = DriverRegistrationDraft();
  final _page = PageController();
  final _picker = ImagePicker();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _address = TextEditingController();
  final _emergency = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _licence = TextEditingController();
  final _upi = TextEditingController();
  final _accountHolder = TextEditingController();
  final _accountNumber = TextEditingController();
  final _ifsc = TextEditingController();

  int _step = 0;
  bool _hidePassword = true;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _error;
  String? _debugOtp;

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _address.dispose();
    _emergency.dispose();
    _vehicleNumber.dispose();
    _licence.dispose();
    _upi.dispose();
    _accountHolder.dispose();
    _accountNumber.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _pick(String kind) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (file == null) return;
    setState(() {
      switch (kind) {
        case 'profile':
          _draft.profilePhotoPath = file.path;
        case 'licence':
          _draft.licencePhotoPath = file.path;
        case 'rc':
          _draft.rcPhotoPath = file.path;
        case 'insurance':
          _draft.insurancePhotoPath = file.path;
      }
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() {
      _sendingOtp = true;
      _error = null;
      _debugOtp = null;
    });
    try {
      final debug = await DriverScope.of(context).sendPhoneOtp(phone);
      if (!mounted) return;
      setState(() {
        _debugOtp = debug;
        _draft.phone = phone;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            debug == null
                ? 'OTP sent to $phone'
                : 'Debug OTP: $debug (enable SMS provider for production)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = explainError(e));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phone.text.trim();
    final code = _otp.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the OTP.');
      return;
    }
    setState(() {
      _verifyingOtp = true;
      _error = null;
    });
    try {
      await DriverScope.of(context).verifyPhoneOtp(phone: phone, code: code);
      if (!mounted) return;
      setState(() {
        _draft.phoneVerified = true;
        _draft.phone = phone;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile number verified')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = explainError(e));
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  String? _validateStep0() {
    if (_name.text.trim().length < 2) return 'Enter your full name.';
    if (!_draft.phoneVerified) return 'Verify mobile number with OTP.';
    if (_password.text.length < 6) return 'Password must be at least 6 characters.';
    final email = _email.text.trim();
    if (email.isNotEmpty && (!email.contains('@') || !email.contains('.'))) {
      return 'Enter a valid email or leave it blank.';
    }
    if (_draft.profilePhotoPath == null) return 'Add a profile photo.';
    return null;
  }

  String? _validateStep1() {
    if (_vehicleNumber.text.trim().length < 4) return 'Enter vehicle registration number.';
    if (_licence.text.trim().length < 5) return 'Enter driving licence number.';
    if (_draft.licencePhotoPath == null) return 'Upload driving licence photo.';
    if (_draft.rcPhotoPath == null) return 'Upload RC photo.';
    return null;
  }

  String? _validateStep2() {
    if (_address.text.trim().length < 8) return 'Enter your current address.';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_emergency.text.trim())) {
      return 'Enter a valid emergency contact number.';
    }
    if (!_draft.termsAccepted) return 'Accept Terms & Conditions.';
    return null;
  }

  Future<void> _next() async {
    String? error;
    if (_step == 0) {
      error = _validateStep0();
      if (error == null) {
        _draft
          ..fullName = _name.text.trim()
          ..phone = _phone.text.trim()
          ..email = _email.text.trim()
          ..password = _password.text;
      }
    } else if (_step == 1) {
      error = _validateStep1();
      if (error == null) {
        _draft
          ..vehicleNumber = _vehicleNumber.text.trim()
          ..licenceNumber = _licence.text.trim();
      }
    } else {
      error = _validateStep2();
      if (error == null) {
        _draft
          ..address = _address.text.trim()
          ..emergencyContact = _emergency.text.trim()
          ..upiId = _upi.text.trim()
          ..accountHolder = _accountHolder.text.trim()
          ..accountNumber = _accountNumber.text.trim()
          ..ifsc = _ifsc.text.trim();
      }
    }
    setState(() => _error = error);
    if (error != null) return;

    if (_step < 2) {
      setState(() => _step += 1);
      await _page.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    try {
      await DriverScope.of(context).registerPartner(_draft);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = explainError(e));
    }
  }

  Future<void> _back() async {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step -= 1;
      _error = null;
    });
    await _page.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Register · Step ${_step + 1}/3'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: session.busy ? null : _back,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: List.generate(3, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PersonalStep(
                  name: _name,
                  phone: _phone,
                  email: _email,
                  password: _password,
                  otp: _otp,
                  hidePassword: _hidePassword,
                  phoneVerified: _draft.phoneVerified,
                  profilePath: _draft.profilePhotoPath,
                  sendingOtp: _sendingOtp,
                  verifyingOtp: _verifyingOtp,
                  debugOtp: _debugOtp,
                  onTogglePassword: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  onSendOtp: _sendOtp,
                  onVerifyOtp: _verifyOtp,
                  onPickPhoto: () => _pick('profile'),
                ),
                _VehicleStep(
                  vehicleType: _draft.vehicleType,
                  vehicleNumber: _vehicleNumber,
                  licence: _licence,
                  licencePath: _draft.licencePhotoPath,
                  rcPath: _draft.rcPhotoPath,
                  onTypeChanged: (v) => setState(() => _draft.vehicleType = v),
                  onPickLicence: () => _pick('licence'),
                  onPickRc: () => _pick('rc'),
                ),
                _ExtraStep(
                  address: _address,
                  emergency: _emergency,
                  upi: _upi,
                  accountHolder: _accountHolder,
                  accountNumber: _accountNumber,
                  ifsc: _ifsc,
                  insurancePath: _draft.insurancePhotoPath,
                  termsAccepted: _draft.termsAccepted,
                  onTermsChanged: (v) =>
                      setState(() => _draft.termsAccepted = v ?? false),
                  onPickInsurance: () => _pick('insurance'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, height: 1.3),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                onPressed: session.busy ? null : _next,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: session.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_step == 2 ? 'Submit for admin review' : 'Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalStep extends StatelessWidget {
  const _PersonalStep({
    required this.name,
    required this.phone,
    required this.email,
    required this.password,
    required this.otp,
    required this.hidePassword,
    required this.phoneVerified,
    required this.profilePath,
    required this.sendingOtp,
    required this.verifyingOtp,
    required this.debugOtp,
    required this.onTogglePassword,
    required this.onSendOtp,
    required this.onVerifyOtp,
    required this.onPickPhoto,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController otp;
  final bool hidePassword;
  final bool phoneVerified;
  final String? profilePath;
  final bool sendingOtp;
  final bool verifyingOtp;
  final String? debugOtp;
  final VoidCallback onTogglePassword;
  final VoidCallback onSendOtp;
  final VoidCallback onVerifyOtp;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      children: [
        const Text(
          'Personal information',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.plum,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mobile OTP verification is required before you can continue.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: onPickPhoto,
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.line,
              backgroundImage:
                  profilePath == null ? null : FileImage(File(profilePath!)),
              child: profilePath == null
                  ? const Icon(Icons.camera_alt, color: AppColors.muted)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text('Profile photo *', style: TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(height: 16),
        _Field(controller: name, label: 'Full name *'),
        _Field(
          controller: phone,
          label: 'Mobile number *',
          keyboardType: TextInputType.phone,
          enabled: !phoneVerified,
        ),
        if (!phoneVerified) ...[
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: otp,
                  label: 'OTP',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  TextButton(
                    onPressed: sendingOtp ? null : onSendOtp,
                    child: Text(sendingOtp ? 'Sending…' : 'Send OTP'),
                  ),
                  TextButton(
                    onPressed: verifyingOtp ? null : onVerifyOtp,
                    child: Text(verifyingOtp ? 'Checking…' : 'Verify'),
                  ),
                ],
              ),
            ],
          ),
          if (debugOtp != null)
            Text(
              'Debug OTP: $debugOtp',
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
            ),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '✓ Mobile verified',
              style: TextStyle(color: AppColors.online, fontWeight: FontWeight.w700),
            ),
          ),
        _Field(
          controller: email,
          label: 'Email (optional)',
          keyboardType: TextInputType.emailAddress,
        ),
        _Field(
          controller: password,
          label: 'Password *',
          obscure: hidePassword,
          suffix: IconButton(
            onPressed: onTogglePassword,
            icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ],
    );
  }
}

class _VehicleStep extends StatelessWidget {
  const _VehicleStep({
    required this.vehicleType,
    required this.vehicleNumber,
    required this.licence,
    required this.licencePath,
    required this.rcPath,
    required this.onTypeChanged,
    required this.onPickLicence,
    required this.onPickRc,
  });

  final String vehicleType;
  final TextEditingController vehicleNumber;
  final TextEditingController licence;
  final String? licencePath;
  final String? rcPath;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickLicence;
  final VoidCallback onPickRc;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      children: [
        const Text(
          'Vehicle information',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.plum,
          ),
        ),
        const SizedBox(height: 16),
        const Text('Vehicle type *', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final type in const ['bike', 'scooter', 'other'])
              ChoiceChip(
                label: Text(type[0].toUpperCase() + type.substring(1)),
                selected: vehicleType == type,
                onSelected: (_) => onTypeChanged(type),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Field(
          controller: vehicleNumber,
          label: 'Vehicle registration number *',
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        ),
        _Field(
          controller: licence,
          label: 'Driving licence number *',
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        ),
        _DocTile(
          title: 'Driving licence photo *',
          path: licencePath,
          onTap: onPickLicence,
        ),
        _DocTile(
          title: 'RC photo *',
          path: rcPath,
          onTap: onPickRc,
        ),
      ],
    );
  }
}

class _ExtraStep extends StatelessWidget {
  const _ExtraStep({
    required this.address,
    required this.emergency,
    required this.upi,
    required this.accountHolder,
    required this.accountNumber,
    required this.ifsc,
    required this.insurancePath,
    required this.termsAccepted,
    required this.onTermsChanged,
    required this.onPickInsurance,
  });

  final TextEditingController address;
  final TextEditingController emergency;
  final TextEditingController upi;
  final TextEditingController accountHolder;
  final TextEditingController accountNumber;
  final TextEditingController ifsc;
  final String? insurancePath;
  final bool termsAccepted;
  final ValueChanged<bool?> onTermsChanged;
  final VoidCallback onPickInsurance;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      children: [
        const Text(
          'Additional information',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.plum,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Submitted for admin verification. You can go online only after approval.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        _Field(controller: address, label: 'Current address *', maxLines: 3),
        _Field(
          controller: emergency,
          label: 'Emergency contact *',
          keyboardType: TextInputType.phone,
        ),
        _DocTile(
          title: 'Vehicle insurance (recommended)',
          path: insurancePath,
          onTap: onPickInsurance,
        ),
        const SizedBox(height: 8),
        const Text('Payout details (recommended)', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _Field(controller: upi, label: 'UPI ID'),
        _Field(controller: accountHolder, label: 'Account holder name'),
        _Field(
          controller: accountNumber,
          label: 'Bank account number',
          keyboardType: TextInputType.number,
        ),
        _Field(
          controller: ifsc,
          label: 'IFSC',
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        ),
        CheckboxListTile(
          value: termsAccepted,
          onChanged: onTermsChanged,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I accept the Terms & Conditions and confirm my documents are genuine.',
            style: TextStyle(fontSize: 14),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.title,
    required this.path,
    required this.onTap,
  });

  final String title;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: path == null
            ? const Icon(Icons.upload_file, color: AppColors.primary)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(path!), width: 44, height: 44, fit: BoxFit.cover),
              ),
        title: Text(title),
        subtitle: Text(path == null ? 'Tap to upload' : 'Uploaded'),
        trailing: const Icon(Icons.chevron_right),
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
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        obscureText: obscure,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
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
