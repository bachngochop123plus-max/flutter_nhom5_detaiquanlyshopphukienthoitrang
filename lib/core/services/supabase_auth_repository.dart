import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/database_helper.dart';
import '../models/user_profile_model.dart';

/// Repository duy nhất xử lý toàn bộ luồng xác thực.
///
/// Ưu tiên Supabase khi được cấu hình; fallback về SQLite local khi không có.
class SupabaseAuthRepository {
  SupabaseAuthRepository({required DatabaseHelper databaseHelper})
      : _databaseHelper = databaseHelper;

  final DatabaseHelper _databaseHelper;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  SupabaseClient get _client => Supabase.instance.client;

  // ══════════════════════════════════════════════════════════
  //  PUBLIC API
  // ══════════════════════════════════════════════════════════

  /// Đăng nhập bằng email + password.
  ///
  /// Trả về [UserProfileModel] đầy đủ (lấy từ [v_users_with_role]).
  /// Ném [AuthException] với [message] tiếng Việt nếu thất bại.
  Future<UserProfileModel> signIn({
    required String email,
    required String password,
  }) async {
    if (_usesSupabase) {
      return _supabaseSignIn(email: email.trim(), password: password);
    }
    return _localSignIn(email: email, password: password);
  }

  /// Đăng ký tài khoản mới.
  ///
  /// Truyền [fullName] vào [raw_user_meta_data] để Trigger DB tự điền vào
  /// bảng [profiles].
  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (_usesSupabase) {
      await _supabaseSignUp(
        fullName: fullName.trim(),
        email: email.trim(),
        password: password,
      );
      return;
    }
    await _databaseHelper.createUser(
      fullName: fullName,
      email: email,
      passwordHash: password,
    );
  }

  /// Đăng xuất.
  Future<void> signOut() async {
    if (_usesSupabase) {
      await _client.auth.signOut();
    }
  }

  /// Kiểm tra session hiện tại khi mở app.
  ///
  /// - Trả về [UserProfileModel] nếu còn session hợp lệ.
  /// - Trả về `null` nếu chưa đăng nhập hoặc token hết hạn.
  Future<UserProfileModel?> restoreSession() async {
    if (!_usesSupabase) return null;

    try {
      final session = _client.auth.currentSession;
      if (session == null) return null;

      // Token còn hạn → fetch profile
      final user = _client.auth.currentUser;
      if (user == null) return null;

      return await _fetchUserProfile(userId: user.id, email: user.email ?? '');
    } catch (e) {
      debugPrint('[Auth] restoreSession error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════
  //  SUPABASE IMPLEMENTATION
  // ══════════════════════════════════════════════════════════

  Future<UserProfileModel> _supabaseSignIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw _AuthAppException('Đăng nhập thất bại. Vui lòng thử lại.');
      }

      return await _fetchUserProfile(userId: user.id, email: user.email ?? email);
    } on AuthException catch (e) {
      throw _AuthAppException(_translateAuthError(e.message));
    } on _AuthAppException {
      rethrow;
    } catch (e) {
      debugPrint('[Auth] signIn unexpected error: $e');
      throw _AuthAppException('Lỗi kết nối. Vui lòng kiểm tra internet.');
    }
  }

  Future<void> _supabaseSignUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      // Supabase có thể trả về user null khi email chưa confirm
      // → coi như thành công, user sẽ nhận email xác nhận
      debugPrint('[Auth] signUp userId=${response.user?.id}');
    } on AuthException catch (e) {
      throw _AuthAppException(_translateAuthError(e.message));
    } catch (e) {
      debugPrint('[Auth] signUp unexpected error: $e');
      throw _AuthAppException('Lỗi kết nối. Vui lòng kiểm tra internet.');
    }
  }

  /// Truy vấn [v_users_with_role] để lấy thông tin đầy đủ của user.
  ///
  /// Nếu view chưa sẵn sàng (race condition trigger), fallback lấy profile
  /// thủ công từ bảng [profiles] + [roles].
  Future<UserProfileModel> _fetchUserProfile({
    required String userId,
    required String email,
  }) async {
    // Thử lấy từ view v_users_with_role trước (đủ thông tin nhất)
    try {
      final rows = await _client
          .from('v_users_with_role')
          .select()
          .eq('id', userId)
          .limit(1);

      if (rows.isNotEmpty) {
        final map = Map<String, dynamic>.from(rows.first as Map);
        // View không có cột email → bổ sung từ auth
        map['email'] = email;

        // Nếu view chưa có img_user (do chưa cập nhật định nghĩa view trong Supabase)
        // thì truy vấn trực tiếp từ bảng profiles làm dự phòng
        if (!map.containsKey('img_user') || map['img_user'] == null) {
          try {
            final profileRow = await _client
                .from('profiles')
                .select('img_user')
                .eq('id', userId)
                .maybeSingle();
            if (profileRow != null && profileRow['img_user'] != null) {
              map['img_user'] = profileRow['img_user'];
            }
          } catch (e) {
            debugPrint('[Auth] Fallback profiles query failed: $e');
          }
        }

        return UserProfileModel.fromMap(map);
      }
    } catch (e) {
      debugPrint('[Auth] v_users_with_role query failed: $e — falling back');
    }

    // Fallback: lấy từ profiles + roles (khi trigger chưa chạy xong)
    return _fetchProfileFallback(userId: userId, email: email);
  }

  Future<UserProfileModel> _fetchProfileFallback({
    required String userId,
    required String email,
  }) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('full_name, phone, address, created_at, role_id, img_user')
          .eq('id', userId)
          .limit(1);

      String fullName = email.split('@').first;
      String roleName = 'customer';
      List<String> permissions = ['place_orders', 'write_reviews'];
      String? phone;
      String? address;
      DateTime? createdAt;
      int? roleId;
      String? imgUser;

      if (rows.isNotEmpty) {
        final p = Map<String, dynamic>.from(rows.first as Map);
        fullName = (p['full_name'] as String?)?.trim() ?? fullName;
        phone = p['phone']?.toString();
        address = p['address']?.toString();
        createdAt = p['created_at'] != null
            ? DateTime.tryParse(p['created_at'].toString())
            : null;
        roleId = (p['role_id'] as num?)?.toInt();
        imgUser = p['img_user']?.toString();

        // Lấy role name từ roles table
        if (roleId != null) {
          try {
            final roleRows = await _client
                .from('roles')
                .select('name, permissions')
                .eq('id', roleId)
                .limit(1);
            if (roleRows.isNotEmpty) {
              final r = Map<String, dynamic>.from(roleRows.first as Map);
              roleName = (r['name'] as String?)?.toLowerCase() ?? 'customer';
              if (r['permissions'] is List) {
                permissions =
                    (r['permissions'] as List).map((e) => e.toString()).toList();
              }
            }
          } catch (_) {}
        }
      }

      return UserProfileModel(
        id: userId,
        email: email,
        fullName: fullName,
        roleName: roleName,
        permissions: permissions,
        phone: phone,
        address: address,
        createdAt: createdAt,
        roleId: roleId,
        imgUser: imgUser,
      );
    } catch (e) {
      debugPrint('[Auth] fetchProfileFallback error: $e');
      // Vẫn trả về profile tối thiểu để không block login
      return UserProfileModel(
        id: userId,
        email: email,
        fullName: email.split('@').first,
        roleName: 'customer',
        permissions: ['place_orders', 'write_reviews'],
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  //  LOCAL SQLITE IMPLEMENTATION (FALLBACK)
  // ══════════════════════════════════════════════════════════

  Future<UserProfileModel> _localSignIn({
    required String email,
    required String password,
  }) async {
    final localUser = await _databaseHelper.authenticateUser(
      email: email,
      passwordHash: password,
    );
    if (localUser == null) {
      throw _AuthAppException('Sai email hoặc mật khẩu.');
    }

    final userIdStr = localUser['id']?.toString() ?? '';
    final userId = int.tryParse(userIdStr) ?? 0;
    final fullName = (localUser['full_name'] as String?)?.trim() ?? '';
    final roleName =
        localUser['role_name']?.toString() == 'admin' ? 'admin' : 'customer';

    final totalAmount = await _databaseHelper.getTotalPurchasedAmount(userId);

    return UserProfileModel(
      id: userIdStr,
      email: email,
      fullName: fullName.isNotEmpty ? fullName : 'Khách hàng',
      roleName: roleName,
      phone: localUser['phone']?.toString(),
      address: localUser['address']?.toString(),
      bankInfo: localUser['bank_info']?.toString(),
      totalAmountPurchased: totalAmount,
      permissions: roleName == 'admin'
          ? ['manage_products', 'manage_orders', 'manage_users',
             'manage_categories', 'view_reports']
          : ['place_orders', 'write_reviews'],
      imgUser: localUser['img_user']?.toString(),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════

  /// Dịch message lỗi từ Supabase Auth sang tiếng Việt thân thiện.
  String _translateAuthError(String raw) {
    final msg = raw.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password') ||
        msg.contains('email not confirmed')) {
      return 'Email hoặc mật khẩu không đúng.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered') ||
        msg.contains('email address is already')) {
      return 'Email này đã được đăng ký. Vui lòng đăng nhập.';
    }
    if (msg.contains('password should be at least')) {
      return 'Mật khẩu phải có ít nhất 6 ký tự.';
    }
    if (msg.contains('unable to validate email address')) {
      return 'Địa chỉ email không hợp lệ.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Bạn đã thử quá nhiều lần. Vui lòng chờ vài phút.';
    }
    if (msg.contains('network') || msg.contains('socket') ||
        msg.contains('connection')) {
      return 'Lỗi kết nối mạng. Vui lòng kiểm tra internet.';
    }

    return 'Đã xảy ra lỗi. Vui lòng thử lại.';
  }
}

// ──────────────────────────────────────────────────────────
//  Internal exception (dùng để pass message tiếng Việt)
// ──────────────────────────────────────────────────────────
class _AuthAppException implements Exception {
  const _AuthAppException(this.message);
  final String message;

  @override
  String toString() => message;
}
