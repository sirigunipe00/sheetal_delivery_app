import 'package:flutter/material.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';
import 'package:sheetal_driver_app/core/format.dart';
import 'package:sheetal_driver_app/models/delivery_order.dart';
import 'package:sheetal_driver_app/screens/order_detail_screen.dart';
import 'package:sheetal_driver_app/state/driver_scope.dart';
import 'package:sheetal_driver_app/state/driver_session.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = DriverScope.of(context);
    final profile = session.profile;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.plum, Color(0xFF7A2468)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greetingForNow(),
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          profile?.firstName ?? 'Partner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OnlineToggle(
                    online: session.isOnline,
                    busy: session.busy,
                    enabled: session.canGoOnline || session.isOnline,
                    onChanged: session.setOnline,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                session.isOnline
                    ? 'Online · new orders will alert you'
                    : 'Offline · order alerts are paused',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: 'Today', value: '${session.deliveriesToday}'),
                  const SizedBox(width: 10),
                  _Stat(label: 'Earned', value: rupees(session.earningsToday)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: session.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (session.error != null) _Banner(text: session.error!),
                if (session.active != null)
                  _ActiveCard(order: session.active!),
                if (!session.isOnline)
                  const _InfoCard(
                    icon: Icons.power_settings_new,
                    title: 'You are offline',
                    body: 'Go online to receive Sheetal delivery requests. Offline partners are not notified.',
                  )
                else ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'New orders',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.plum),
                    ),
                  ),
                  if (session.available.isEmpty)
                    const _SearchingCard()
                  else
                    for (final order in session.available)
                      _RequestCard(order: order, session: session),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OnlineToggle extends StatelessWidget {
  const _OnlineToggle({
    required this.online,
    required this.busy,
    required this.onChanged,
    this.enabled = true,
  });

  final bool online;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy || !enabled ? null : () => onChanged(!online),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: online ? AppColors.online : const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(online ? Icons.bolt : Icons.power_settings_new, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              online ? 'ONLINE' : 'OFFLINE',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.danger, height: 1.35)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: AppColors.muted, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingCard extends StatefulWidget {
  const _SearchingCard();

  @override
  State<_SearchingCard> createState() => _SearchingCardState();
}

class _SearchingCardState extends State<_SearchingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
      child: const _InfoCard(
        icon: Icons.radar,
        title: 'Looking for orders',
        body: 'Stay on this screen. A new customer order will pop up only because you are online.',
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current delivery', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(order.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(order.statusLabel, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.plum,
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('Open delivery'),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.order, required this.session});

  final DeliveryOrder order;
  final DriverSession session;

  Future<void> _accept(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failure = await session.accept(order);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    session.dismissIncoming(orderId: order.id);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(order: session.active ?? order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.customerName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Text(
                rupees(order.total),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.online, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${order.paymentLabel} · ${timeAgo(order.createdAt)}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Text(order.address, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(order.itemSummary, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: session.acting
                      ? null
                      : () => session.dismissIncoming(orderId: order.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: session.acting ? null : () => _accept(context),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.online),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
              );
            },
            child: const Text('View details'),
          ),
        ],
      ),
    );
  }
}
