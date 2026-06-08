import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/models/user_profile_model.dart';
import '../../../../core/services/supabase_storage_service.dart';
import '../../../../core/widgets/app_notifications.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../data/repositories/profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = false;
  String? _localDocsDir;

  double? _totalSpent;
  String? _loadedUserId;
  StreamSubscription? _ordersSubscription;

  @override
  void initState() {
    super.initState();
    _loadTotalSpent();
    _initLocalDocsDir();
  }

  Future<void> _initLocalDocsDir() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (mounted) {
        setState(() {
          _localDocsDir = dir.path;
        });
      }
    } catch (e) {
      debugPrint('Lỗi lấy thư mục ứng dụng: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTotalSpent();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTotalSpent() async {
    final auth = context.read<AuthCubit>().state;
    if (auth.isAuthenticated && auth.profile != null) {
      final currentId = auth.profile!.id;
      if (_loadedUserId == currentId) return;
      _loadedUserId = currentId;
      _subscribeToOrders(currentId);
    } else {
      _ordersSubscription?.cancel();
      _ordersSubscription = null;
      _totalSpent = null;
      _loadedUserId = null;
    }
  }

  void _subscribeToOrders(String userId) {
    _ordersSubscription?.cancel();
    if (SupabaseConfig.instance.isConfigured) {
      try {
        _ordersSubscription = Supabase.instance.client
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId)
            .listen((List<Map<String, dynamic>> data) {
              double total = 0.0;
              for (var row in data) {
                if (row['status'] == 'delivered') {
                  final amt = row['total_amount'];
                  if (amt != null) {
                    total += (amt as num).toDouble();
                  }
                }
              }
              if (mounted) {
                setState(() {
                  _totalSpent = total;
                });
              }
            }, onError: (e) {
              debugPrint('[ProfilePage] Realtime stream error: $e. Falling back to one-time fetch.');
              _loadTotalSpentLocalOrSupabase(userId);
            });
      } catch (e) {
        debugPrint('[ProfilePage] Error setting up realtime stream: $e');
        _loadTotalSpentLocalOrSupabase(userId);
      }
    } else {
      _loadTotalSpentLocalOrSupabase(userId);
    }
  }

  Future<void> _loadTotalSpentLocalOrSupabase(String userId) async {
    try {
      final spent = await DatabaseHelper.instance.getUserTotalSpent(userId);
      if (mounted) {
        setState(() {
          _totalSpent = spent;
        });
      }
    } catch (e) {
      debugPrint('[ProfilePage] Error loading spent: $e');
    }
  }

  Future<void> _refreshTotalSpent() async {
    if (_loadedUserId != null) {
      if (SupabaseConfig.instance.isConfigured) {
        // Just re-subscribe or query to ensure fresh state
        _subscribeToOrders(_loadedUserId!);
      } else {
        _loadTotalSpentLocalOrSupabase(_loadedUserId!);
      }
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final auth = context.read<AuthCubit>().state;
    if (!auth.isAuthenticated) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _loading = true);

    try {
      final userId = auth.profile!.id;
      final oldFileName = auth.profile!.imgUser;
      String? dbImgUserValue;

      if (SupabaseConfig.instance.isConfigured) {
        // Tải lên Supabase Storage
        final storageService = GetIt.instance<SupabaseStorageService>();
        dbImgUserValue = await storageService.uploadUserAvatar(
          userId: userId,
          file: pickedFile,
          oldFileName: oldFileName,
        );
      } else {
        // Lưu local cho người dùng SQLite
        final directory = await getApplicationDocumentsDirectory();

        // 1. Xóa ảnh cũ nếu có trong thư mục local
        if (oldFileName != null && oldFileName.isNotEmpty) {
          try {
            final oldPath = oldFileName.contains('/') || oldFileName.contains('\\')
                ? oldFileName
                : '${directory.path}/$oldFileName';
            final oldFile = File(oldPath);
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
          } catch (e) {
            debugPrint('Lỗi xóa ảnh local cũ: $e');
          }
        }

        // 2. Lưu ảnh mới vào thư mục local
        final extension = pickedFile.name.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
        final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}$extension';
        await File(pickedFile.path).copy('${directory.path}/$fileName');

        // Chỉ lưu tên file vào database
        dbImgUserValue = fileName;
      }

      if (dbImgUserValue == null) {
        throw Exception('Không thể lưu ảnh đại diện. Vui lòng thử lại.');
      }

      // Lưu vào Database (Supabase profiles hoặc local users)
      final profileRepository = GetIt.instance<ProfileRepository>();
      await profileRepository.updateAvatar(userId: userId, imgUrl: dbImgUserValue);

      if (!mounted) return;

      // Cập nhật state AuthCubit
      final updatedProfile = auth.profile!.copyWith(imgUser: dbImgUserValue);
      context.read<AuthCubit>().updateProfileData(updatedProfile);

      AppNotifications.showSuccessSnackBar(context, 'Cập nhật ảnh đại diện thành công');
    } catch (e) {
      if (mounted) {
        AppNotifications.showErrorSnackBar(context, 'Lỗi cập nhật ảnh đại diện: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ImageProvider? _getAvatarProvider(UserProfileModel profile) {
    final imgUser = profile.imgUser;
    if (imgUser == null || imgUser.isEmpty) return null;

    if (imgUser.startsWith('http://') || imgUser.startsWith('https://')) {
      return CachedNetworkImageProvider(imgUser);
    }

    if (SupabaseConfig.instance.isConfigured) {
      try {
        // Nếu tên ảnh bắt đầu bằng 'avatar_', đây là ảnh do user tự tải lên và nằm trong thư mục avatars/userId/
        // Ngược lại, nếu là ảnh mẫu hoặc ảnh hệ thống (ví dụ: 'Avatar_1.webp'), nó nằm trong thư mục 'Img_Product/' của bucket
        final String path;
        if (imgUser.startsWith('avatar_')) {
          path = 'avatars/${profile.id}/$imgUser';
        } else if (imgUser.startsWith('Img_Product/')) {
          path = imgUser;
        } else {
          path = 'Img_Product/$imgUser';
        }
        final publicUrl = Supabase.instance.client.storage
            .from('Img_products')
            .getPublicUrl(path);
        return CachedNetworkImageProvider(publicUrl);
      } catch (e) {
        debugPrint('Lỗi lấy public URL cho avatar: $e');
        return null;
      }
    } else {
      if (imgUser.contains('/') || imgUser.contains('\\')) {
        return FileImage(File(imgUser));
      }
      if (_localDocsDir != null) {
        return FileImage(File('$_localDocsDir/$imgUser'));
      }
      return null;
    }
  }

  void _changeAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E), // Vibe đen tối giản/Chanel sang trọng
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'ĐỔI ẢNH ĐẠI DIỆN',
                  style: TextStyle(
                    color: Color(0xFFD8B267),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
                  title: const Text(
                    'Chụp ảnh mới',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadAvatar(ImageSource.camera);
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                  title: const Text(
                    'Chọn từ thư viện',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadAvatar(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.red[300],
                    ),
                    child: const Text(
                      'HỦY BỎ',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _logout() {
    AppNotifications.showConfirmationDialog(
      context,
      title: 'Xác nhận đăng xuất',
      content: 'Bạn có chắc chắn muốn đăng xuất không?',
      confirmText: 'Đăng xuất',
      cancelText: 'Hủy',
      isDanger: true,
      onConfirm: () {
        context.read<AuthCubit>().logout();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;

    // Tông màu: Nền vàng Gold sang trọng, chi tiết và các card chứa thông tin sáng màu dễ nhìn
    const luxuryGoldBgStart = Color(0xFFFDF0CD); // Vàng gold sáng ánh kim
    const luxuryGoldBgEnd = Color(0xFFD8B267);   // Vàng gold hoàng gia trầm
    const luxuryGoldAccent = Color(0xFFB8860B);  // Vàng Gold đậm làm điểm nhấn
    
    // Card sáng màu Glassmorphic mờ nhẹ, hòa hợp tuyệt hảo với nền vàng
    final luxuryLightCard = Colors.white.withValues(alpha: 0.82); 
    
    // Màu chữ trên nền Vàng
    const textOnGoldPrimary = Color(0xFF1E1E1E);
    const textOnGoldSecondary = Color(0xFF5A5A5A);
    
    // Màu chữ trong Card sáng màu
    const textOnCardPrimary = Color(0xFF1C1C1E);
    const textOnCardSecondary = Color(0xFF5E5E5E);

    // ❌ CHƯA LOGIN
    if (!auth.isAuthenticated) {
      return BaseScreen(
        title: 'Hồ sơ',
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [luxuryGoldBgStart, luxuryGoldBgEnd],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: luxuryLightCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: luxuryGoldAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_person_outlined, size: 64, color: luxuryGoldAccent),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'KHÔNG GIAN THÀNH VIÊN',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textOnCardPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Đăng nhập để chiêm ngưỡng thẻ đặc quyền và quản lý đơn hàng của bạn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textOnCardSecondary, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [luxuryGoldAccent, Color(0xFFF1D498)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: luxuryGoldAccent.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () => context.push('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Đăng nhập ngay',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.push('/register'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: luxuryGoldAccent, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Tạo tài khoản mới',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: luxuryGoldAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ✅ ĐÃ LOGIN
    final profile = auth.profile!;
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    final double totalSpent = _totalSpent ?? profile.totalAmountPurchased;
    
    String currentTier = 'Đồng';
    if (totalSpent >= 10000000) {
      currentTier = 'Kim Cương';
    } else if (totalSpent >= 5000000) {
      currentTier = 'Bạch Kim';
    } else if (totalSpent >= 2000000) {
      currentTier = 'Vàng';
    } else if (totalSpent >= 1000000) {
      currentTier = 'Bạc';
    }
    String nextTier = '';
    double nextTierThreshold = 0;
    double prevTierThreshold = 0;
    double progressPercent = 0.0;
    double neededMore = 0;

    if (currentTier == 'Đồng') {
      nextTier = 'Bạc';
      prevTierThreshold = 0;
      nextTierThreshold = 1000000;
      progressPercent = (totalSpent / nextTierThreshold).clamp(0.0, 1.0);
      neededMore = nextTierThreshold - totalSpent;
    } else if (currentTier == 'Bạc') {
      nextTier = 'Vàng';
      prevTierThreshold = 1000000;
      nextTierThreshold = 2000000;
      progressPercent = ((totalSpent - prevTierThreshold) / (nextTierThreshold - prevTierThreshold)).clamp(0.0, 1.0);
      neededMore = nextTierThreshold - totalSpent;
    } else if (currentTier == 'Vàng') {
      nextTier = 'Bạch Kim';
      prevTierThreshold = 2000000;
      nextTierThreshold = 5000000;
      progressPercent = ((totalSpent - prevTierThreshold) / (nextTierThreshold - prevTierThreshold)).clamp(0.0, 1.0);
      neededMore = nextTierThreshold - totalSpent;
    } else if (currentTier == 'Bạch Kim') {
      nextTier = 'Kim Cương';
      prevTierThreshold = 5000000;
      nextTierThreshold = 10000000;
      progressPercent = ((totalSpent - prevTierThreshold) / (nextTierThreshold - prevTierThreshold)).clamp(0.0, 1.0);
      neededMore = nextTierThreshold - totalSpent;
    } else {
      nextTier = '';
      nextTierThreshold = 10000000;
      progressPercent = 1.0;
      neededMore = 0;
    }

    // Gradient của thẻ VIP tối màu tương ứng với Hạng (Tương phản cao cực đẹp trên nền vàng)
    LinearGradient getCardGradient(String tier) {
      switch (tier) {
        case 'Kim Cương':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0E12), Color(0xFF1A1C23), Color(0xFF050608)],
          );
        case 'Bạch Kim':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E242B), Color(0xFF333D49), Color(0xFF12161A)],
          );
        case 'Vàng':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E220D), Color(0xFF423315), Color(0xFF1A1408)],
          );
        case 'Bạc':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF242424), Color(0xFF3A3A3A), Color(0xFF141414)],
          );
        default: // Đồng
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B160C), Color(0xFF3B2012), Color(0xFF170C06)],
          );
      }
    }

    Color getTierBadgeColor(String tier) {
      switch (tier) {
        case 'Kim Cương':
          return const Color(0xFF9EE8FF);
        case 'Bạch Kim':
          return const Color(0xFFE5E4E2);
        case 'Vàng':
          return const Color(0xFFFFD700);
        case 'Bạc':
          return const Color(0xFFC0C0C0);
        default:
          return const Color(0xFFE58742);
      }
    }

    IconData getTierIcon(String tier) {
      switch (tier) {
        case 'Kim Cương':
          return Icons.diamond_outlined;
        case 'Bạch Kim':
          return Icons.military_tech;
        case 'Vàng':
          return Icons.workspace_premium;
        case 'Bạc':
          return Icons.shield_outlined;
        default:
          return Icons.star_border_purple500_outlined;
      }
    }

    final String memberId = 'VIP-${(profile.id.length > 8) ? profile.id.substring(profile.id.length - 8).toUpperCase() : "001A8F9C"}';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [luxuryGoldBgStart, luxuryGoldBgEnd],
          ),
        ),
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // ── APPBAR SANG TRỌNG NỀN VÀNG TRONG SUỐT ──────────────────
                SliverAppBar(
                  expandedHeight: 240,
                  pinned: true,
                  backgroundColor: luxuryGoldBgStart,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    title: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: 1.0,
                      child: Text(
                        profile.displayName,
                        style: const TextStyle(
                          color: textOnGoldPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    background: Stack(
                      children: [
                        Positioned(
                          top: -60,
                          left: -60,
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 50),
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF1E1E1E), luxuryGoldAccent],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.12),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        )
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 46,
                                      backgroundColor: Colors.white,
                                      backgroundImage: _getAvatarProvider(profile),
                                      child: _loading
                                          ? const CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(luxuryGoldAccent),
                                            )
                                          : (profile.imgUser == null
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 46,
                                                  color: Color(0xFF1E1E1E),
                                                )
                                              : null),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _changeAvatarOptions,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1E1E1E),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 14,
                                        color: luxuryGoldBgStart,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                profile.displayName,
                                style: const TextStyle(
                                  color: textOnGoldPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                profile.email,
                                style: const TextStyle(
                                  color: textOnGoldSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── NỘI DUNG PROFILE CHÍNH ─────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. THẺ VIP ĐEN TUYỀN HUYỀN BÍ (Metallic Black VIP Card) - Vẫn giữ nguyên vì cực kỳ sang trọng
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            gradient: getCardGradient(currentTier),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: getTierBadgeColor(currentTier).withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              children: [
                                Positioned(
                                  bottom: -50,
                                  right: -30,
                                  child: Opacity(
                                    opacity: 0.08,
                                    child: Icon(
                                      getTierIcon(currentTier),
                                      size: 190,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                getTierIcon(currentTier),
                                                color: getTierBadgeColor(currentTier),
                                                size: 22,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${currentTier.toUpperCase()} MEMBER',
                                                style: TextStyle(
                                                  color: getTierBadgeColor(currentTier),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  letterSpacing: 2.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Gold Smart Chip
                                          Container(
                                            width: 36,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFFE5C060), Color(0xFFF3E5AB), Color(0xFFB8860B)],
                                              ),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: CustomPaint(
                                              painter: CardChipPainter(),
                                            ),
                                          ),
                                        ],
                                      ),

                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                                        child: Text(
                                          memberId,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            fontFamily: 'monospace',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 3.0,
                                          ),
                                        ),
                                      ),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'HỌ VÀ TÊN',
                                                  style: TextStyle(
                                                    color: Colors.white30,
                                                    fontSize: 8,
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  profile.displayName.toUpperCase(),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              const Text(
                                                'TỔNG CHI TIÊU',
                                                style: TextStyle(
                                                  color: Colors.white30,
                                                  fontSize: 8,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                currencyFormat.format(totalSpent),
                                                style: TextStyle(
                                                  color: getTierBadgeColor(currentTier),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 2. TIẾN TRÌNH THĂNG HẠNG (SÁNG MÀU GLASSMORPHIC)
                        if (nextTier.isNotEmpty) ...[
                          _buildSectionHeader('BƯỚC ĐƯỜNG ĐẶC QUYỀN'),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: luxuryLightCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Hạng hiện tại: $currentTier',
                                      style: const TextStyle(
                                        color: textOnCardPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    Text(
                                      'Hạng tiếp theo: $nextTier',
                                      style: TextStyle(
                                        color: nextTier == 'Kim Cương' ? const Color(0xFF0083B0) : luxuryGoldAccent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 7,
                                    color: Colors.black.withValues(alpha: 0.07),
                                    child: Stack(
                                      children: [
                                        FractionallySizedBox(
                                          widthFactor: progressPercent,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  nextTier == 'Bạc' ? const Color(0xFFCD7F32) : const Color(0xFFD4AF37),
                                                  getTierBadgeColor(nextTier),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Bạn cần tích luỹ thêm ${currencyFormat.format(neededMore)} để nâng cấp lên thẻ $nextTier.',
                                  style: const TextStyle(
                                    color: textOnCardSecondary,
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else ...[
                          // Thẻ tối cao (Sáng màu)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: luxuryLightCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.workspace_premium, color: getTierBadgeColor(currentTier), size: 32),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'HẠNG ĐẶC QUYỀN TỐI CAO: $currentTier',
                                        style: TextStyle(
                                          color: getTierBadgeColor(currentTier) == const Color(0xFFB9F2FF) ? const Color(0xFF007A9B) : luxuryGoldAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'Hệ thống trân trọng tri ân sự đồng hành đặc biệt của quý khách với những ưu đãi cao cấp nhất.',
                                        style: TextStyle(
                                          color: textOnCardSecondary,
                                          fontSize: 11.5,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // 3. DANH SÁCH CHỨC NĂNG (SÁNG MÀU GLASSMORPHIC)
                        _buildSectionHeader('THÔNG TIN TÀI KHOẢN'),
                        Container(
                          decoration: BoxDecoration(
                            color: luxuryLightCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildListTile(
                                icon: Icons.phone_outlined,
                                title: 'Số điện thoại',
                                value: profile.phone ?? 'Chưa cập nhật',
                              ),
                              _buildDivider(),
                              _buildListTile(
                                icon: Icons.location_on_outlined,
                                title: 'Địa chỉ nhận hàng',
                                value: profile.address ?? 'Chưa cập nhật',
                              ),
                              _buildDivider(),
                              _buildListTile(
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Tài khoản ngân hàng',
                                value: profile.bankInfo ?? 'Chưa cập nhật',
                              ),
                              _buildDivider(),
                              _buildListTile(
                                icon: Icons.edit_note_outlined,
                                title: 'Chỉnh sửa thông tin cá nhân',
                                onTap: () async {
                                  await context.push('/profile/edit');
                                  _refreshTotalSpent();
                                },
                                showChevron: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        _buildSectionHeader('ĐƠN HÀNG & GIAO DỊCH'),
                        Container(
                          decoration: BoxDecoration(
                            color: luxuryLightCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildListTile(
                                icon: Icons.history_edu_outlined,
                                title: 'Lịch sử mua hàng',
                                onTap: () async {
                                  await context.push('/profile/orders');
                                  _refreshTotalSpent();
                                },
                                showChevron: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 4. NÚT ĐĂNG XUẤT TRẮNG SỮA VIỀN ĐỎ SANG TRỌNG
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _logout,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.85),
                              foregroundColor: const Color(0xFFC62828),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: Color(0xFFC62828), width: 1.0),
                              ),
                              elevation: 1.5,
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text(
                              'Đăng xuất tài khoản',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_loading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(luxuryGoldAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 6, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E1E1E),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.black.withValues(alpha: 0.05),
      indent: 52,
      endIndent: 16,
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? value,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    final hasAction = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 15.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFFB8860B), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: const Color(0xFF1E1E1E),
                      fontWeight: hasAction ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13.5,
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF5E5E5E),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB8860B),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class CardChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF70541C).withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(size.width * 0.25, 0), Offset(size.width * 0.25, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.5, 0), Offset(size.width * 0.5, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), paint);
    
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), paint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65), paint);

    final centerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.3,
        height: size.height * 0.4,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(centerRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
