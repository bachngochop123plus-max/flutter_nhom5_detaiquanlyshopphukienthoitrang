import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/base_screen.dart';

class EInvoicePage extends StatelessWidget {
  final int orderId;
  final String? paymentMethod;
  final double? totalAmount;

  const EInvoicePage({
    super.key,
    required this.orderId,
    this.paymentMethod,
    this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return BaseScreen(
      title: 'Hoá đơn điện tử',
      leading: const SizedBox(), // Ẩn nút back
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Color(0xFFC6A15B),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ĐẶT HÀNG THÀNH CÔNG',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D8F6F),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildRow('Mã đơn hàng:', '#${orderId.toString().padLeft(6, '0')}'),
                    _buildRow('Ngày đặt:', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
                    if (paymentMethod != null)
                      _buildRow('Thanh toán:', paymentMethod == 'COD' ? 'Thanh toán khi nhận hàng' : 'Chuyển khoản / Ví điện tử'),
                    if (totalAmount != null)
                      _buildRow(
                        'Tổng thanh toán:',
                        currencyFormat.format(totalAmount),
                        valueStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFB9852E)),
                      ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Cảm ơn bạn đã mua sắm tại cửa hàng.\nĐơn hàng của bạn đang được xử lý và sẽ sớm được giao!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    context.go('/home'); // Quay về trang chủ
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Về trang chủ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC6A15B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    context.go('/profile/orders'); // Xem lịch sử đơn hàng
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Xem lịch sử mua hàng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {TextStyle? valueStyle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
