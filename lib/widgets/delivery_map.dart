import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sheetal_driver_app/core/app_colors.dart';

class DeliveryMap extends StatefulWidget {
  const DeliveryMap({
    super.key,
    required this.address,
    this.latitude,
    this.longitude,
    this.driver,
    this.pinLabel,
  });

  final String address;
  final double? latitude;
  final double? longitude;
  final Position? driver;
  final String? pinLabel;

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  LatLng? _drop;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DeliveryMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.address != widget.address) {
      _loading = true;
      _error = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.latitude != null && widget.longitude != null) {
      setState(() {
        _drop = LatLng(widget.latitude!, widget.longitude!);
        _loading = false;
      });
      return;
    }
    final address = widget.address.trim();
    if (address.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This order has no delivery address.';
      });
      return;
    }
    try {
      final marks = await Geocoding().locationFromAddress(address);
      if (!mounted) return;
      if (marks.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Could not place this address on the map.';
        });
        return;
      }
      setState(() {
        _drop = LatLng(marks.first.latitude, marks.first.longitude);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not place this address on the map. Use Navigate to search it.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final drop = _drop;
    if (drop == null) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          _error ?? 'Map unavailable',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
        ),
      );
    }

    final pinColor = widget.pinLabel == 'Store'
        ? AppColors.purple
        : AppColors.primary;
    final markers = <Marker>[
      Marker(
        point: drop,
        width: 48,
        height: 48,
        child: Icon(
          widget.pinLabel == 'Store'
              ? Icons.storefront_rounded
              : Icons.location_on,
          color: pinColor,
          size: 42,
        ),
      ),
      if (widget.driver != null)
        Marker(
          point: LatLng(widget.driver!.latitude, widget.driver!.longitude),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.purple,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.two_wheeler, color: Colors.white, size: 18),
          ),
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 230,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: drop,
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.easycloud.sheetal_partner',
            ),
            MarkerLayer(markers: markers),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
