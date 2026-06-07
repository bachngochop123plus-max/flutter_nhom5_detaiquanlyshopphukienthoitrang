import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/widgets/app_notifications.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/cart_cubit.dart';
import '../../../../core/models/product.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _addressController = TextEditingController();
  final _db = GetIt.instance<DatabaseHelper>();
  final _catalogRepository = GetIt.instance<CatalogRepository>();

  String _paymentMethod = 'COD';
  bool _isPlacingOrder = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthCubit>().state.profile;
    if (profile?.address != null) {
      _addressController.text = profile!.address!;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      AppNotifications.showErrorSnackBar(context, 'Vui lòng nhập địa chỉ giao hàng');
      return;
    }

    final cartState = context.read<CartCubit>().state;
    final selectedItems = cartState.selectedItems;
    if (selectedItems.isEmpty) return;

    setState(() => _isPlacingOrder = true);

    try {
      final profile = context.read<AuthCubit>().state.profile;
      final userIdStr = profile?.id ?? '1';
      final userId = int.tryParse(userIdStr) ?? 1;

      // ── Bước 1: Resolve variant IDs ─────────────────────────────────────
      List<({int variantId, int quantity, double price})> orderItems = [];

      for (final item in selectedItems) {
        final variantId = await _db.getVariantId(
          item.product.id,
          item.selectedColor,
          item.selectedSize,
        );

        orderItems.add((
          variantId: variantId,
          quantity: item.quantity,
          price: item.product.price,
        ));
      }

      // ── Bước 2: Kiểm tra tồn kho trước khi đặt ──────────────────────────
      final stockCheck = orderItems
          .map((e) => (variantId: e.variantId, quantity: e.quantity))
          .toList();
      final outOfStockIds = await _db.checkStockAvailability(stockCheck);

      if (outOfStockIds.isNotEmpty && mounted) {
        // Tìm tên sản phẩm tương ứng với variant hết hàng
        final outOfStockNames = <String>[];
        for (var i = 0; i < orderItems.length; i++) {
          if (outOfStockIds.contains(orderItems[i].variantId)) {
            outOfStockNames.add(selectedItems[i].product.name);
          }
        }

        setState(() => _isPlacingOrder = false);
        _showOutOfStockDialog(outOfStockNames);
        return;
      }

      // ── Bước 3: Đặt hàng ────────────────────────────────────────────────
      final orderId = await _db.placeOrder(
        userId: userId,
        shippingAddress: address,
        paymentMethod: _paymentMethod,
        items: orderItems,
        supabaseUserId: profile?.id,
      );

      if (!mounted) return;

      final totalAmount = cartState.selectedTotal;
      context.read<CartCubit>().removeSelectedItems();

      // Cập nhập lại stock trong bộ nhớ sau khi đặt hàng thành công
      unawaited(_catalogRepository.refreshProducts().catchError((_) => <Product>[]));

      if (_paymentMethod == 'COD') {
        context.go('/e-invoice?orderId=$orderId&method=$_paymentMethod&total=$totalAmount');
      } else {
        context.go('/payment-qr?orderId=$orderId&total=$totalAmount');
      }
    } on InsufficientStockException catch (e) {
      // Lỗi hết hàng được phát hiện tại DB layer (race condition)
      if (!mounted) return;
      AppNotifications.showErrorSnackBar(context, e.toString());
    } catch (e) {
      if (!mounted) return;
      debugPrint('[checkout_page] Error placing order: $e');
      AppNotifications.showErrorSnackBar(
        context,
        'Đặt hàng thất bại: $e. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.',
      );
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  void _showOutOfStockDialog(List<String> productNames) {
    AppNotifications.showInfoDialog(
      context,
      title: 'Sản phẩm hết hàng',
      content: 'Các sản phẩm sau không đủ tồn kho để đặt hàng:\n'
          '${productNames.map((name) => '• $name').join('\n')}\n\n'
          'Vui lòng bỏ chọn hoặc giảm số lượng các sản phẩm trên rồi thử lại.',
      closeText: 'Đã hiểu',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    final selectedItems = context.watch<CartCubit>().state.selectedItems;
    final totalAmount = context.watch<CartCubit>().state.selectedTotal;

    if (selectedItems.isEmpty && !_isPlacingOrder) {
      return BaseScreen(
        title: 'Thanh toán',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        body: const Center(child: Text('Không có sản phẩm nào được chọn')),
      );
    }

    return BaseScreen(
      title: 'Thanh toán',
      isLoading: _isPlacingOrder,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Địa chỉ giao hàng
                _buildSectionHeader('Địa chỉ giao hàng', Icons.location_on_outlined),
                const SizedBox(height: 8),
                TextField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Nhập địa chỉ của bạn',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Danh sách sản phẩm
                _buildSectionHeader('Sản phẩm (${selectedItems.length})', Icons.shopping_bag_outlined),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: selectedItems.map((item) {
                      String variantLabel = '';
                      if (item.selectedColor != null && item.selectedSize != null) {
                        variantLabel = '${item.selectedColor}, ${item.selectedSize}';
                      } else if (item.selectedColor != null) {
                        variantLabel = item.selectedColor!;
                      } else if (item.selectedSize != null) {
                        variantLabel = item.selectedSize!;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: item.product.imageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(item.product.imageUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                color: Colors.grey[200],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  if (variantLabel.isNotEmpty)
                                    Text(
                                      variantLabel,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  Text(
                                    '${currencyFormat.format(item.product.price)} x ${item.quantity}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              currencyFormat.format(item.lineTotal),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Phương thức thanh toán
                _buildSectionHeader('Phương thức thanh toán', Icons.payment_outlined),
                const SizedBox(height: 8),
                _buildPaymentOption('Thanh toán khi nhận hàng (COD)', 'COD', Icons.local_shipping_outlined),
                _buildPaymentOption('Chuyển khoản ngân hàng', 'BANK_TRANSFER', Icons.account_balance_outlined),
                _buildPaymentOption('Ví điện tử Momo/ZaloPay', 'E_WALLET', Icons.qr_code_scanner),
                const SizedBox(height: 40),
              ],
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Tổng thanh toán'),
                      Text(
                        currencyFormat.format(totalAmount),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFFB9852E),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  FilledButton(
                    onPressed: _placeOrder,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC6A15B),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: const Text('Đặt hàng'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFC6A15B)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildPaymentOption(String title, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _paymentMethod == value;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFFC6A15B) : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _paymentMethod,
        onChanged: (val) {
          if (val != null) setState(() => _paymentMethod = val);
        },
        title: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFFC6A15B) : Colors.grey),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 14)),
          ],
        ),
        activeColor: const Color(0xFFC6A15B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
