import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/services/supabase_auth_repository.dart';
import '../../../../core/widgets/app_notifications.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  final CatalogRepository _catalogRepository =
      GetIt.instance<CatalogRepository>();
  final SupabaseAuthRepository _authRepository =
      GetIt.instance<SupabaseAuthRepository>();

  bool _isLoading = true;

  // ── Animation ──────────────────────────────────────────
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );

    _animController.forward();
    _checkInitialConnection();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── 1. Kiểm tra kết nối ────────────────────────────────
  Future<void> _checkInitialConnection() async {
    // Delay nhỏ để animation kịp render đẹp
    await Future.delayed(const Duration(milliseconds: 1000));

    final connectivityResult = await Connectivity().checkConnectivity();
    final hasConnection = _hasInternet(connectivityResult);

    if (!mounted) return;

    if (!hasConnection) {
      setState(() => _isLoading = false);
      _showOfflineDialog();
    } else {
      await _restoreSessionAndNavigate(isOffline: false);
    }
  }

  bool _hasInternet(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  // ── 2. Restore session Supabase ────────────────────────
  /// Thứ tự ưu tiên:
  ///  a) Còn session hợp lệ → fetch profile → đi thẳng /home
  ///  b) Không có session → đi /home (guest) hoặc /login
  Future<void> _restoreSessionAndNavigate({required bool isOffline}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (!isOffline) {
        final profile = await _authRepository.restoreSession();
        if (profile != null && mounted) {
          context.read<AuthCubit>().loginSuccess(profile);
          // Không cần warmUp riêng — đi home luôn
          await _warmUpCatalog();
          if (mounted) context.go('/home', extra: false);
          return;
        }
      }

      // Không có session → warmUp catalog rồi về home (guest)
      if (mounted) {
        context.read<AuthCubit>().setUnauthenticated();
      }
      await _warmUpCatalog();
      if (mounted) context.go('/home', extra: isOffline);
    } catch (e) {
      debugPrint('[Splash] error: $e');
      if (mounted) {
        context.read<AuthCubit>().setUnauthenticated();
        context.go('/home', extra: isOffline);
      }
    }
  }

  Future<void> _warmUpCatalog() async {
    try {
      await _catalogRepository.warmUp();
    } catch (e) {
      debugPrint('[Splash] warmUp error: $e');
    }
  }

  // ── 3. Dialog offline ──────────────────────────────────
  void _showOfflineDialog() {
    AppNotifications.showConfirmationDialog(
      context,
      title: 'Mất kết nối mạng',
      content: 'Không có kết nối mạng. Bạn có muốn tiếp tục vào ứng dụng để xem dữ liệu đã tải trước không?',
      confirmText: 'TIẾP TỤC',
      cancelText: 'THOÁT',
      onConfirm: () async {
        await _restoreSessionAndNavigate(isOffline: true);
      },
      onCancel: () {
        _showGoodbyeView();
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
    Future.delayed(const Duration(seconds: 2), () => exit(0));
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFFC6A15B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFC6A15B).withOpacity(0.4),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Fashion Accessories',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Phong cách của bạn, đẳng cấp của chúng tôi',
                style: TextStyle(color: Color(0xFFF6E8C7), fontSize: 13),
              ),
              const SizedBox(height: 48),
              if (_isLoading) ...[
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFC6A15B)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Đang khởi động...',
                  style:
                      TextStyle(color: Color(0xFFF6E8C7), fontSize: 14),
                ),
              ] else ...[
                const Text(
                  'Đang kiểm tra kết nối...',
                  style:
                      TextStyle(color: Color(0xFFF6E8C7), fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
