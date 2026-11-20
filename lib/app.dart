import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/screens/auth_screen.dart';
import 'package:sheetal_driver_app/screens/shell_screen.dart';
import 'package:sheetal_driver_app/screens/verification_status_screen.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';

class SheetalDriverApp extends StatelessWidget {
  const SheetalDriverApp({super.key, required this.session});

  final DriverSession session;

  @override
  Widget build(BuildContext context) {
    return DriverScope(
      session: session,
      child: MaterialApp(
        title: 'Sheetal Partner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.page,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
          ),
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        ),
        home: const RootScreen(),
      ),
    );
  }
}

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    if (session.booting) return const SplashScreen();
    if (session.userId == null) return const AuthScreen();
    if (session.profile == null) return const SetupScreen();
    // Block home until admin approves the partner.
    if (!session.profile!.isApproved) {
      return const VerificationStatusScreen();
    }
    return const ShellScreen();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.plum,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.two_wheeler, color: Colors.white, size: 64),
              SizedBox(height: 16),
              Text(
                'Sheetal Partner',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Finish delivery setup',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.plum,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                session.error ??
                    'Run supabase/create_delivery_schema.sql in the Supabase SQL editor, then retry.',
                style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 16),
              ),
              const Spacer(),
              FilledButton(
                onPressed: session.busy ? null : session.reloadProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: session.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Retry'),
              ),
              const SizedBox(height: 12),
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
