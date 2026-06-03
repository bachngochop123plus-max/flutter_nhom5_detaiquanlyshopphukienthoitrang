import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/data/catalog_repository.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final CatalogRepository _catalogRepository = GetIt.instance<CatalogRepository>();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    // Giả lập hiệu ứng loading SplashScreen nhẹ
    await Future.delayed(const Duration(milliseconds: 800));

    final connectivityResult = await Connectivity().checkConnectivity();
    final hasConnection = _hasInternet(connectivityResult);

    if (!mounted) return;

    if (!hasConnection) {
      // Offline: Hỏi ý kiến người dùng
      setState(() {
        _isLoading = false;
      });
      _showOfflineDialog();
    } else {
      // Online: Chạy warmUp tải Supabase
      await _loadAndNavigate(isOffline: false);
    }
  }

  bool _hasInternet(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _loadAndNavigate({required bool isOffline}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Gọi warmUp và đợi hoàn thành (đảm bảo cache được nạp đầy đủ)
      await _catalogRepository.warmUp();
    } catch (e) {
      debugPrint('[Splash] Lỗi khi warmUp repository: $e');
    }

    if (!mounted) return;
    
    // Điều hướng vào HomeScreen với flag isOffline tương ứng
    context.go('/home', extra: isOffline);
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Mất kết nối mạng'),
          content: const Text(
            'Không có kết nối mạng. Bạn có muốn tiếp tục vào ứng dụng để xem dữ liệu cũ không?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _showGoodbyeView();
              },
              child: const Text('KHÔNG', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _loadAndNavigate(isOffline: true);
              },
              child: const Text('CÓ', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  void _showGoodbyeView() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          backgroundColor: const Color(0xFF111111),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.favorite, color: Color(0xFFC6A15B), size: 80),
                SizedBox(height: 24),
                Text(
                  'Cảm ơn bạn đã ghé thăm shop!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Hẹn gặp lại bạn lần sau.',
                  style: TextStyle(color: Color(0xFFF6E8C7), fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 2), () {
      exit(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 100,
              color: Color(0xFFC6A15B),
            ),
            const SizedBox(height: 32),
            if (_isLoading) ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC6A15B)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Đang chuẩn bị dữ liệu...',
                style: TextStyle(color: Color(0xFFF6E8C7), fontSize: 16),
              ),
            ] else ...[
              const Text(
                'Chờ kiểm tra kết nối...',
                style: TextStyle(color: Color(0xFFF6E8C7), fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
