import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/database_helper.dart';

class ProfileRepository {
  final DatabaseHelper _databaseHelper;

  ProfileRepository({required DatabaseHelper databaseHelper})
      : _databaseHelper = databaseHelper;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;
  SupabaseClient get _client => Supabase.instance.client;

  /// Cập nhật thông tin người dùng trong bảng profiles (hoặc users nếu offline)
  Future<void> updateProfileInfo({
    required String userId,
    required String fullName,
    String? phone,
    String? address,
    String? bankInfo,
  }) async {
    try {
      // Nếu userId là số nguyên → đây là user local SQLite
      final localId = int.tryParse(userId);
      final isLocalUser = localId != null;

      if (!isLocalUser && _usesSupabase) {
        // User Supabase (UUID) → cập nhật lên Supabase
        await _client.from('profiles').update({
          'full_name': fullName,
          'phone': phone,
          'address': address,
        }).eq('id', userId);
      } else if (isLocalUser) {
        // User local SQLite → cập nhật vào SQLite
        final db = await _databaseHelper.database;
        await db.update(
          'users',
          {
            'full_name': fullName,
            'phone': phone,
            'address': address,
            'bank_info': bankInfo,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    } catch (e) {
      debugPrint('[ProfileRepository] updateProfileInfo error: $e');
      throw Exception('Lỗi cập nhật thông tin: $e');
    }
  }

  /// Cập nhật ảnh đại diện người dùng
  Future<void> updateAvatar({
    required String userId,
    required String? imgUrl,
  }) async {
    try {
      final localId = int.tryParse(userId);
      final isLocalUser = localId != null;

      if (!isLocalUser && _usesSupabase) {
        await _client.from('profiles').update({
          'img_user': imgUrl,
        }).eq('id', userId);
      } else if (isLocalUser) {
        final db = await _databaseHelper.database;
        await db.update(
          'users',
          {
            'img_user': imgUrl,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    } catch (e) {
      debugPrint('[ProfileRepository] updateAvatar error: $e');
      throw Exception('Lỗi cập nhật ảnh đại diện: $e');
    }
  }
}
