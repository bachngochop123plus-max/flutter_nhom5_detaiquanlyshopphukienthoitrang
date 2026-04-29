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
  
  // Bộ điều khiển để thao tác với bản đồ
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _selectedBranch = _branches.first;
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    // 1. Kiểm tra quyền truy cập vị trí
    final permission = await Permission.locationWhenInUse.request();
    if (!permission.isGranted) {
      return;
    }

    // 2. Kiểm tra dịch vụ định vị (GPS) có đang bật không
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    // 3. Lấy vị trí hiện tại (Đã cập nhật theo chuẩn mới để xóa gạch vàng)
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
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
    // Vẽ đường thẳng từ bạn đến chi nhánh
    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Theme.of(context).colorScheme.primary,
      width: 5,
      points: [_currentLocation, _selectedBranch.position],
    );

    // Tạo các điểm đánh dấu trên bản đồ
    final markers = {
      Marker(
        markerId: const MarkerId('current'),
        position: _currentLocation,
        infoWindow: const InfoWindow(title: 'Vị trí của bạn'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: MarkerId(_selectedBranch.name),
        position: _selectedBranch.position,
        infoWindow: InfoWindow(title: _selectedBranch.name),
      ),
    };

    // Tính toán khoảng cách thực tế
    final distanceKm = Geolocator.distanceBetween(
          _currentLocation.latitude,
          _currentLocation.longitude,
          _selectedBranch.position.latitude,
          _selectedBranch.position.longitude,
        ) / 1000;

    // Ước tính thời gian di chuyển (giả định 25km/h)
    final estimatedMinutes = (distanceKm / 25 * 60).round();

    return BaseScreen(
      title: 'Tìm cửa hàng gần nhất',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<StoreBranch>(
              value: _selectedBranch,
              decoration: const InputDecoration(
                labelText: 'Chọn chi nhánh',
                border: OutlineInputBorder(),
              ),
              items: _branches
                  .map(
                    (branch) => DropdownMenuItem(
                      value: branch,
                      child: Text(branch.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _selectedBranch = value;
                });

                // Di chuyển camera bản đồ đến chi nhánh được chọn
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(value.position, 14),
                );
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
              onMapCreated: (controller) {
                _mapController = controller;
              },
              markers: markers,
              polylines: {polyline},
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: true,
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title, 
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value, 
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}