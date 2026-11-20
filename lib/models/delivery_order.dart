import 'dart:convert';

class DeliveryItem {
  const DeliveryItem({
    required this.name,
    required this.unitLabel,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final String unitLabel;
  final int unitPrice;
  final int quantity;
  final int lineTotal;

  factory DeliveryItem.fromMap(Map<String, dynamic> map) {
    return DeliveryItem(
      name: map['product_name']?.toString() ?? 'Ice cream',
      unitLabel: map['unit_label']?.toString() ?? '',
      unitPrice: _asInt(map['unit_price']),
      quantity: _asInt(map['quantity']) == 0 ? 1 : _asInt(map['quantity']),
      lineTotal: _asInt(map['line_total']),
    );
  }
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    required this.handlingFee,
    required this.total,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.addressLabel,
    required this.createdAt,
    required this.items,
    this.driverId,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final int subtotal;
  final int deliveryFee;
  final int handlingFee;
  final int total;
  final String customerName;
  final String customerPhone;
  final String address;
  final String addressLabel;
  final DateTime createdAt;
  final List<DeliveryItem> items;
  final String? driverId;
  final double? latitude;
  final double? longitude;

  /// How long a placed order stays visible as a new offer for partners.
  static const offerMaxAge = Duration(minutes: 60);

  bool get isAvailable =>
      status == 'placed' && (driverId == null || driverId!.isEmpty);

  /// Fresh enough to show/alert drivers (hides stale "2 days ago" placed orders).
  bool get isFreshOffer {
    if (!isAvailable) return false;
    return DateTime.now().difference(createdAt) <= offerMaxAge;
  }

  bool get isCod => paymentMethod.toLowerCase().contains('cod');

  String get paymentLabel => isCod ? 'Cash on delivery' : 'Paid online';

  String get statusLabel {
    switch (status) {
      case 'placed':
        return 'New order';
      case 'preparing':
        return 'Accepted';
      case 'out_for_delivery':
        return 'On the way';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String get itemSummary {
    if (items.isEmpty) return 'Ice cream order';
    final first = '${items.first.quantity} × ${items.first.name}';
    if (items.length == 1) return first;
    return '$first + ${items.length - 1} more';
  }

  int get pieceCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  factory DeliveryOrder.fromMap(Map<String, dynamic> map) {
    DateTime created;
    try {
      created = DateTime.parse(map['created_at'].toString()).toLocal();
    } catch (_) {
      created = DateTime.now();
    }

    final id = map['id']?.toString() ?? '';
    final number = map['order_number']?.toString() ??
        (id.length > 6 ? 'SHT${id.substring(0, 6).toUpperCase()}' : 'SHT');
    final driver = map['driver_id']?.toString();

    return DeliveryOrder(
      id: id,
      orderNumber: number,
      status: map['status']?.toString() ?? 'placed',
      paymentMethod: map['payment_method']?.toString() ?? 'cod',
      paymentStatus: map['payment_status']?.toString() ?? 'pending',
      subtotal: _asInt(map['subtotal']),
      deliveryFee: _asInt(map['delivery_fee']),
      handlingFee: _asInt(map['handling_fee']),
      total: _asInt(map['total'] ?? map['grand_total']),
      customerName: map['customer_name']?.toString() ?? 'Customer',
      customerPhone: map['customer_phone']?.toString() ?? '',
      address: _addressOf(map),
      addressLabel: map['address_label']?.toString() ?? 'Home',
      createdAt: created,
      items: _itemsOf(map),
      driverId: (driver == null || driver.isEmpty) ? null : driver,
      latitude: _asDouble(map['delivery_lat'] ?? map['latitude']),
      longitude: _asDouble(map['delivery_lng'] ?? map['longitude']),
    );
  }

  DeliveryOrder copyWith({
    String? status,
    String? driverId,
    bool clearDriver = false,
    double? latitude,
    double? longitude,
    List<DeliveryItem>? items,
  }) {
    return DeliveryOrder(
      id: id,
      orderNumber: orderNumber,
      status: status ?? this.status,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      handlingFee: handlingFee,
      total: total,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      addressLabel: addressLabel,
      createdAt: createdAt,
      items: items ?? this.items,
      driverId: clearDriver ? null : (driverId ?? this.driverId),
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  static String _addressOf(Map<String, dynamic> map) {
    final delivery = map['delivery_address']?.toString().trim() ?? '';
    if (delivery.isNotEmpty) return delivery;
    return map['address_text']?.toString() ?? '';
  }

  static List<DeliveryItem> _itemsOf(Map<String, dynamic> map) {
    var raw = map['order_items'];
    if (raw is! List || raw.isEmpty) raw = map['items'];
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) DeliveryItem.fromMap(Map<String, dynamic>.from(row)),
    ];
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.round();
  return num.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
