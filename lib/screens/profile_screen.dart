import 'package:flutter/material.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final profile = session.profile;
    final name = profile?.fullName ?? 'Partner';
    final initial = name.trim().isEmpty ? 'P' : name.trim()[0].toUpperCase();
    return ListView(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 24, 20, 24),
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.hotPink,
          backgroundImage: profile?.profilePhotoUrl == null
              ? null
              : NetworkImage(profile!.profilePhotoUrl!),
          child: profile?.profilePhotoUrl == null
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        Text(
          name,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.plum,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile?.verificationLabel ?? 'Partner',
          style: TextStyle(
            color: profile?.isApproved == true ? AppColors.online : AppColors.warning,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        _Row(label: 'Phone', value: profile?.phone ?? ''),
        _Row(label: 'Email', value: profile?.email ?? ''),
        _Row(
          label: 'Vehicle',
          value:
              '${(profile?.vehicleType ?? 'bike').toUpperCase()} · ${profile?.vehicleNumber ?? ''}',
        ),
        _Row(label: 'Licence', value: profile?.licenceNumber ?? ''),
        _Row(label: 'Address', value: profile?.address ?? ''),
        _Row(label: 'Status', value: session.isOnline ? 'Online' : 'Offline'),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: session.logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('Log out'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
