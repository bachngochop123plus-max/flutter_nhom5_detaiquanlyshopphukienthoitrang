/// Model đại diện cho một user đã xác thực, được lấy từ
/// view [v_users_with_role] (JOIN auth.users + profiles + roles).
///
/// Dùng trong [AuthState] để lưu toàn bộ thông tin người dùng sau khi
/// đăng nhập thành công, tránh phải query lại mỗi lần cần.
class UserProfileModel {
  const UserProfileModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roleName,
    required this.permissions,
    this.phone,
    this.address,
    this.bankInfo,
    this.createdAt,
    this.roleId,
    this.totalAmountPurchased = 0.0,
    this.imgUser,
  });

  /// UUID từ auth.users
  final String id;

  /// Email từ auth.users
  final String email;

  /// Tên hiển thị từ profiles.full_name
  final String fullName;

  /// Tên role: 'admin' | 'customer'
  final String roleName;

  /// Danh sách quyền từ roles.permissions (JSONB array)
  final List<String> permissions;

  final String? phone;
  final String? address;
  final String? bankInfo;
  final DateTime? createdAt;
  final int? roleId;
  final double totalAmountPurchased;
  final String? imgUser;

  String get membershipTier {
    if (totalAmountPurchased >= 10000000) return 'Kim Cương';
    if (totalAmountPurchased >= 5000000) return 'Bạch Kim';
    if (totalAmountPurchased >= 2000000) return 'Vàng';
    if (totalAmountPurchased >= 1000000) return 'Bạc';
    return 'Đồng';
  }

  bool get isAdmin => roleName == 'admin';

  bool hasPermission(String permission) => permissions.contains(permission);

  UserProfileModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? roleName,
    List<String>? permissions,
    String? phone,
    String? address,
    String? bankInfo,
    DateTime? createdAt,
    int? roleId,
    double? totalAmountPurchased,
    String? imgUser,
  }) {
    return UserProfileModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      roleName: roleName ?? this.roleName,
      permissions: permissions ?? this.permissions,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      bankInfo: bankInfo ?? this.bankInfo,
      createdAt: createdAt ?? this.createdAt,
      roleId: roleId ?? this.roleId,
      totalAmountPurchased: totalAmountPurchased ?? this.totalAmountPurchased,
      imgUser: imgUser ?? this.imgUser,
    );
  }

  /// Parse từ một row của v_users_with_role
  factory UserProfileModel.fromMap(Map<String, dynamic> map) {
    List<String> parsePermissions(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return [];
    }

    return UserProfileModel(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      fullName: (map['full_name'] as String?)?.trim() ?? '',
      roleName: (map['role_name'] as String?)?.toLowerCase().trim() ?? 'customer',
      permissions: parsePermissions(map['permissions']),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      bankInfo: map['bank_info']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      roleId: (map['role_id'] as num?)?.toInt(),
      totalAmountPurchased: (map['total_amount_purchased'] as num?)?.toDouble() ?? 0.0,
      imgUser: map['img_user']?.toString(),
    );
  }

  /// Tên hiển thị: ưu tiên fullName, fallback sang phần trước @ của email
  String get displayName {
    final trimmed = fullName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return email.split('@').first;
  }

  @override
  String toString() =>
      'UserProfileModel(id: $id, email: $email, role: $roleName, imgUser: $imgUser)';
}
