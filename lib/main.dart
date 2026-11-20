import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:sheetal_driver_app/app.dart';
import 'package:sheetal_driver_app/core/supabase_config.dart';
import 'package:sheetal_driver_app/firebase_options.dart';
import 'package:sheetal_driver_app/services/offer_alert_service.dart';
import 'package:sheetal_driver_app/services/push_service.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = DriverSession();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }
  try {
    await OfferAlertService.instance.init();
    await PushService.instance.init();
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (error) {
    session.failBoot(error);
    runApp(SheetalDriverApp(session: session));
    return;
  }

  PushService.instance.attach(session);
  await session.restore();
  runApp(SheetalDriverApp(session: session));
}
