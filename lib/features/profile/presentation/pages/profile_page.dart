import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/device_service.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _deviceService = const DeviceService();
  String? _avatarPath;
  List<ContactEntry> _contacts = const [];
  bool _loading = false;

  Future<void> _captureAvatar() async {
    setState(() => _loading = true);
    final avatarPath = await _deviceService.captureAvatar();
    if (mounted) {
      setState(() {
        _avatarPath = avatarPath;
        _loading = false;
      });
    }
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final contacts = await _deviceService.loadContacts();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    }
  }

  void _logout() {
    context.read<AuthCubit>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;

    // ❌ CHƯA LOGIN
    if (!auth.isAuthenticated) {
      return BaseScreen(
        title: 'Hồ sơ',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_off, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Bạn chưa đăng nhập',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đăng nhập để xem thông tin cá nhân và đơn hàng của bạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push('/login'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Đăng nhập', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.push('/register'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Đăng ký', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ ĐÃ LOGIN
    final profile = auth.profile!;
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    Color getTierColor(String tier) {
      if (tier == 'Kim Cương') return const Color(0xFFE5E4E2); // Platinum/Diamond
      if (tier == 'Vàng') return const Color(0xFFFFD700);
      return const Color(0xFFC0C0C0); // Silver
    }
    
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.tertiary,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              backgroundImage: _avatarPath == null
                                  ? null
                                  : FileImage(File(_avatarPath!)),
                              child: _avatarPath == null
                                  ? Icon(
                                      Icons.person,
                                      size: 50,
                                      color: Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                            ),
                            InkWell(
                              onTap: _captureAvatar,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          profile.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          profile.email,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hạng thành viên
                      _buildSectionHeader('Hạng Thành Viên'),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: getTierColor(profile.membershipTier).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.military_tech,
                                  color: getTierColor(profile.membershipTier),
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hạng ${profile.membershipTier}',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: getTierColor(profile.membershipTier),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tổng chi tiêu: ${currencyFormat.format(profile.totalAmountPurchased)}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Thông tin tài khoản
                      _buildSectionHeader('Thông tin tài khoản'),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.phone_outlined),
                              title: const Text('Số điện thoại'),
                              subtitle: Text(profile.phone ?? 'Chưa cập nhật'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.location_on_outlined),
                              title: const Text('Địa chỉ'),
                              subtitle: Text(profile.address ?? 'Chưa cập nhật'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.account_balance_wallet_outlined),
                              title: const Text('Thông tin ngân hàng'),
                              subtitle: Text(profile.bankInfo ?? 'Chưa cập nhật'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.edit_outlined),
                              title: const Text('Chỉnh sửa hồ sơ'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/profile/edit'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Đơn hàng
                      _buildSectionHeader('Đơn hàng của tôi'),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.shopping_bag_outlined),
                              title: const Text('Lịch sử mua hàng'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/profile/orders'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tiện ích
                      _buildSectionHeader('Tiện ích'),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.contacts_outlined),
                              title: const Text('Mời bạn bè từ danh bạ'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _loadContacts,
                            ),
                          ],
                        ),
                      ),

                      // Hiển thị danh bạ nếu có
                      if (_contacts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSectionHeader('Danh bạ (${_contacts.length})'),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _contacts.length,
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Text(
                                    contact.displayName.isNotEmpty
                                        ? contact.displayName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                title: Text(contact.displayName),
                                subtitle: Text(contact.phoneNumber),
                                trailing: TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Đã gửi lời mời đến ${contact.displayName}'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  child: const Text('Mời'),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Đăng xuất
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.logout),
                          label: const Text(
                            'Đăng xuất',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
