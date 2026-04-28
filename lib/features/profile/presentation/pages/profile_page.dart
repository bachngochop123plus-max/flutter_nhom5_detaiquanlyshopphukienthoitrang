import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Đã thêm
import '../../../../core/services/device_service.dart';
import '../../../../core/widgets/base_screen.dart';
import 'edit_profile_page.dart'; // Đã thêm

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

  // --- BIẾN LƯU THÔNG TIN KHÁCH HÀNG ---
  String _fullName = 'Đang tải...';
  String _phoneNumber = 'Chưa cập nhật';
  String _address = 'Chưa có địa chỉ';

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Tự động load khi khởi tạo
  }

  // --- LOGIC ĐỌC DỮ LIỆU "MÃI MÃI" ---
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fullName = prefs.getString('user_name') ?? 'Bach Ngoc Hop';
      _phoneNumber = prefs.getString('user_phone') ?? 'Chưa cập nhật SĐT';
      _address = prefs.getString('user_address') ?? 'Chưa có địa chỉ';
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return BaseScreen(
      title: 'Hồ sơ',
      isLoading: _loading,
      body: CustomScrollView(
        slivers: [
          // 1. Header Profile Section
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  _buildAvatar(colorScheme),
                  const SizedBox(height: 16),
                  // Hiển thị Tên động từ bộ nhớ
                  Text(_fullName, 
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  // Hiển thị SĐT/Job động
                  Text(_phoneNumber, 
                    style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
                  
                  const SizedBox(height: 16),
                  // Nút chuyển sang trang Chỉnh sửa
                  _buildEditButton(colorScheme),
                  
                  const SizedBox(height: 12),
                  _buildActionButtons(colorScheme),
                ],
              ),
            ),
          ),

          // 2. Contacts Title
          if (_contacts.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Icon(Icons.people_alt_rounded, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Danh bạ bạn bè', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_contacts.length} người', style: textTheme.labelSmall),
                  ],
                ),
              ),
            ),

          // 3. Contacts List
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final contact = _contacts[index];
                  return _buildContactTile(contact, colorScheme);
                },
                childCount: _contacts.length,
              ),
            ),
          ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // --- WIDGET NÚT CHỈNH SỬA (MỚI THÊM) ---
  Widget _buildEditButton(ColorScheme colorScheme) {
    return OutlinedButton.icon(
      onPressed: () async {
        // Đợi kết quả từ trang Edit trả về
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfilePage()),
        );
        // Nếu lưu thành công (result == true), cập nhật lại giao diện
        if (result == true) {
          _loadUserData();
        }
      },
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
      ),
      icon: const Icon(Icons.edit_note, size: 18),
      label: const Text('Thiết lập tài khoản'),
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.primary, width: 3),
          ),
          child: CircleAvatar(
            radius: 55,
            backgroundColor: colorScheme.surface,
            backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
            child: _avatarPath == null 
                ? Icon(Icons.person_rounded, size: 60, color: colorScheme.primary.withOpacity(0.5)) 
                : null,
          ),
        ),
        CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primary,
          child: IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            onPressed: _captureAvatar,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _captureAvatar,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Đổi ảnh'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _loadContacts,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Mời bạn'),
          ),
        ),
      ],
    );
  }

  Widget _buildContactTile(ContactEntry contact, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            contact.displayName[0].toUpperCase(),
            style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(contact.phoneNumber),
        trailing: IconButton.filledTonal(
          icon: const Icon(Icons.send_rounded, size: 20),
          onPressed: () => _deviceService.openSms(
            contact.phoneNumber,
            message: 'Mời bạn trải nghiệm ứng dụng mua sắm phụ kiện thời trang của mình nhé!',
          ),
        ),
      ),
    );
  }
}