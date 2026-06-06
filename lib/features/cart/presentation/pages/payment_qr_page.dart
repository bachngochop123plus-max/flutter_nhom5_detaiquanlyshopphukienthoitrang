import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/base_screen.dart';

class PaymentQrPage extends StatelessWidget {
  final int orderId;
  final double totalAmount;

  const PaymentQrPage({
    super.key,
    required this.orderId,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return BaseScreen(
      title: 'Thanh toán QR',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(), // Quay lại nếu huỷ
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Quét mã QR để thanh toán',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Đơn hàng #${orderId.toString().padLeft(6, '0')}',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              
              // Fake QR Code box
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Icon(
                    Icons.qr_code_2,
                    size: 200,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Số tiền cần thanh toán:',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                currencyFormat.format(totalAmount),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFFB9852E),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nội dung chuyển khoản: THANHTOAN $orderId',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    // Cập nhật Database nếu cần thiết, ở đây mình giả định
                    // đã chuyển khoản xong, chuyển sang E-Invoice
                    context.pushReplacement('/e-invoice?orderId=$orderId');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2D8F6F), // Xanh lá cây
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Tôi đã thanh toán xong',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
