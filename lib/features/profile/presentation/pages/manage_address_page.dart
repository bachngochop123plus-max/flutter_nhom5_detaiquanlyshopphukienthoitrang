import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/models/address_model.dart';
import 'package:uuid/uuid.dart'; // Thêm package uuid vào pubspec.yaml

class ManageAddressPage extends StatefulWidget {
  const ManageAddressPage({super.key});

  @override
  State<ManageAddressPage> createState() => _ManageAddressPageState();
}

class _ManageAddressPageState extends State<ManageAddressPage> {
  List<Address> _addresses = [];
  final _titleController = TextEditingController();
  final _detailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('user_addresses_list');
    if (data != null) {
      final List decode = jsonDecode(data);
      setState(() {
        _addresses = decode.map((e) => Address.fromMap(e)).toList();
      });
    }
  }

  Future<void> _saveAndNotify() async {
    final prefs = await SharedPreferences.getInstance();
    final String encode = jsonEncode(_addresses.map((e) => e.toMap()).toList());
    await prefs.setString('user_addresses_list', encode);
    
    // Lưu địa chỉ mặc định vào key riêng để ProfilePage dễ đọc
    final defaultAddr = _addresses.firstWhere((e) => e.isDefault, orElse: () => Address(id: '', title: '', detail: 'Chưa có địa chỉ'));
    await prefs.setString('user_address', defaultAddr.detail);
  }

  void _addNewAddress() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Thêm địa chỉ mới', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Tên gợi nhớ (VD: Nhà riêng)')),
            TextField(controller: _detailController, decoration: const InputDecoration(labelText: 'Địa chỉ chi tiết')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    final newAddr = Address(
                      id: const Uuid().v4(),
                      title: _titleController.text,
                      detail: _detailController.text,
                      isDefault: _addresses.isEmpty, // Nếu là cái đầu tiên thì mặc định luôn
                    );
                    _addresses.add(newAddr);
                    _titleController.clear();
                    _detailController.clear();
                  });
                  _saveAndNotify();
                  Navigator.pop(context);
                },
                child: const Text('THÊM'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Địa chỉ của tôi')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewAddress,
        child: const Icon(Icons.add),
      ),
      body: _addresses.isEmpty 
        ? const Center(child: Text('Bạn chưa có địa chỉ nào'))
        : ListView.builder(
            itemCount: _addresses.length,
            itemBuilder: (context, index) {
              final item = _addresses[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Icon(Icons.location_on, color: item.isDefault ? Colors.red : Colors.grey),
                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(item.detail),
                  trailing: item.isDefault ? const Icon(Icons.check_circle, color: Colors.green) : null,
                  onTap: () {
                    setState(() {
                      for (var a in _addresses) { a.isDefault = false; }
                      item.isDefault = true;
                    });
                    _saveAndNotify();
                  },
                ),
              );
            },
          ),
    );
  }
}