import 'package:flutter/material.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/external_links.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';
import 'package:sheetal_driver_app/widgets/delivery_map.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  DeliveryOrder? _hydrated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    if (!mounted) return;
    if (widget.order.items.isNotEmpty &&
        widget.order.latitude != null &&
        widget.order.longitude != null) {
      return;
    }
    final full = await DriverScope.of(context).reloadOrder(widget.order.id);
    if (!mounted || full == null) return;
    setState(() => _hydrated = full);
  }

  DeliveryOrder _live() {
    final session = DriverScope.of(context);
    final id = widget.order.id;
    if (session.active?.id == id) return session.active!;
    for (final order in session.available) {
      if (order.id == id) return order;
    }
    for (final order in session.history) {
      if (order.id == id) return order;
    }
    return _hydrated ?? widget.order;
  }

  Future<void> _run(
    Future<String?> Function() action, {
    bool popOnSuccess = false,
  }) async {
    final failure = await action();
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    if (popOnSuccess) Navigator.of(context).pop();
  }

  Future<void> _open(Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
  }

  bool _isPickupPhase(DeliveryOrder order) =>
      order.status == 'placed' || order.status == 'preparing';

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final order = _live();
    final store = session.store ?? session.incomingStore ?? DeliveryStore.fallback;
    final mine = order.driverId != null && order.driverId == session.profile?.id;
    final pickupPhase = _isPickupPhase(order);
    final bottomLabel = !mine && order.isAvailable
        ? 'Accept order'
        : order.status == 'preparing'
            ? 'Reached store · Order picked up'
            : order.status == 'out_for_delivery'
                ? 'Mark delivered'
                : null;

    final mapAddress = pickupPhase && mine
        ? store.address
        : order.address;
    final mapLat = pickupPhase && mine ? store.latitude : order.latitude;
    final mapLng = pickupPhase && mine ? store.longitude : order.longitude;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.plum,
        foregroundColor: Colors.white,
        title: Text('#${order.orderNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (mine) ...[
            _NextStepBanner(
              title: pickupPhase
                  ? 'Step 1 · Go to store & pick up'
                  : 'Step 2 · Deliver to customer',
              body: pickupPhase
                  ? 'Review order details below, then tap Navigate to open maps to the store.'
                  : 'Order is with you. Navigate to the customer and complete delivery.',
            ),
            const SizedBox(height: 12),
          ],
          DeliveryMap(
            address: mapAddress,
            latitude: mapLat,
            longitude: mapLng,
            driver: session.position,
            pinLabel: pickupPhase && mine ? 'Store' : 'Customer',
          ),
          const SizedBox(height: 12),
          if (mine) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _open(
                      () => ExternalLinks.call(
                        pickupPhase
                            ? store.phone
                            : order.customerPhone,
                      ),
                      pickupPhase
                          ? 'Could not call the store.'
                          : 'Could not start the call.',
                    ),
                    icon: Icon(pickupPhase ? Icons.storefront_outlined : Icons.call),
                    label: Text(pickupPhase ? 'Call store' : 'Call customer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(
                      () => pickupPhase
                          ? ExternalLinks.navigateToStore(store)
                          : ExternalLinks.navigate(order),
                      'Could not open maps.',
                    ),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                    icon: const Icon(Icons.navigation),
                    label: Text(pickupPhase ? 'Navigate to store' : 'Navigate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickupPhase ? 'Pickup store' : 'Drop location',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (pickupPhase) ...[
                    Text(
                      store.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(store.address, style: const TextStyle(height: 1.35)),
                    if (store.phone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        store.phone,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      order.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(order.address, style: const TextStyle(height: 1.35)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _open(
                      () => ExternalLinks.call(order.customerPhone),
                      'Could not start the call.',
                    ),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(
                      () => ExternalLinks.navigate(order),
                      'Could not open maps.',
                    ),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navigate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusChip(label: order.statusLabel),
                const SizedBox(height: 10),
                Text(
                  order.customerName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (order.customerPhone.isNotEmpty)
                  Text(
                    order.customerPhone,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                const SizedBox(height: 8),
                Text(
                  order.addressLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(order.address, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 6),
                Text(
                  formatWhen(order.createdAt),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (order.items.isEmpty)
                  const Text('Item details will appear when the order syncs.')
                else
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity} × ${item.name}${item.unitLabel.isEmpty ? '' : ' (${item.unitLabel})'}',
                            ),
                          ),
                          Text(
                            rupees(item.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              children: [
                _BillRow(label: 'Items', value: rupees(order.subtotal)),
                _BillRow(label: 'Delivery', value: rupees(order.deliveryFee)),
                _BillRow(label: 'Handling', value: rupees(order.handlingFee)),
                const Divider(),
                _BillRow(
                  label: order.isCod ? 'Collect from customer' : 'Paid online',
                  value: rupees(order.total),
                  strong: true,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    order.paymentLabel,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          if (mine && order.status != 'delivered') ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: session.acting
                  ? null
                  : () => _run(() => session.release(order), popOnSuccess: true),
              child: const Text('Release order back to other partners'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: bottomLabel == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: session.acting
                      ? null
                      : () {
                          if (order.isAvailable) {
                            _run(() async {
                              final failure = await session.accept(order);
                              if (failure == null) {
                                session.dismissIncoming(orderId: order.id);
                              }
                              return failure;
                            });
                            return;
                          }
                          _run(
                            () => session.advance(order),
                            popOnSuccess: order.status == 'out_for_delivery',
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        order.isAvailable || order.status == 'preparing'
                            ? AppColors.online
                            : AppColors.primary,
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: session.acting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          bottomLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
    );
  }
}

class _NextStepBanner extends StatelessWidget {
  const _NextStepBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(color: AppColors.plum, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8F3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      fontSize: strong ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
