import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_notifications.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../data/repositories/profile_repository.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _profileRepository = GetIt.instance<ProfileRepository>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _bankInfoController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthCubit>().state.profile;
    _nameController = TextEditingController(text: profile?.fullName ?? '');
    _phoneController = TextEditingController(text: profile?.phone ?? '');
    _addressController = TextEditingController(text: profile?.address ?? '');
    _bankInfoController = TextEditingController(text: profile?.bankInfo ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _bankInfoController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authCubit = context.read<AuthCubit>();
      final currentProfile = authCubit.state.profile;
      
      if (currentProfile == null) {
        throw Exception('Không tìm thấy thông tin người dùng.');
      }

      final newFullName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();
      final newAddress = _addressController.text.trim();
      final newBankInfo = _bankInfoController.text.trim();

      await _profileRepository.updateProfileInfo(
        userId: currentProfile.id,
        fullName: newFullName,
        phone: newPhone.isEmpty ? null : newPhone,
        address: newAddress.isEmpty ? null : newAddress,
        bankInfo: newBankInfo.isEmpty ? null : newBankInfo,
      );

      final updatedProfile = currentProfile.copyWith(
        fullName: newFullName,
        phone: newPhone.isEmpty ? null : newPhone,
        address: newAddress.isEmpty ? null : newAddress,
        bankInfo: newBankInfo.isEmpty ? null : newBankInfo,
      );

      authCubit.updateProfileData(updatedProfile);

      if (mounted) {
        AppNotifications.showSuccessSnackBar(context, 'Cập nhật hồ sơ thành công');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.showErrorSnackBar(context, 'Lỗi: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa hồ sơ'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Thông tin cá nhân',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cập nhật thông tin để chúng tôi phục vụ bạn tốt hơn.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên *',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập họ tên';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 48.0),
                          child: Icon(Icons.location_on_outlined),
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bankInfoController,
                      decoration: const InputDecoration(
                        labelText: 'Thông tin ngân hàng (Tên NH, STK)',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _saveProfile,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Lưu thay đổi',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
