import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/device_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _deviceService = const DeviceService();
  
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController(); // Thêm địa chỉ
  final _dobController = TextEditingController();     // Thêm ngày sinh

  String? _avatarPath;
  String? _selectedGender; // Thêm giới tính
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_name') ?? '';
      _phoneController.text = prefs.getString('user_phone') ?? '';
      _addressController.text = prefs.getString('user_address') ?? '';
      _dobController.text = prefs.getString('user_dob') ?? '';
      _selectedGender = prefs.getString('user_gender');
      _avatarPath = prefs.getString('user_avatar');
    });
  }

  // Hàm chọn ngày tháng năm sinh
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)), // Mặc định 18 tuổi
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('user_name', _nameController.text.trim());
      await prefs.setString('user_phone', _phoneController.text.trim());
      await prefs.setString('user_address', _addressController.text.trim());
      await prefs.setString('user_dob', _dobController.text.trim());
      if (_selectedGender != null) {
        await prefs.setString('user_gender', _selectedGender!);
      }
      if (_avatarPath != null) await prefs.setString('user_avatar', _avatarPath!);
      
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thiết lập hồ sơ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final path = await _deviceService.captureAvatar();
                    if (path != null) setState(() => _avatarPath = path);
                  },
                  child: Hero(
                    tag: 'profile-avatar',
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                      child: _avatarPath == null ? const Icon(Icons.camera_alt, size: 40) : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Họ và tên
              TextFormField(
                controller: _nameController, 
                decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 16),

              // Số điện thoại
              TextFormField(
                controller: _phoneController, 
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 16),

              // Giới tính (Dropdown)
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(labelText: 'Giới tính', border: OutlineInputBorder(), prefixIcon: Icon(Icons.wc)),
                items: ['Nam', 'Nữ', 'Khác'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (value) => setState(() => _selectedGender = value),
              ),
              const SizedBox(height: 16),

              // Ngày tháng năm sinh (DatePicker)
              TextFormField(
                controller: _dobController,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Ngày sinh', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                onTap: () => _selectDate(context),
              ),
              const SizedBox(height: 16),

              // Địa chỉ nhận hàng
              TextFormField(
                controller: _addressController, 
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Địa chỉ nhận hàng', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
              ),
              const SizedBox(height: 32),

              // Nút lưu
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _save, 
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}