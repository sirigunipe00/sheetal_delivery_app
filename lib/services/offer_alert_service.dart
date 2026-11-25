import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player_plus/flutter_ringtone_player_plus.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';

/// Payload actions from lock-screen notification buttons.
enum OfferNotifAction { open, accept, reject }

class OfferNotifEvent {
  const OfferNotifEvent(this.orderId, this.action);
  final String orderId;
  final OfferNotifAction action;
}

typedef OfferNotifHandler = Future<void> Function(OfferNotifEvent event);

/// Lock-screen / background notifications + foreground ringing alert.
class OfferAlertService {
  OfferAlertService._();
  static final OfferAlertService instance = OfferAlertService._();

  static const channelId = 'delivery_offers_alert';
  static const _notifId = 71001;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _ringtone = RingtonePlayer();
  OfferNotifHandler? onEvent;
  bool _ready = false;
  Timer? _ringTimer;
  bool _ringing = false;
  int _lastNotifId = _notifId;

  Future<void> init({OfferNotifHandler? handler}) async {
    onEvent = handler ?? onEvent;
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse:
            offerNotificationTapBackground,
      );

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestFullScreenIntentPermission();
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          'Delivery offers (alert)',
          description: 'Loud alerts for new nearby delivery requests',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          vibrationPattern: Int64List.fromList([0, 600, 400, 600, 400, 800]),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('[OfferAlert] init failed: $e');
    }
  }

  /// Consume cold-start notification tap (Accept / Reject / open).
  Future<OfferNotifEvent?> takeLaunchEvent() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _eventFrom(details!.notificationResponse);
  }

  /// Lock screen / background: single system notification with Accept / Reject.
  Future<void> showLockScreenOffer({
    required DeliveryOrder order,
    required DeliveryStore store,
    String? distanceToStoreKm,
    String? distanceToCustomerKm,
    String? tripDistanceKm,
  }) async {
    if (!_ready) await init();
    final amount = order.total.round();
    final customer = order.customerName.trim().isEmpty
        ? 'Customer'
        : order.customerName.trim();
    final title = amount > 0
        ? 'New Sheetal delivery · ₹$amount'
        : 'New Sheetal delivery';
    final distanceLine = [
      if (distanceToStoreKm != null && distanceToStoreKm.isNotEmpty)
        'Store $distanceToStoreKm',
      if (distanceToCustomerKm != null && distanceToCustomerKm.isNotEmpty)
        'Customer $distanceToCustomerKm',
      if (tripDistanceKm != null && tripDistanceKm.isNotEmpty)
        'Trip $tripDistanceKm',
    ].join(' · ');
    final body = [
      'Pickup: ${store.name}',
      'Drop: $customer',
      if (order.address.isNotEmpty) order.address,
      if (amount > 0) 'Amount: ₹$amount · ${order.paymentLabel}',
      if (distanceLine.isNotEmpty) distanceLine,
    ].join('\n');

    final android = AndroidNotificationDetails(
      channelId,
      'Delivery offers (alert)',
      channelDescription: 'Loud alerts for new nearby delivery requests',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 600, 400, 600, 400, 800]),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ticker: 'New delivery offer',
      onlyAlertOnce: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: order.orderNumber.isEmpty ? null : '#${order.orderNumber}',
      ),
      actions: const [
        AndroidNotificationAction(
          'accept',
          'ACCEPT',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'reject',
          'REJECT',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    // Stable id per order so duplicates replace instead of stacking.
    final notifId = (order.id.hashCode & 0x7fffffff);
    _lastNotifId = notifId == 0 ? _notifId : notifId;
    await _plugin.cancel(_notifId);
    await _plugin.cancel(_lastNotifId);
    await _plugin.show(
      _lastNotifId,
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: 'offer:${order.id}',
    );
  }

  Future<void> cancelOfferNotification() async {
    await _plugin.cancel(_lastNotifId);
    await _plugin.cancel(_notifId);
  }

  /// Foreground: loop ringtone until accept/reject.
  Future<void> startForegroundRing() async {
    if (_ringing) return;
    _ringing = true;
    try {
      await _ringtone.playAlarm(
        volume: 1,
        looping: true,
      );
    } catch (_) {
      _ringTimer?.cancel();
      _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      });
    }
  }

  Future<void> stopForegroundRing() async {
    _ringing = false;
    _ringTimer?.cancel();
    _ringTimer = null;
    try {
      await _ringtone.stop();
    } catch (_) {}
  }

  void _onResponse(NotificationResponse response) {
    final event = _eventFrom(response);
    if (event == null || onEvent == null) return;
    unawaited(onEvent!(event));
  }

  static OfferNotifEvent? _eventFrom(NotificationResponse? response) {
    if (response == null) return null;
    final payload = response.payload ?? '';
    final orderId = payload.startsWith('offer:')
        ? payload.substring(6)
        : (payload.isEmpty ? null : payload);
    if (orderId == null || orderId.isEmpty) return null;
    final actionId = response.actionId;
    if (actionId == 'accept') {
      return OfferNotifEvent(orderId, OfferNotifAction.accept);
    }
    if (actionId == 'reject') {
      return OfferNotifEvent(orderId, OfferNotifAction.reject);
    }
    return OfferNotifEvent(orderId, OfferNotifAction.open);
  }
}

@pragma('vm:entry-point')
void offerNotificationTapBackground(NotificationResponse response) {
  debugPrint(
    '[OfferAlert] background tap ${response.actionId} ${response.payload}',
  );
}
