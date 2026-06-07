import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
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
      title: 'Thanh Toán Trực Tuyến',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => context.pop(), // Quay lại nếu huỷ
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF111111), Color(0xFF1A1A1A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon Header
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.luxuryGold.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.luxuryGold.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 32,
                    color: AppColors.luxuryGold,
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  'QUÉT MÃ QR',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đơn hàng #${orderId.toString().padLeft(6, '0')}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.softGray,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Luxury QR Code Box
                Container(
                  width: 260,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.luxuryGold,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.luxuryGold.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.qr_code_2,
                        size: 200,
                        color: AppColors.deepBlack,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 16, color: Colors.green),
                          const SizedBox(width: 6),
                          Text(
                            'Thanh toán an toàn',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Tổng thanh toán',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softGray),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormat.format(totalAmount),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.luxuryGold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'Nội dung chuyển khoản',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.softGray),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'THANHTOAN $orderId',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      context.pushReplacement('/e-invoice?orderId=$orderId');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.luxuryGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 8,
                    ),
                    child: const Text(
                      'TÔI ĐÃ THANH TOÁN',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
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
