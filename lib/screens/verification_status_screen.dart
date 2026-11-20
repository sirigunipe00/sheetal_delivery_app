import 'package:flutter/material.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/screens/register_wizard_screen.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';

/// Shown when partner is pending review / rejected / incomplete.
class VerificationStatusScreen extends StatelessWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final profile = session.profile;
    final pending = profile?.isPendingReview ?? false;
    final rejected = profile?.isRejected ?? false;

    final title = pending
        ? 'Waiting for admin approval'
        : rejected
            ? 'Registration rejected'
            : 'Complete your registration';
    final body = pending
        ? 'Your documents were submitted. Sheetal admin will review and notify you. You cannot go online until approved.'
        : rejected
            ? (profile?.rejectionReason?.isNotEmpty == true
                ? profile!.rejectionReason!
                : 'Please update your details and documents, then submit again.')
            : 'Finish the 3-step registration so admin can verify your partner account.';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pending
                    ? Icons.hourglass_top_rounded
                    : rejected
                        ? Icons.cancel_outlined
                        : Icons.assignment_ind_outlined,
                size: 56,
                color: pending
                    ? AppColors.warning
                    : rejected
                        ? AppColors.danger
                        : AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.plum,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 16),
              ),
              const SizedBox(height: 18),
              if (profile != null) ...[
                _Info(label: 'Name', value: profile.fullName),
                _Info(label: 'Phone', value: profile.phone),
                _Info(label: 'Status', value: profile.verificationLabel),
              ],
              const Spacer(),
              if (!pending)
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterWizardScreen()),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(rejected ? 'Update & resubmit' : 'Continue registration'),
                ),
              if (pending) ...[
                FilledButton(
                  onPressed: session.busy ? null : session.reloadProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.plum,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: session.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Refresh status'),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: session.logout,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
