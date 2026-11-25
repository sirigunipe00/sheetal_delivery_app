import 'dart:io';

import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:sheetal_driver_app/models/driver_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcceptOfferResult {
  const AcceptOfferResult({this.order, this.store, this.error});

  final DeliveryOrder? order;
  final DeliveryStore? store;
  final String? error;

  bool get ok => order != null && error == null;
}

class DriverRepository {
  DriverRepository({this._client});

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  Future<DriverProfile?> fetchProfile(String id) async {
    final row = await _db.from('drivers').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return DriverProfile.fromMap(row);
  }

  Future<DriverProfile> upsertProfile({
    required String id,
    required String fullName,
    required String phone,
    required String email,
    required String vehicleNumber,
    String vehicleType = 'bike',
    String licenceNumber = '',
    String address = '',
    String emergencyContact = '',
    bool phoneVerified = false,
    String verificationStatus = 'draft',
    String? profilePhotoUrl,
  }) async {
    final row = await _db
        .from('drivers')
        .upsert({
          'id': id,
          'full_name': fullName,
          'phone': phone,
          'email': email,
          'vehicle_number': vehicleNumber,
          'vehicle_type': vehicleType,
          'licence_number': licenceNumber,
          'address': address,
          'emergency_contact': emergencyContact,
          'phone_verified': phoneVerified,
          'verification_status': verificationStatus,
          'profile_photo_url': profilePhotoUrl,
          'is_online': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    return DriverProfile.fromMap(row);
  }

  Future<String?> requestPhoneOtp(String phone) async {
    final raw = await _db.rpc(
      'request_partner_phone_otp',
      params: {'p_phone': phone},
    );
    if (raw is Map && raw['debug_otp'] != null) {
      return raw['debug_otp'].toString();
    }
    return null;
  }

  Future<void> verifyPhoneOtp({
    required String phone,
    required String code,
  }) async {
    final raw = await _db.rpc(
      'verify_partner_phone_otp',
      params: {'p_phone': phone, 'p_code': code},
    );
    if (raw is! Map || raw['ok'] != true) {
      throw Exception(
        (raw is Map ? raw['error'] : null)?.toString() ?? 'OTP verification failed',
      );
    }
  }

  Future<void> saveVehicle({
    required String driverId,
    required String vehicleType,
    required String registrationNumber,
    required String licenceNumber,
  }) async {
    await _db.from('driver_vehicles').upsert({
      'driver_id': driverId,
      'vehicle_type': vehicleType,
      'registration_number': registrationNumber,
      'licence_number': licenceNumber,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> savePayout({
    required String driverId,
    required String upiId,
    String accountHolder = '',
    String accountNumber = '',
    String ifsc = '',
  }) async {
    if (upiId.trim().isEmpty && accountNumber.trim().isEmpty) return;
    await _db.from('driver_payout_details').upsert({
      'driver_id': driverId,
      'upi_id': upiId.trim().isEmpty ? null : upiId.trim(),
      'account_holder': accountHolder.trim().isEmpty ? null : accountHolder.trim(),
      'account_number':
          accountNumber.trim().isEmpty ? null : accountNumber.trim(),
      'ifsc': ifsc.trim().isEmpty ? null : ifsc.trim().toUpperCase(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Uploads a local image into private bucket `driver-documents/{uid}/{type}.ext`
  Future<String> uploadDocument({
    required String driverId,
    required String docType,
    required String localPath,
  }) async {
    final file = File(localPath);
    final ext = localPath.split('.').last.toLowerCase();
    final path = '$driverId/$docType.$ext';
    final bytes = await file.readAsBytes();
    await _db.storage.from('driver-documents').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
    final signed = await _db.storage
        .from('driver-documents')
        .createSignedUrl(path, 60 * 60 * 24 * 365);
    await _db.from('driver_documents').upsert({
      'driver_id': driverId,
      'doc_type': docType,
      'storage_path': path,
      'public_url': signed,
      'file_name': '$docType.$ext',
      'mime_type': ext == 'png' ? 'image/png' : 'image/jpeg',
    }, onConflict: 'driver_id,doc_type');
    return signed;
  }

  Future<DriverProfile> submitForReview(String driverId) async {
    final raw = await _db.rpc('submit_partner_for_review');
    if (raw is! Map || raw['ok'] != true) {
      throw Exception(
        (raw is Map ? raw['error'] : null)?.toString() ??
            'Could not submit for review',
      );
    }
    final profile = await fetchProfile(driverId);
    if (profile == null) throw Exception('Profile missing after submit');
    return profile;
  }

  Future<DriverProfile> setPresence({
    required String id,
    required bool online,
    double? latitude,
    double? longitude,
  }) async {
    final payload = <String, dynamic>{
      'is_online': online,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'latitude': ?latitude,
      'longitude': ?longitude,
    };
    final row =
        await _db.from('drivers').update(payload).eq('id', id).select().single();
    return DriverProfile.fromMap(row);
  }

  Future<void> updateLocation({
    required String id,
    required double latitude,
    required double longitude,
  }) async {
    await _db.from('drivers').update({
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Persist / clear the device FCM token used for nearby order pushes.
  Future<void> saveFcmToken({
    required String driverId,
    required String? token,
  }) async {
    await _db.from('drivers').update({
      'fcm_token': token,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', driverId);
  }

  Future<List<DeliveryOrder>> fetchPlaced() {
    final since = DateTime.now()
        .toUtc()
        .subtract(DeliveryOrder.offerMaxAge)
        .toIso8601String();
    return _orders((query) => query
        .eq('status', 'placed')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(40));
  }

  Future<List<DeliveryOrder>> fetchActive(String driverId) {
    return _orders((query) => query
        .eq('driver_id', driverId)
        .inFilter('status', ['preparing', 'out_for_delivery'])
        .order('created_at', ascending: false));
  }

  Future<List<DeliveryOrder>> fetchHistory(String driverId) {
    return _orders((query) => query
        .eq('driver_id', driverId)
        .eq('status', 'delivered')
        .order('created_at', ascending: false)
        .limit(50));
  }

  Future<DeliveryOrder?> fetchOrder(String id) async {
    final rows = await _orders((query) => query.eq('id', id).limit(1));
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Direct claim fallback when [accept_delivery_offer] RPC is not deployed.
  Future<DeliveryOrder?> claim(String orderId, String driverId) async {
    final payload = {
      'driver_id': driverId,
      'status': 'preparing',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final data = await _db
        .from('orders')
        .update(payload)
        .eq('id', orderId)
        .eq('status', 'placed')
        .isFilter('driver_id', null)
        .select();
    final rows = _asOrders(data);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Accept a nearby delivery offer. Returns order + store (pickup) details.
  Future<AcceptOfferResult> acceptOffer(String orderId) async {
    try {
      final raw = await _db.rpc(
        'accept_delivery_offer',
        params: {'p_order_id': orderId},
      );
      if (raw is! Map) {
        return const AcceptOfferResult(error: 'Unexpected accept response');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) {
        return AcceptOfferResult(
          error: map['error']?.toString() ?? 'Could not accept order',
        );
      }
      final orderMap = map['order'];
      final storeMap = map['store'];
      return AcceptOfferResult(
        order: orderMap is Map
            ? DeliveryOrder.fromMap(Map<String, dynamic>.from(orderMap))
            : null,
        store: storeMap is Map
            ? DeliveryStore.fromMap(Map<String, dynamic>.from(storeMap))
            : DeliveryStore.fallback,
      );
    } catch (e) {
      return AcceptOfferResult(error: e.toString());
    }
  }

  /// Reject / cancel a delivery offer for this partner.
  Future<void> rejectOffer(String orderId) async {
    try {
      await _db.rpc('reject_delivery_offer', params: {'p_order_id': orderId});
    } catch (_) {
      // Best-effort if RPC missing.
      try {
        await _db
            .from('driver_order_alerts')
            .update({
              'status': 'rejected',
              'responded_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('order_id', orderId)
            .eq('status', 'pending');
      } catch (_) {}
    }
  }

  /// Order IDs this partner already rejected (must not reappear on Home).
  Future<Set<String>> fetchRejectedOrderIds(String driverId) async {
    try {
      final rows = await _db
          .from('driver_order_alerts')
          .select('order_id')
          .eq('driver_id', driverId)
          .eq('status', 'rejected');
      final out = <String>{};
      for (final row in rows) {
        final id = row['order_id']?.toString();
        if (id != null && id.isNotEmpty) out.add(id);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<DeliveryStore> fetchStore() async {
    try {
      final row =
          await _db.from('delivery_stores').select().eq('id', 1).maybeSingle();
      if (row == null) return DeliveryStore.fallback;
      return DeliveryStore.fromMap(row);
    } catch (_) {
      return DeliveryStore.fallback;
    }
  }

  Future<void> updateStatus({
    required String orderId,
    required String driverId,
    required String status,
  }) async {
    await _db.from('orders').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId).eq('driver_id', driverId);
  }

  Future<void> release(String orderId, String driverId) async {
    await _db.from('orders').update({
      'driver_id': null,
      'status': 'placed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId).eq('driver_id', driverId);
  }

  Future<List<DeliveryOrder>> _orders(dynamic Function(dynamic query) apply) async {
    try {
      final data = await apply(_db.from('orders').select('*, order_items(*)'));
      return _asOrders(data);
    } catch (_) {
      final data = await apply(_db.from('orders').select());
      return _asOrders(data);
    }
  }

  List<DeliveryOrder> _asOrders(dynamic data) {
    if (data is! List) return const [];
    return [
      for (final row in data)
        if (row is Map) DeliveryOrder.fromMap(Map<String, dynamic>.from(row)),
    ];
  }
}
