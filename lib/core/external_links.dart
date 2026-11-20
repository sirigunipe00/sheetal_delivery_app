import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalLinks {
  const ExternalLinks._();

  static Future<bool> call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    return launchUrl(Uri.parse('tel:$digits'));
  }

  static Future<bool> navigate(DeliveryOrder order) async {
    final uri = order.latitude != null && order.longitude != null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${order.latitude},${order.longitude}&travelmode=driving',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(order.address)}',
          );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens turn-by-turn navigation to the store (pickup).
  static Future<bool> navigateToStore(DeliveryStore store) async {
    final uri = store.latitude != null && store.longitude != null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${store.latitude},${store.longitude}&travelmode=driving',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${store.name}, ${store.address}')}',
          );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
