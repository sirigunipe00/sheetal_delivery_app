import 'package:flutter_test/flutter_test.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';

void main() {
  test('reads a customer order from the shared Supabase shape', () {
    final order = DeliveryOrder.fromMap({
      'id': 'abc',
      'order_number': 'SHT100001',
      'status': 'placed',
      'payment_method': 'cod',
      'total': 240,
      'subtotal': 200,
      'delivery_fee': 30,
      'handling_fee': 10,
      'customer_name': 'Asha',
      'customer_phone': '9876543210',
      'delivery_address': '12, Indiranagar, Bengaluru',
      'delivery_lat': 12.97,
      'delivery_lng': 77.64,
      'created_at': '2026-11-13T05:00:00Z',
      'items': [
        {
          'product_name': 'Chocolate Chips',
          'unit_label': '120 ml',
          'unit_price': 40,
          'quantity': 2,
          'line_total': 80,
        }
      ],
    });

    expect(order.customerName, 'Asha');
    expect(order.items, hasLength(1));
    expect(order.items.first.name, 'Chocolate Chips');
    expect(order.latitude, 12.97);
    expect(order.longitude, 77.64);
    expect(order.isAvailable, isTrue);
    expect(order.itemSummary, '2 × Chocolate Chips');
    expect(rupees(order.total), '₹240');
  });

  test('prefers order items over an empty relation', () {
    final order = DeliveryOrder.fromMap({
      'id': 'def',
      'status': 'preparing',
      'driver_id': 'partner-1',
      'order_items': [],
      'items': [
        {
          'product_name': 'Kulfi',
          'quantity': 1,
          'unit_price': 50,
          'line_total': 50,
        }
      ],
    });

    expect(order.isAvailable, isFalse);
    expect(order.items.single.name, 'Kulfi');
    expect(order.statusLabel, 'Accepted');
  });
}
