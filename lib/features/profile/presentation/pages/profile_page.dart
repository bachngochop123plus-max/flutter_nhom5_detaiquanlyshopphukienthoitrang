import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/device_service.dart';
import '../../../../core/widgets/base_screen.dart';
import 'edit_profile_page.dart';
import 'bank_account_page.dart';
import 'change_password_page.dart';
import 'manage_address_page.dart';


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _deviceService = const DeviceService();
  String? _avatarPath;
  String _fullName = 'Đang tải...';
  String _phoneNumber = 'Chưa cập nhật';
  String _address = 'Chưa thiết lập'; // 1. Bổ sung biến lưu địa chỉ
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fullName = prefs.getString('user_name') ?? 'Bach Ngoc Hop';
      _phoneNumber = prefs.getString('user_phone') ?? 'Chưa cập nhật';
      _address = prefs.getString('user_address') ?? 'Chưa thiết lập'; // 2. Load dữ liệu địa chỉ
      _avatarPath = prefs.getString('user_avatar');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return BaseScreen(
      title: 'Hồ sơ của tôi',
      isLoading: _loading,
      body: CustomScrollView(
        slivers: [
          // Header với Hero Avatar
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colorScheme.primaryContainer.withOpacity(0.4), colorScheme.surface]),
              ),
              child: Column(
                children: [
                  Hero(
                    tag: 'profile-avatar',
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colorScheme.primary, width: 2)),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                        child: _avatarPath == null ? const Icon(Icons.person, size: 50) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_fullName, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text(_phoneNumber, style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilePage()));
                      if (result == true) _loadUserData();
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Thiết lập tài khoản'),
                  ),
                ],
              ),
            ),
          ),

          // Thẻ Rank & Chi tiêu
          SliverToBoxAdapter(child: _buildLoyaltyCard(colorScheme, textTheme)),

          // Danh sách Menu Chức năng
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 3. THÊM MENU ĐỊA CHỈ NHẬN HÀNG VÀO ĐÂY
                _buildMenuTile(
                  icon: Icons.location_on_rounded,
                  title: 'Địa chỉ nhận hàng',
                  subtitle: _address, // Hiển thị địa chỉ thực tế
                  color: Colors.redAccent,
                  onTap: () async {
                    // Chuyển sang trang thiết lập và đợi kết quả trả về
                    final result = await Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const ManageAddressPage())
                    );
                    if (result == true) _loadUserData(); // Cập nhật lại UI nếu có thay đổi
                  },
                ),
                
                // Menu Ngân hàng
                _buildMenuTile(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Tài khoản ngân hàng',
                  subtitle: 'Quản lý liên kết thanh toán',
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BankAccountPage())),
                ),
                
                // Menu Đổi mật khẩu
                _buildMenuTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Đổi mật khẩu',
                  subtitle: 'Bảo mật tài khoản',
                  color: Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangePasswordPage())),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TỔNG CHI TIÊU', style: textTheme.labelSmall),
                  Text('1.500.000đ', style: textTheme.titleLarge?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
              Chip(label: const Text('Hạng Vàng'), backgroundColor: Colors.amber, labelStyle: const TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: 0.7, minHeight: 8, color: Colors.amber, backgroundColor: colorScheme.surface),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis), // Thêm maxLines để địa chỉ dài không bị tràn
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}