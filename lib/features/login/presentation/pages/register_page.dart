import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../../core/services/supabase_auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // GlobalKey để quản lý trạng thái của Form
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- LOGIC ĐĂNG KÝ ---
  Future<void> _submit() async {
    // 1. Kiểm tra Validate của Form
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    
    try {
      final authRepository = GetIt.instance.get<SupabaseAuthRepository>();
      
      // Gọi hàm đăng ký từ Repository của bạn
      await authRepository.signUp(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Thông báo thành công
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng ký thành công! Vui lòng kiểm tra email để xác nhận.'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Chuyển hướng sang trang đăng nhập
      context.go('/login');
      
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi đăng ký: ${error.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Đăng ký tài khoản',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey, // Gắn Key vào Form
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tham gia cùng chúng tôi',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // --- HỌ VÀ TÊN ---
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration('Họ và tên', Icons.person_outline),
                        validator: (value) => (value == null || value.isEmpty) ? 'Vui lòng nhập tên' : null,
                      ),
                      const SizedBox(height: 16),

                      // --- EMAIL ---
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration('Email', Icons.email_outlined),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Vui lòng nhập email';
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                            return 'Email không hợp lệ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- MẬT KHẨU ---
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration('Mật khẩu', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) => (value == null || value.length < 6) ? 'Mật khẩu ít nhất 6 ký tự' : null,
                      ),
                      const SizedBox(height: 16),

                      // --- XÁC NHẬN MẬT KHẨU ---
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration('Nhập lại mật khẩu', Icons.lock_reset_outlined),
                        validator: (value) {
                          if (value != _passwordController.text) return 'Mật khẩu không khớp';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // --- NÚT ĐĂNG KÝ ---
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('ĐĂNG KÝ NGAY', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),

                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Đã có tài khoản? Đăng nhập ngay'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Tiện ích để giao diện đồng nhất
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}