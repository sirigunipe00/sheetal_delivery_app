import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/distance_util.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/models/delivery_store.dart';
import 'package:sheetal_driver_app/screens/history_screen.dart';
import 'package:sheetal_driver_app/screens/home_screen.dart';
import 'package:sheetal_driver_app/screens/order_detail_screen.dart';
import 'package:sheetal_driver_app/screens/profile_screen.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  String? _openedDeliveryId;
  DriverSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = DriverScope.of(context);
    if (_session != session) {
      _session?.removeListener(_onSession);
      _session = session;
      _session?.addListener(_onSession);
    }
    _openPendingIfNeeded();
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() => _openPendingIfNeeded();

  void _openPendingIfNeeded() {
    final session = _session;
    if (session == null || !mounted) return;
    final pending = session.takePendingActiveDelivery();
    if (pending == null) return;
    if (_openedDeliveryId == pending.id) return;
    _openedDeliveryId = pending.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(order: pending)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final pages = const [HomeScreen(), HistoryScreen(), ProfileScreen()];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          Scaffold(
            body: pages[_index],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
          if (session.incoming != null)
            IncomingRequestOverlay(
              order: session.incoming!,
              store: session.incomingStore ?? DeliveryStore.fallback,
            ),
        ],
      ),
    );
  }
}

class IncomingRequestOverlay extends StatelessWidget {
  const IncomingRequestOverlay({
    super.key,
    required this.order,
    required this.store,
  });

  final DeliveryOrder order;
  final DeliveryStore store;

  Future<void> _accept(BuildContext context) async {
    final session = DriverScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failure = await session.accept(order);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(order: session.active ?? order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final toStore = DistanceUtil.labelKm(session.distanceToStoreKm(order));
    final toCustomer = DistanceUtil.labelKm(session.distanceToCustomerKm(order));
    final trip = DistanceUtil.labelKm(session.tripDistanceKm(order));

    return Material(
      color: const Color(0xE61A1028),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8F3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'NEW ORDER',
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo(order.createdAt),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        rupees(order.total),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: AppColors.online,
                        ),
                      ),
                      Text(
                        '${order.paymentLabel} · ${order.pieceCount} items · #${order.orderNumber}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      if (trip != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Total trip ≈ $trip',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.plum,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _Block(
                        icon: Icons.storefront_rounded,
                        title: 'Pickup · Store',
                        lines: [
                          store.name,
                          store.address,
                          if (store.phone.isNotEmpty) store.phone,
                          if (toStore != null) 'Distance from you: $toStore',
                        ],
                        accent: AppColors.purple,
                      ),
                      const SizedBox(height: 10),
                      _Block(
                        icon: Icons.location_on_rounded,
                        title: 'Drop · Customer',
                        lines: [
                          order.customerName,
                          if (order.customerPhone.isNotEmpty) order.customerPhone,
                          order.address,
                          if (toCustomer != null) 'Distance from you: $toCustomer',
                        ],
                        accent: AppColors.primary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        order.itemSummary,
                        style: const TextStyle(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: session.acting
                                  ? null
                                  : () => session.dismissIncoming(
                                        orderId: order.id,
                                      ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFDC2626)),
                                minimumSize: const Size.fromHeight(54),
                              ),
                              child: const Text(
                                'REJECT',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  session.acting ? null : () => _accept(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.online,
                                minimumSize: const Size.fromHeight(54),
                              ),
                              child: session.acting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'ACCEPT',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Accept opens order details in the app. Navigate to the store from there.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.lines,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line, style: const TextStyle(height: 1.3)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
