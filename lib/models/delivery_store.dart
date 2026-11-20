class DeliveryStore {
  const DeliveryStore({
    required this.name,
    required this.phone,
    required this.address,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String phone;
  final String address;
  final double? latitude;
  final double? longitude;

  factory DeliveryStore.fromMap(Map<String, dynamic> map) {
    return DeliveryStore(
      name: map['name']?.toString() ?? 'Sheetal Ice Cream',
      phone: map['phone']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      latitude: _asDouble(map['latitude']),
      longitude: _asDouble(map['longitude']),
    );
  }

  static const fallback = DeliveryStore(
    name: 'Sheetal Ice Cream',
    phone: '+91 73000 51000',
    address: 'Sheetal Food World, Hyderabad',
  );
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
