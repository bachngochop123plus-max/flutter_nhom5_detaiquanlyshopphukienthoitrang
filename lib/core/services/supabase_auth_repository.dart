import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/database_helper.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';

class SupabaseAuthRepository {
  SupabaseAuthRepository({required DatabaseHelper databaseHelper})
    : _databaseHelper = databaseHelper;

  final DatabaseHelper _databaseHelper;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  Future<({String displayName, UserRole role})> signIn({
    required String email,
    required String password,
  }) async {
    if (_usesSupabase) {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw Exception('Dang nhap Supabase that bai');
      }

      final metadataName = user.userMetadata?['full_name']?.toString().trim();
      var displayName = (metadataName != null && metadataName.isNotEmpty)
          ? metadataName
          : (user.email ?? email).split('@').first;
      var role = UserRole.user;

      try {
        final rpcRole = await Supabase.instance.client.rpc('get_my_role');
        final roleName = rpcRole?.toString().trim().toLowerCase();
        if (roleName == 'admin') {
          role = UserRole.admin;
        }
      } catch (_) {
        // Fall back to profile lookup below.
      }

      try {
        final profileRows = await Supabase.instance.client
            .from('profiles')
            .select('full_name, role_id')
            .eq('id', user.id)
            .limit(1);

        if (profileRows.isNotEmpty) {
          final profile = Map<String, dynamic>.from(profileRows.first as Map);
          final fullName = profile['full_name']?.toString().trim() ?? '';
          if (fullName.isNotEmpty) {
            displayName = fullName;
          }

          if (role != UserRole.admin) {
            final roleName = await _getRoleNameById(profile['role_id'] as num?);
            role = roleName == 'admin' ? UserRole.admin : UserRole.user;
          }
        }
      } catch (_) {
        // Authentication succeeded; fall back to a default app role when
        // profile/role read is blocked or profile data is not ready yet.
      }

      return (displayName: displayName, role: role);
    }

    final localUser = await _databaseHelper.authenticateUser(
      email: email,
      passwordHash: password,
    );
    if (localUser == null) {
      throw Exception('Sai email hoac mat khau');
    }

    final fullName = (localUser['full_name'] as String?)?.trim() ?? '';
    return (
      displayName: fullName.isNotEmpty ? fullName : 'Khach hang',
      role: localUser['role_name'] == 'admin' ? UserRole.admin : UserRole.user,
    );
  }

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (_usesSupabase) {
      await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
      return;
    }

    await _databaseHelper.createUser(
      fullName: fullName,
      email: email,
      passwordHash: password,
    );
  }

  Future<void> signOut() async {
    if (_usesSupabase) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  Future<String> _getRoleNameById(num? roleId) async {
    if (roleId == null) return 'customer';

    try {
      final rows = await Supabase.instance.client
          .from('roles')
          .select('name')
          .eq('id', roleId.toInt())
          .limit(1);
      if (rows.isNotEmpty) {
        final row = Map<String, dynamic>.from(rows.first as Map);
        return row['name']?.toString() ?? 'customer';
      }
    } catch (_) {
      return 'customer';
    }
    return 'customer';
  }
}
