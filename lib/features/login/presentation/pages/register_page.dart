import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/supabase_auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  // ── Controllers & Nodes ────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // ── Password strength ──────────────────────────────────
  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';
  Color _passwordStrengthColor = Colors.transparent;

  // ── Animation ──────────────────────────────────────────
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    _passwordController.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── Password strength meter ────────────────────────────
  void _updatePasswordStrength() {
    final password = _passwordController.text;
    double strength = 0;

    if (password.length >= 6) strength += 0.25;
    if (password.length >= 10) strength += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength += 0.2;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 0.2;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      strength += 0.2;
    }

    String label;
    Color color;
    if (strength <= 0) {
      label = '';
      color = Colors.transparent;
    } else if (strength < 0.4) {
      label = 'Yếu';
      color = const Color(0xFFB00020);
    } else if (strength < 0.7) {
      label = 'Trung bình';
      color = Colors.orange;
    } else {
      label = 'Mạnh';
      color = Colors.green;
    }

    setState(() {
      _passwordStrength = strength.clamp(0.0, 1.0);
      _passwordStrengthLabel = label;
      _passwordStrengthColor = color;
    });
  }

  // ── Submit ─────────────────────────────────────────────
  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final authRepository = GetIt.instance<SupabaseAuthRepository>();
      await authRepository.signUp(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      _showSuccess();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFFC6A15B)],
                ),
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Đăng ký thành công!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tài khoản của bạn đã được tạo.\nVui lòng đăng nhập để tiếp tục.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC6A15B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go('/login');
              },
              child: const Text('Đăng nhập ngay'),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          // ── Gradient header background ──────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: Column(
                            children: [
                              // ── Header ─────────────────
                              _buildHeader(isDark),
                              const SizedBox(height: 32),

                              // ── Form card ──────────────
                              _buildCard(isDark),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('register_back_button'),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/login');
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        const Icon(Icons.person_add_outlined,
            color: Color(0xFFC6A15B), size: 56),
        const SizedBox(height: 12),
        const Text(
          'Tạo tài khoản mới',
          style: TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bắt đầu hành trình thời trang của bạn',
          style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Họ và tên ────────────────────────────────
            _buildTextField(
              id: 'register_name_field',
              controller: _nameController,
              focusNode: _nameFocus,
              nextFocus: _emailFocus,
              label: 'Họ và tên',
              hint: 'Nguyễn Văn A',
              icon: Icons.person_outline,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Vui lòng nhập họ và tên';
                }
                if (v.trim().length < 2) {
                  return 'Tên phải có ít nhất 2 ký tự';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Email ─────────────────────────────────────
            _buildTextField(
              id: 'register_email_field',
              controller: _emailController,
              focusNode: _emailFocus,
              nextFocus: _passwordFocus,
              label: 'Email',
              hint: 'example@email.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Vui lòng nhập email';
                }
                final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                if (!emailRegex.hasMatch(v.trim())) {
                  return 'Email không hợp lệ';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Mật khẩu ─────────────────────────────────
            _buildTextField(
              id: 'register_password_field',
              controller: _passwordController,
              focusNode: _passwordFocus,
              nextFocus: _confirmFocus,
              label: 'Mật khẩu',
              hint: 'Tối thiểu 6 ký tự',
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                if (v.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
                return null;
              },
            ),

            // ── Thanh độ mạnh mật khẩu ───────────────────
            if (_passwordStrength > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _passwordStrength,
                        minHeight: 4,
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _passwordStrengthColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _passwordStrengthLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: _passwordStrengthColor,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // ── Xác nhận mật khẩu ─────────────────────────
            _buildTextField(
              id: 'register_confirm_field',
              controller: _confirmPasswordController,
              focusNode: _confirmFocus,
              label: 'Xác nhận mật khẩu',
              hint: 'Nhập lại mật khẩu',
              icon: Icons.lock_reset_outlined,
              obscureText: _obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Vui lòng xác nhận mật khẩu';
                }
                if (v != _passwordController.text) {
                  return 'Mật khẩu xác nhận không khớp';
                }
                return null;
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 28),

            // ── Nút đăng ký ──────────────────────────────
            _buildSubmitButton(),
            const SizedBox(height: 16),

            // ── Link đăng nhập ───────────────────────────
            TextButton(
              key: const Key('register_login_link'),
              onPressed: () => context.go('/login'),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  children: const [
                    TextSpan(text: 'Đã có tài khoản? '),
                    TextSpan(
                      text: 'Đăng nhập ngay',
                      style: TextStyle(
                        color: Color(0xFFC6A15B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String id,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    FocusNode? nextFocus,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return TextFormField(
      key: Key(id),
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction:
          nextFocus != null ? TextInputAction.next : TextInputAction.done,
      validator: validator,
      onFieldSubmitted: onSubmitted ??
          (v) {
            if (nextFocus != null) {
              FocusScope.of(context).requestFocus(nextFocus);
            }
          },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFC6A15B), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB00020)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB00020), width: 1.8),
        ),
        filled: true,
        fillColor: Colors.grey.withOpacity(0.07),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        gradient: _isSubmitting
            ? null
            : const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFFC6A15B)],
              ),
        color: _isSubmitting ? Colors.grey.shade400 : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isSubmitting
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFFC6A15B).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('register_submit_button'),
          onTap: _isSubmitting ? null : _submit,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Tạo tài khoản',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
