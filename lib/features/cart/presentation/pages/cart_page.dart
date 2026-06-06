import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/base_screen.dart';
import '../cubit/cart_cubit.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BaseScreen(
      title: 'Giỏ hàng',
      actions: [
        BlocBuilder<CartCubit, CartState>(
          builder: (context, state) {
            if (state.items.isEmpty) return const SizedBox();
            return TextButton(
              onPressed: () => context.read<CartCubit>().clear(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB23A48),
              ),
              child: const Text('Xoá tất cả'),
            );
          },
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<CartCubit, CartState>(
              builder: (context, state) {
                if (state.items.isEmpty) {
                  return _buildEmptyCart(context);
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: state.itemList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final item = state.itemList[index];
                    final isSelected = state.selectedItemKeys.contains(item.id);
                    return _buildCartItem(context, item, isSelected, isDark);
                  },
                );
              },
            ),
          ),
          _buildBottomCheckoutBar(context, isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 80,
            color: const Color(0xFFC6A15B).withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Giỏ hàng của bạn đang trống',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC6A15B),
              minimumSize: const Size(200, 48),
            ),
            child: const Text('Mua sắm ngay'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(
      BuildContext context, CartItem item, bool isSelected, bool isDark) {
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );
    final theme = Theme.of(context);

    // Xử lý chuỗi hiển thị phân loại
    String variantLabel = '';
    if (item.selectedColor != null && item.selectedSize != null) {
      variantLabel = '${item.selectedColor}, ${item.selectedSize}';
    } else if (item.selectedColor != null) {
      variantLabel = item.selectedColor!;
    } else if (item.selectedSize != null) {
      variantLabel = item.selectedSize!;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFFC6A15B) : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Checkbox
          Checkbox(
            value: isSelected,
            activeColor: const Color(0xFFC6A15B),
            onChanged: (_) {
              context.read<CartCubit>().toggleSelection(item.id);
            },
          ),
          // Hình ảnh sản phẩm
          Container(
            width: 80,
            height: 80,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
            ),
            clipBehavior: Clip.hardEdge,
            child: item.product.imageUrl.isNotEmpty
                ? Image.network(
                    item.product.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, color: Colors.grey),
                  )
                : const Icon(Icons.inventory_2_outlined, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          // Thông tin sản phẩm
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12).copyWith(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Nút xoá
                      GestureDetector(
                        onTap: () => context.read<CartCubit>().remove(item.id),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  if (variantLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        variantLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currencyFormat.format(item.product.price),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFB9852E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Quantity control
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => context.read<CartCubit>().decrement(item.id),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.remove, size: 16),
                              ),
                            ),
                            Container(
                              width: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                '${item.quantity}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            InkWell(
                              onTap: () => context.read<CartCubit>().increment(item.id),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.add, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCheckoutBar(BuildContext context, bool isDark) {
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return BlocBuilder<CartCubit, CartState>(
      builder: (context, state) {
        if (state.items.isEmpty) return const SizedBox();

        final isAllSelected = state.selectedItemKeys.length == state.items.length;
        final selectedCount = state.selectedItemKeys.length;
        final totalAmount = state.selectedTotal;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              children: [
                Checkbox(
                  value: isAllSelected,
                  activeColor: const Color(0xFFC6A15B),
                  onChanged: (_) {
                    context.read<CartCubit>().toggleAll();
                  },
                ),
                const Text('Tất cả'),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: selectedCount == 0
                      ? null
                      : () {
                          context.push('/checkout');
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC6A15B),
                    disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('Mua hàng ($selectedCount)'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
