import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/user_profile_model.dart';

import '../../../../core/services/supabase_auth_repository.dart';

// ─────────────────────────────────────────────────────────
//  Backward-compat enum (dùng trong router guard)
// ─────────────────────────────────────────────────────────
enum UserRole { guest, user, admin }

// ─────────────────────────────────────────────────────────
//  AuthStatus
// ─────────────────────────────────────────────────────────
enum AuthStatus {
  /// Chưa xác định (đang check session lúc khởi động)
  unknown,

  /// Chưa đăng nhập
  unauthenticated,

  /// Đang xử lý (loading)
  loading,

  /// Đã đăng nhập thành công
  authenticated,

  /// Lỗi
  error,
}

// ─────────────────────────────────────────────────────────
//  AuthState
// ─────────────────────────────────────────────────────────
class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.profile,
    this.errorMessage,
  });

  final AuthStatus status;

  /// Thông tin đầy đủ user sau khi đăng nhập
  final UserProfileModel? profile;

  /// Thông báo lỗi thân thiện (đã được dịch sang tiếng Việt)
  final String? errorMessage;

  // ── Shortcuts ──────────────────────────────────────────

  bool get isAuthenticated => status == AuthStatus.authenticated && profile != null;

  bool get isLoading => status == AuthStatus.loading;

  bool get isAdmin => profile?.isAdmin ?? false;

  bool get isUnknown => status == AuthStatus.unknown;

  /// Backward-compat: dùng trong router/UI cũ
  String get displayName => profile?.displayName ?? '';

  UserRole get role {
    if (!isAuthenticated) return UserRole.guest;
    return isAdmin ? UserRole.admin : UserRole.user;
  }

  AuthState copyWith({
    AuthStatus? status,
    UserProfileModel? profile,
    String? errorMessage,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      profile: clearProfile ? null : (profile ?? this.profile),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, profile, errorMessage];
}

// ─────────────────────────────────────────────────────────
//  AuthCubit
// ─────────────────────────────────────────────────────────
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthState());

  final SupabaseAuthRepository _authRepository;

  // ── Gọi từ SupabaseAuthRepository sau khi đăng nhập / restore session ──
  void loginSuccess(UserProfileModel profile) {
    emit(AuthState(status: AuthStatus.authenticated, profile: profile));
  }

  // ── Cập nhật thông tin profile khi người dùng chỉnh sửa ──
  void updateProfileData(UserProfileModel updatedProfile) {
    if (state.isAuthenticated) {
      emit(state.copyWith(profile: updatedProfile));
    }
  }

  // ── Trạng thái loading (khóa nút bấm) ──
  void setLoading() {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
  }

  // ── Báo lỗi với message tiếng Việt ──
  void setError(String message) {
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      errorMessage: message,
      clearProfile: true,
    ));
  }

  // ── Đăng xuất ──
  void logout() {
    emit(const AuthState(status: AuthStatus.unauthenticated));
    _authRepository.signOut().catchError((_) {});
  }

  // ── Không có session (mở app lần đầu / hết hạn) ──
  void setUnauthenticated() {
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  // ─── Backward-compat: giữ lại để code cũ không bị lỗi ────────────────
  void login({required String displayName, required UserRole role}) {
    // Nếu code cũ vẫn gọi hàm này, tạo một profile giả tối thiểu
    final fakeProfile = UserProfileModel(
      id: '',
      email: '',
      fullName: displayName,
      roleName: role == UserRole.admin ? 'admin' : 'customer',
      permissions: [],
    );
    emit(AuthState(status: AuthStatus.authenticated, profile: fakeProfile));
  }
}
