import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sheetal_driver_app/firebase_options.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:sheetal_driver_app/services/driver_repository.dart';
import 'package:sheetal_driver_app/services/offer_alert_service.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';

/// Background isolate — show loud Accept/Reject notification when locked.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await OfferAlertService.instance.init();

    final data = message.data;
    if (data['type'] != null && data['type'] != 'delivery_offer') return;
    final orderId = data['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    // Prefer rich data from the push payload (no auth needed in background).
    final total = _asInt(data['total']);
    final customer = _nonEmpty(data['customer_name']) ?? 'Customer';
    final order = DeliveryOrder(
      id: orderId,
      orderNumber: data['order_number']?.toString() ?? '',
      status: 'placed',
      paymentMethod: data['payment_method']?.toString() ?? 'cod',
      paymentStatus: 'pending',
      subtotal: total,
      deliveryFee: 0,
      handlingFee: 0,
      total: total,
      customerName: customer,
      customerPhone: data['customer_phone']?.toString() ?? '',
      address: data['delivery_address']?.toString() ?? '',
      addressLabel: 'Home',
      createdAt: DateTime.now(),
      items: const [],
      latitude: double.tryParse(data['delivery_lat']?.toString() ?? ''),
      longitude: double.tryParse(data['delivery_lng']?.toString() ?? ''),
    );
    final store = DeliveryStore(
      name: data['store_name']?.toString() ?? DeliveryStore.fallback.name,
      phone: data['store_phone']?.toString() ?? DeliveryStore.fallback.phone,
      address:
          data['store_address']?.toString() ?? DeliveryStore.fallback.address,
      latitude: double.tryParse(data['store_lat']?.toString() ?? ''),
      longitude: double.tryParse(data['store_lng']?.toString() ?? ''),
    );

    await OfferAlertService.instance.showLockScreenOffer(
      order: order,
      store: store,
      distanceToStoreKm: _nonEmpty(data['distance_to_store_km']),
      distanceToCustomerKm: _nonEmpty(data['distance_to_customer_km']),
      tripDistanceKm: _nonEmpty(data['trip_distance_km']),
    );
  } catch (e) {
    debugPrint('[FCM background] $e');
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.round();
  return num.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  final _repo = DriverRepository();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  DriverSession? _session;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // Foreground: we show the big in-app overlay ourselves (not a tiny banner).
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      await OfferAlertService.instance.init(
        handler: (event) async {
          final session = _session;
          if (session == null) return;
          await session.handleNotificationAction(event);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('[FCM] init failed: $e');
    }
  }

  void attach(DriverSession session) {
    _session = session;
    _foregroundSub?.cancel();
    _openedSub?.cancel();

    OfferAlertService.instance.onEvent = (event) async {
      await session.handleNotificationAction(event);
    };

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final orderId = _orderIdOf(message);
      if (orderId == null) return;
      // App open → big Accept/Reject overlay + ringtone.
      unawaited(session.handlePushOffer(orderId, forceShow: true));
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final orderId = _orderIdOf(message);
      if (orderId == null) return;
      unawaited(session.handlePushOffer(orderId, forceShow: true));
    });

    unawaited(() async {
      final launch = await OfferAlertService.instance.takeLaunchEvent();
      if (launch != null) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await session.handleNotificationAction(launch);
        return;
      }
      final initial = await _messaging.getInitialMessage();
      final orderId = _orderIdOf(initial);
      if (orderId == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await session.handlePushOffer(orderId, forceShow: true);
    }());
  }

  Future<void> syncToken(String driverId) async {
    if (!_ready) await init();
    if (!_ready) return;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed && Platform.isIOS) {
        debugPrint('[FCM] notification permission denied');
        return;
      }

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _repo.saveFcmToken(driverId: driverId, token: token);
        debugPrint('[FCM] token saved for $driverId');
      }

      await _tokenSub?.cancel();
      _tokenSub = _messaging.onTokenRefresh.listen((fresh) async {
        final id = _session?.profile?.id ?? driverId;
        await _repo.saveFcmToken(driverId: id, token: fresh);
      });
    } catch (e) {
      debugPrint('[FCM] syncToken failed: $e');
    }
  }

  Future<void> clearToken(String driverId) async {
    try {
      await _repo.saveFcmToken(driverId: driverId, token: null);
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('[FCM] clearToken failed: $e');
    }
  }

  String? _orderIdOf(RemoteMessage? message) {
    if (message == null) return null;
    final data = message.data;
    final type = data['type']?.toString();
    if (type != null && type != 'delivery_offer') return null;
    final id = data['order_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
  }
}
