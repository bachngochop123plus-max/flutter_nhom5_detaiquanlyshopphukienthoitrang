import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/widgets/base_screen.dart';

class StoreBranch {
  const StoreBranch({required this.name, required this.position});

  final String name;
  final LatLng position;
}

class StoreLocatorPage extends StatefulWidget {
  const StoreLocatorPage({super.key});

  @override
  State<StoreLocatorPage> createState() => _StoreLocatorPageState();
}

class _StoreLocatorPageState extends State<StoreLocatorPage> {
  final _branches = const [
    StoreBranch(name: 'Quận 1', position: LatLng(10.7769, 106.7009)),
    StoreBranch(name: 'Quận 3', position: LatLng(10.7841, 106.6839)),
    StoreBranch(name: 'Tân Bình', position: LatLng(10.8031, 106.6523)),
  ];

  late StoreBranch _selectedBranch;
  LatLng _currentLocation = const LatLng(10.7769, 106.7009);

  @override
  void initState() {
    super.initState();
    _selectedBranch = _branches.first;
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final permission = await Permission.locationWhenInUse.request();
    if (!permission.isGranted) {
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Theme.of(context).colorScheme.primary,
      width: 5,
      points: [_currentLocation, _selectedBranch.position],
    );

    final markers = {
      Marker(
        markerId: const MarkerId('current'),
        position: _currentLocation,
        infoWindow: const InfoWindow(title: 'Vị trí của bạn'),
      ),
      Marker(
        markerId: MarkerId(_selectedBranch.name),
        position: _selectedBranch.position,
        infoWindow: InfoWindow(title: _selectedBranch.name),
      ),
    };

    final distanceKm =
        Geolocator.distanceBetween(
          _currentLocation.latitude,
          _currentLocation.longitude,
          _selectedBranch.position.latitude,
          _selectedBranch.position.longitude,
        ) /
        1000;
    final estimatedMinutes = (distanceKm / 25 * 60).round();

    return BaseScreen(
      title: 'Tìm cửa hàng gần nhất',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<StoreBranch>(
              value: _selectedBranch,
              decoration: const InputDecoration(labelText: 'Chọn chi nhánh'),
              items: _branches
                  .map(
                    (branch) => DropdownMenuItem(
                      value: branch,
                      child: Text(branch.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() => _selectedBranch = value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    title: 'Khoảng cách',
                    value: '${distanceKm.toStringAsFixed(1)} km',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    title: 'Thời gian',
                    value: '$estimatedMinutes phút',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selectedBranch.position,
                zoom: 13,
              ),
              markers: markers,
              polylines: {polyline},
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
