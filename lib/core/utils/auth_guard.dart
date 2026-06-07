import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_notifications.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';

class AuthGuard {
  static bool requireLogin(BuildContext context) {
    final auth = context.read<AuthCubit>();

    if (auth.state.isAuthenticated) {
      return true;
    }

    AppNotifications.showConfirmationDialog(
      context,
      title: 'Yêu cầu đăng nhập',
      content: 'Vui lòng đăng nhập để tiếp tục.',
      confirmText: 'Đăng nhập',
      onConfirm: () {
        context.push('/login');
      },
    );

    return false;
  }
}
