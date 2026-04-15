import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/device_service.dart';
import '../../../../core/widgets/base_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Hồ sơ',
      isLoading: _loading,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              backgroundImage: _avatarPath == null
                  ? null
                  : FileImage(File(_avatarPath!)),
              child: _avatarPath == null
                  ? const Icon(Icons.person, size: 42)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _captureAvatar,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Chụp avatar bằng camera'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadContacts,
            icon: const Icon(Icons.contacts_outlined),
            label: const Text('Mời bạn bè từ danh bạ'),
          ),
          const SizedBox(height: 24),
          if (_contacts.isNotEmpty)
            Text('Danh bạ', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._contacts.map(
            (contact) => Card(
              child: ListTile(
                title: Text(contact.displayName),
                subtitle: Text(contact.phoneNumber),
                trailing: IconButton(
                  icon: const Icon(Icons.sms_outlined),
                  onPressed: () => _deviceService.openSms(
                    contact.phoneNumber,
                    message:
                        'Mời bạn trải nghiệm ứng dụng phụ kiện thời trang của mình.',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
