import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final adminName = authState.displayName ?? 'Admin';

        return BaseScreen(
          title: 'Admin Panel',
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: () {
                context.read<AuthCubit>().logout();
                context.go('/home');
              },
              icon: const Icon(Icons.logout_outlined),
            ),
          ],
          drawer: Drawer(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
            ),
            child: SafeArea(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0E0E0E), Color(0xFF2B2B2B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 40,
                        color: Color(0xFFC6A15B),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Chào mừng, $adminName',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Quản trị viên',
                        style: TextStyle(color: Color(0xFFF6E8C7)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFF7E7C1),
                            const Color(0xFFE6F1FF),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                ),
                _AdminDashboardView(adminName: adminName),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminDashboardView extends StatelessWidget {
  const _AdminDashboardView({required this.adminName});

  final String adminName;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 760;

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 880),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFC6A15B).withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 36,
                color: Color(0xFFC6A15B),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chao mung, $adminName',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    const Text('Quan tri vien'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Chon chuc nang', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Nhan vao tung the de mo dung man hinh quan ly.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (isWide)
                  Row(
                    children: [
                      Expanded(
                        child: _FunctionCard(
                          icon: Icons.inventory_2_outlined,
                          title: 'Quan ly san pham',
                          subtitle: 'Xem danh sach, sua, xoa san pham',
                          color: const Color(0xFFB9852E),
                          onTap: () {
                            context.push('/admin/inventory');
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _FunctionCard(
                          icon: Icons.add_box_outlined,
                          title: 'Them san pham moi',
                          subtitle: 'Mo form tao san pham moi',
                          color: const Color(0xFF2A8A5A),
                          onTap: () {
                            context.push('/admin/inventory/new');
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _FunctionCard(
                        icon: Icons.inventory_2_outlined,
                        title: 'Quan ly san pham',
                        subtitle: 'Xem danh sach, sua, xoa san pham',
                        color: const Color(0xFFB9852E),
                        onTap: () {
                          context.push('/admin/inventory');
                        },
                      ),
                      const SizedBox(height: 14),
                      _FunctionCard(
                        icon: Icons.add_box_outlined,
                        title: 'Them san pham moi',
                        subtitle: 'Mo form tao san pham moi',
                        color: const Color(0xFF2A8A5A),
                        onTap: () {
                          context.push('/admin/inventory/new');
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunctionCard extends StatelessWidget {
  const _FunctionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: color,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Mo'),
            ),
          ],
        ),
      ),
    );
  }
}
