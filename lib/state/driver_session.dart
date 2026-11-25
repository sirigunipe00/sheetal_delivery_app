import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:sheetal_driver_app/models/driver_profile.dart';
import 'package:sheetal_driver_app/core/distance_util.dart';
import 'package:sheetal_driver_app/services/driver_repository.dart';
import 'package:sheetal_driver_app/services/offer_alert_service.dart';
import 'package:sheetal_driver_app/services/push_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverSession extends ChangeNotifier with WidgetsBindingObserver {
  DriverSession({DriverRepository? repository})
      : _repo = repository ?? DriverRepository() {
    WidgetsBinding.instance.addObserver(this);
  }

  final DriverRepository _repo;

  bool booting = true;
  bool busy = false;
  bool acting = false;
  String? error;
  String? userId;
  DriverProfile? profile;
  Position? position;
  List<DeliveryOrder> available = [];
  DeliveryOrder? active;
  List<DeliveryOrder> history = [];
  DeliveryOrder? incoming;
  /// Pickup / store details for the active or incoming offer.
  DeliveryStore? store;
  DeliveryStore? incomingStore;
  /// After accept (esp. from notification), Shell opens in-app order details.
  bool pendingOpenActiveDelivery = false;

  final List<DeliveryOrder> _queue = [];
  final Set<String> _notified = {};
  final Set<String> _rejectedIds = {};
  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positionSub;
  bool _listening = false;

  bool get isOnline => profile?.isOnline ?? false;
  bool get canGoOnline => profile?.canGoOnline ?? false;
  bool get needsOnboardingCompletion =>
      profile != null && (profile!.isDraft || profile!.isRejected);
  bool get waitingForAdmin => profile?.isPendingReview ?? false;

  SupabaseClient get _db => Supabase.instance.client;

  int get deliveriesToday => history
      .where((order) => isSameDay(order.createdAt, DateTime.now()))
      .length;

  int get earningsToday => history
      .where((order) => isSameDay(order.createdAt, DateTime.now()))
      .fold(0, (sum, order) => sum + order.total);

  void failBoot(Object failure) {
    error = explainError(failure);
    booting = false;
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      final user = _db.auth.currentUser;
      userId = user?.id;
      if (userId != null) {
        profile = await _repo.fetchProfile(userId!);
        if (profile != null && profile!.isApproved) {
          unawaited(PushService.instance.syncToken(userId!));
        }
        if (profile?.isApproved == true && profile?.isOnline == true) {
          await setOnline(true);
        } else if (profile != null && profile!.isApproved) {
          await _refreshActive();
        }
      }
    } catch (failure) {
      error = explainError(failure);
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> reloadProfile() async {
    final id = userId;
    if (id == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      profile = await _repo.fetchProfile(id);
      if (profile == null) {
        error =
            'No partner profile yet. Run supabase/create_delivery_schema.sql in the Supabase SQL editor, then tap Retry.';
      }
    } catch (failure) {
      error = explainError(failure);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Full 3-step partner registration → pending admin review.
  Future<void> registerPartner(DriverRegistrationDraft draft) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!draft.phoneVerified) {
        throw Exception('Verify your mobile number with OTP first.');
      }
      if (!draft.termsAccepted) {
        throw Exception('Accept Terms & Conditions to continue.');
      }

      final authEmail = draft.email.trim().isEmpty
          ? '${draft.phone.trim()}@partners.sheetal.app'
          : draft.email.trim();

      final response = await _db.auth.signUp(
        email: authEmail,
        password: draft.password,
        data: {
          'role': 'driver',
          'full_name': draft.fullName.trim(),
          'phone': draft.phone.trim(),
          'vehicle_number': draft.vehicleNumber.trim(),
        },
      );
      final user = response.user;
      if (user == null) throw Exception('Could not create the account.');
      if (response.session == null) {
        throw Exception(
          'Account created. Confirm the email if required, then log in to finish document upload / review status.',
        );
      }
      userId = user.id;

      String? photoUrl;
      if (draft.profilePhotoPath != null) {
        photoUrl = await _repo.uploadDocument(
          driverId: user.id,
          docType: 'profile_photo',
          localPath: draft.profilePhotoPath!,
        );
      }
      if (draft.licencePhotoPath == null || draft.rcPhotoPath == null) {
        throw Exception('Driving Licence and RC photos are required.');
      }
      await _repo.uploadDocument(
        driverId: user.id,
        docType: 'driving_licence',
        localPath: draft.licencePhotoPath!,
      );
      await _repo.uploadDocument(
        driverId: user.id,
        docType: 'rc',
        localPath: draft.rcPhotoPath!,
      );
      if (draft.insurancePhotoPath != null) {
        await _repo.uploadDocument(
          driverId: user.id,
          docType: 'insurance',
          localPath: draft.insurancePhotoPath!,
        );
      }

      await _repo.upsertProfile(
        id: user.id,
        fullName: draft.fullName.trim(),
        phone: draft.phone.trim(),
        email: authEmail,
        vehicleNumber: draft.vehicleNumber.trim().toUpperCase(),
        vehicleType: draft.vehicleType,
        licenceNumber: draft.licenceNumber.trim().toUpperCase(),
        address: draft.address.trim(),
        emergencyContact: draft.emergencyContact.trim(),
        phoneVerified: true,
        verificationStatus: 'draft',
        profilePhotoUrl: photoUrl,
      );
      await _repo.saveVehicle(
        driverId: user.id,
        vehicleType: draft.vehicleType,
        registrationNumber: draft.vehicleNumber.trim().toUpperCase(),
        licenceNumber: draft.licenceNumber.trim().toUpperCase(),
      );
      await _repo.savePayout(
        driverId: user.id,
        upiId: draft.upiId,
        accountHolder: draft.accountHolder,
        accountNumber: draft.accountNumber,
        ifsc: draft.ifsc,
      );

      profile = await _repo.submitForReview(user.id);
      unawaited(PushService.instance.syncToken(user.id));
    } catch (failure) {
      error = explainError(failure);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> sendPhoneOtp(String phone) => _repo.requestPhoneOtp(phone);

  Future<void> verifyPhoneOtp({
    required String phone,
    required String code,
  }) =>
      _repo.verifyPhoneOtp(phone: phone, code: code);

  Future<void> login({
    required String email,
    required String password,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await _db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final id = response.user?.id;
      if (id == null) throw Exception('Could not sign in.');
      userId = id;
      try {
        profile = await _repo.fetchProfile(id);
      } catch (failure) {
        error = explainError(failure);
        return;
      }
      if (profile == null) {
        await _db.auth.signOut();
        userId = null;
        throw Exception(
          'This email is not a delivery partner. Register a partner account.',
        );
      }
      // Always refresh FCM token after login so pushes can reach this device.
      unawaited(PushService.instance.syncToken(id));
      if (profile!.isOnline) {
        await setOnline(true);
      } else {
        await _refreshActive();
      }
    } catch (failure) {
      error = explainError(failure);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final current = profile;
    _listening = false;
    await _stopLive();
    if (current != null) {
      try {
        if (current.isOnline) {
          await _repo.setPresence(id: current.id, online: false);
        }
        await PushService.instance.clearToken(current.id);
      } catch (_) {}
    }
    await _db.auth.signOut();
    profile = null;
    userId = null;
    available = [];
    active = null;
    history = [];
    incoming = null;
    incomingStore = null;
    store = null;
    _queue.clear();
    error = null;
    unawaited(OfferAlertService.instance.stopForegroundRing());
    unawaited(OfferAlertService.instance.cancelOfferNotification());
    notifyListeners();
  }

  Future<void> setOnline(bool online) async {
    final current = profile;
    if (current == null || busy) return;
    error = null;
    if (online) {
      if (!current.canGoOnline) {
        if (current.isPendingReview) {
          error = 'Admin approval pending. You can go online after approval.';
        } else if (current.isRejected) {
          error =
              'Registration rejected${current.rejectionReason == null || current.rejectionReason!.isEmpty ? '' : ': ${current.rejectionReason}'}. Update details and resubmit.';
        } else {
          error = 'Complete registration and get admin approval before going online.';
        }
        notifyListeners();
        return;
      }
      final allowed = await _ensureLocation();
      if (!allowed) {
        try {
          profile = await _repo.setPresence(id: current.id, online: false);
        } catch (_) {}
        error = 'Allow location to go online. Order alerts are sent only while you are online.';
        notifyListeners();
        return;
      }
    }

    busy = true;
    notifyListeners();
    try {
      Position? pos;
      if (online) pos = await _readPosition();
      profile = await _repo.setPresence(
        id: current.id,
        online: online,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
      position = pos ?? position;
      if (online) {
        unawaited(PushService.instance.syncToken(current.id));
        await _listen();
        _trackLocation();
        await _refreshBoard();
      } else {
        _listening = false;
        await _stopLive();
        available = [];
        incoming = null;
        _queue.clear();
        await _refreshActive();
      }
    } catch (failure) {
      error = explainError(failure);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (profile == null) return;
    if (isOnline) {
      await _refreshBoard();
    } else {
      await _refreshActive();
    }
    notifyListeners();
  }

  Future<String?> accept(DeliveryOrder order) async {
    final current = profile;
    if (current == null) return 'Sign in again.';
    if (active != null && active!.id != order.id) {
      return 'Finish the current delivery before accepting another one.';
    }
    acting = true;
    notifyListeners();
    try {
      final result = await _repo.acceptOffer(order.id);
      if (result.ok) {
        active = result.order;
        store = result.store ?? DeliveryStore.fallback;
      } else if (result.error != null &&
          result.error!.toLowerCase().contains('already taken')) {
        available = available.where((item) => item.id != order.id).toList();
        return 'Another partner already took this order.';
      } else {
        // RPC missing / failed — fall back to direct claim.
        final claimed = await _repo.claim(order.id, current.id);
        if (claimed == null) {
          available = available.where((item) => item.id != order.id).toList();
          return result.error ?? 'Another partner already took this order.';
        }
        active = claimed;
        store = await _repo.fetchStore();
      }
      available = available.where((item) => item.id != order.id).toList();
      _queue.removeWhere((item) => item.id == order.id);
      if (incoming?.id == order.id) {
        incoming = null;
        incomingStore = null;
      }
      await OfferAlertService.instance.stopForegroundRing();
      await OfferAlertService.instance.cancelOfferNotification();
      return null;
    } catch (failure) {
      return explainError(failure);
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  /// Cancel / ignore this offer for the current partner (never show again).
  Future<void> dismissIncoming({String? orderId}) async {
    final id = orderId ?? incoming?.id;
    if (id != null) {
      _rejectedIds.add(id);
      _notified.remove(id);
      available = available.where((order) => order.id != id).toList();
      _queue.removeWhere((order) => order.id == id);
      if (incoming?.id == id) {
        incoming = null;
        incomingStore = null;
      }
      await OfferAlertService.instance.stopForegroundRing();
      await OfferAlertService.instance.cancelOfferNotification();
      try {
        await _repo.rejectOffer(id);
      } catch (_) {}
    } else {
      incoming = null;
      incomingStore = null;
      await OfferAlertService.instance.stopForegroundRing();
      await OfferAlertService.instance.cancelOfferNotification();
    }
    if (incoming == null && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (!_rejectedIds.contains(next.id) && next.isFreshOffer) {
        incoming = next;
        unawaited(_prepareIncoming(incoming!));
      }
    }
    notifyListeners();
  }

  double? distanceToStoreKm([DeliveryOrder? order]) {
    final s = incomingStore ?? store;
    return DistanceUtil.kmBetween(
      lat1: position?.latitude,
      lng1: position?.longitude,
      lat2: s?.latitude,
      lng2: s?.longitude,
    );
  }

  double? distanceToCustomerKm(DeliveryOrder order) {
    return DistanceUtil.kmBetween(
      lat1: position?.latitude,
      lng1: position?.longitude,
      lat2: order.latitude,
      lng2: order.longitude,
    );
  }

  double? tripDistanceKm(DeliveryOrder order) {
    final toStore = distanceToStoreKm(order);
    final store = incomingStore ?? this.store;
    final storeToCustomer = DistanceUtil.kmBetween(
      lat1: store?.latitude,
      lng1: store?.longitude,
      lat2: order.latitude,
      lng2: order.longitude,
    );
    if (toStore == null && storeToCustomer == null) {
      return distanceToCustomerKm(order);
    }
    return (toStore ?? 0) + (storeToCustomer ?? 0);
  }

  /// Handles Accept / Reject / Open from lock-screen notification actions.
  Future<void> handleNotificationAction(OfferNotifEvent event) async {
    if (event.action == OfferNotifAction.reject) {
      await dismissIncoming(orderId: event.orderId);
      return;
    }
    await handlePushOffer(event.orderId, forceShow: true);
    if (event.action == OfferNotifAction.accept) {
      final order = incoming?.id == event.orderId
          ? incoming!
          : await _repo.fetchOrder(event.orderId);
      if (order == null || _rejectedIds.contains(event.orderId)) return;
      final failure = await accept(order);
      if (failure == null) {
        pendingOpenActiveDelivery = true;
        notifyListeners();
      }
    }
  }

  /// Consumed by Shell after accept so we open the in-app delivery screen once.
  DeliveryOrder? takePendingActiveDelivery() {
    if (!pendingOpenActiveDelivery || active == null) return null;
    pendingOpenActiveDelivery = false;
    return active;
  }

  Future<String?> advance(DeliveryOrder order) async {
    final current = profile;
    if (current == null) return 'Sign in again.';
    final next = order.status == 'preparing' ? 'out_for_delivery' : 'delivered';
    acting = true;
    notifyListeners();
    try {
      await _repo.updateStatus(
        orderId: order.id,
        driverId: current.id,
        status: next,
      );
      if (next == 'delivered') {
        active = null;
        history = [order.copyWith(status: 'delivered'), ...history];
      } else {
        active = order.copyWith(status: next);
        // Seed customer map as soon as partner starts the trip.
        await _publishLocationNow();
        _trackLocation();
      }
      return null;
    } catch (failure) {
      return explainError(failure);
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  Future<String?> release(DeliveryOrder order) async {
    final current = profile;
    if (current == null) return 'Sign in again.';
    acting = true;
    notifyListeners();
    try {
      await _repo.release(order.id, current.id);
      active = null;
      if (isOnline) {
        final returned = order.copyWith(status: 'placed', clearDriver: true);
        available = [returned, ...available.where((item) => item.id != order.id)];
      }
      return null;
    } catch (failure) {
      return explainError(failure);
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  Future<DeliveryOrder?> reloadOrder(String id) => _repo.fetchOrder(id);

  /// Opens Accept/Cancel for a push / notification tap.
  /// [forceShow] is true when the user tapped the system notification.
  Future<void> handlePushOffer(String orderId, {bool forceShow = false}) async {
    if (profile == null) return;
    if (!isOnline && !forceShow) return;

    if (_rejectedIds.contains(orderId)) {
      if (incoming?.id == orderId) {
        incoming = null;
        notifyListeners();
      }
      return;
    }
    final order = await _repo.fetchOrder(orderId);
    if (order == null || !order.isFreshOffer) {
      // Already taken or too old — drop any stale overlay for this order.
      if (incoming?.id == orderId) {
        incoming = null;
        notifyListeners();
      }
      return;
    }

    // Realtime may already have queued it; avoid duplicates.
    if (_notified.contains(orderId) && !forceShow && incoming?.id == orderId) {
      return;
    }

    await _onNewOrder(order);
    if (forceShow && incoming?.id != orderId) {
      // Promote this offer to the front when opened from a notification tap.
      _queue.removeWhere((o) => o.id == orderId);
      if (incoming != null && incoming!.id != orderId) {
        _queue.insert(0, incoming!);
      }
      incoming = order;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isOnline) {
      unawaited(_refreshBoard().then((_) => notifyListeners()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopLive());
    super.dispose();
  }

  Future<void> _refreshBoard() async {
    final id = profile?.id;
    if (id == null) return;
    final placed = await _repo.fetchPlaced();
    final rejected = await _repo.fetchRejectedOrderIds(id);
    _rejectedIds.addAll(rejected);
    final activeRows = await _repo.fetchActive(id);
    final past = await _repo.fetchHistory(id);
    available = [
      for (final order in placed)
        if (order.isFreshOffer && !_rejectedIds.contains(order.id)) order,
    ];
    active = activeRows.isEmpty ? null : activeRows.first;
    history = past;
    _dropStaleIncoming();
  }

  Future<void> _refreshActive() async {
    final id = profile?.id;
    if (id == null) return;
    final activeRows = await _repo.fetchActive(id);
    active = activeRows.isEmpty ? null : activeRows.first;
    if (active != null) {
      store ??= await _repo.fetchStore();
    }
  }

  void _dropStaleIncoming() {
    final openIds = available.map((order) => order.id).toSet();
    _queue.removeWhere((order) => !openIds.contains(order.id));
    if (incoming != null && !openIds.contains(incoming!.id)) {
      incoming = null;
    }
    if (incoming == null && _queue.isNotEmpty) {
      incoming = _queue.removeAt(0);
    }
  }

  Future<void> _listen() async {
    await _stopChannel();
    final id = profile?.id;
    if (id == null) return;
    _listening = true;
    final channel = _db.channel('partner-orders-$id');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            unawaited(_onNewOrder(DeliveryOrder.fromMap(payload.newRecord)));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (!_listening) return;
            unawaited(_refreshBoard().then((_) => notifyListeners()));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_order_alerts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: id,
          ),
          callback: (payload) {
            final orderId = payload.newRecord['order_id']?.toString();
            if (orderId == null || orderId.isEmpty) return;
            unawaited(_onAlert(orderId));
          },
        )
        .subscribe();
    _channel = channel;
  }

  Future<void> _onAlert(String orderId) async {
    if (!_listening) return;
    final order = await _repo.fetchOrder(orderId);
    if (order == null) return;
    await _onNewOrder(order);
  }

  Future<void> _onNewOrder(DeliveryOrder order) async {
    if (!_listening || !order.isFreshOffer) return;
    if (_rejectedIds.contains(order.id)) return;
    if (!_notified.add(order.id)) return;
    if (!available.any((item) => item.id == order.id)) {
      available = [order, ...available];
    }
    _queue.add(order);
    if (incoming == null) {
      incoming = _queue.removeAt(0);
      await _prepareIncoming(incoming!);
    }
    notifyListeners();
  }

  Future<void> _prepareIncoming(DeliveryOrder order) async {
    try {
      incomingStore = await _repo.fetchStore();
    } catch (_) {
      incomingStore = DeliveryStore.fallback;
    }
    final toStore = DistanceUtil.labelKm(distanceToStoreKm(order));
    final toCustomer = DistanceUtil.labelKm(distanceToCustomerKm(order));
    final trip = DistanceUtil.labelKm(tripDistanceKm(order));

    // Foreground (unlocked / home): big in-app overlay + ringtone.
    // Background / lock screen: loud system notification with Accept / Reject.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final inForeground = lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;

    if (inForeground) {
      await OfferAlertService.instance.startForegroundRing();
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      return;
    }

    await OfferAlertService.instance.showLockScreenOffer(
      order: order,
      store: incomingStore ?? DeliveryStore.fallback,
      distanceToStoreKm: toStore,
      distanceToCustomerKm: toCustomer,
      tripDistanceKm: trip,
    );
  }

  void _trackLocation() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Smaller steps → smoother Blinkit-style movement on customer map.
        distanceFilter: 8,
      ),
    ).listen((pos) async {
      position = pos;
      final id = profile?.id;
      // Keep publishing while online OR while a delivery is in progress.
      final delivering = active != null &&
          (active!.status == 'preparing' ||
              active!.status == 'out_for_delivery');
      if (id == null || (!isOnline && !delivering)) return;
      try {
        await _repo.updateLocation(
          id: id,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      } catch (_) {}
      notifyListeners();
    });
  }

  /// Push current GPS immediately (call when starting delivery).
  Future<void> _publishLocationNow() async {
    final id = profile?.id;
    if (id == null) return;
    try {
      final pos = position ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
      position = pos;
      await _repo.updateLocation(
        id: id,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {}
  }

  Future<bool> _ensureLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> _readPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  Future<void> _stopLive() async {
    await _stopChannel();
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _stopChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _db.removeChannel(channel);
    }
  }
}
