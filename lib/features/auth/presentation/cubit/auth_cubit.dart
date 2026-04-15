import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum UserRole { guest, user, admin }

class AuthState extends Equatable {
  const AuthState({this.displayName, this.role = UserRole.guest});

  final String? displayName;
  final UserRole role;

  bool get isAuthenticated => role != UserRole.guest;

  bool get isAdmin => role == UserRole.admin;

  @override
  List<Object?> get props => [displayName, role];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthState());

  // Phần phân quyền được giữ đơn giản: chỉ cần tên hiển thị và vai trò.
  void login({required String displayName, required UserRole role}) {
    emit(AuthState(displayName: displayName, role: role));
  }

  void logout() => emit(const AuthState());
}
