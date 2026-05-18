import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/base_screen.dart';
import '../cubit/cart_cubit.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Giỏ hàng',

      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state.items.isEmpty) {
            return const _EmptyCart();
          }

          return Column(
            children: [
              /// LIST ITEM
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.itemList.length,

                  separatorBuilder: (_, __) => const SizedBox(height: 14),

                  itemBuilder: (context, index) {
                    final item = state.itemList[index];

                    return Container(
                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),

                      child: Row(
                        children: [
                          /// IMAGE
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),

                            child: CachedNetworkImage(
                              imageUrl: item.product.imageUrl,
                              width: 95,
                              height: 95,
                              fit: BoxFit.cover,

                              placeholder: (context, url) => Container(
                                width: 95,
                                height: 95,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),

                              errorWidget: (_, __, ___) => Container(
                                width: 95,
                                height: 95,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.image),
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          /// INFO
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  item.product.name,

                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  '${item.product.price.toStringAsFixed(0)} đ',

                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,

                                  children: [
                                    /// COLOR
                                    if (item.product.availableColors.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _showVariantPicker(
                                            context,
                                            item,
                                            isColorPicker: true,
                                          );
                                        },

                                        child: _InfoChip(
                                          text:
                                              'Màu: ${item.selectedColor ?? "Chọn"}',
                                        ),
                                      ),

                                    /// SIZE
                                    if (item.product.availableSizes.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _showVariantPicker(
                                            context,
                                            item,
                                            isColorPicker: false,
                                          );
                                        },

                                        child: _InfoChip(
                                          text:
                                              'Size: ${item.selectedSize ?? "Chọn"}',
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                Row(
                                  children: [
                                    _QuantityButton(
                                      icon: Icons.remove,
                                      onTap: () {
                                        context.read<CartCubit>().decrement(
                                          item.product.id,
                                        );
                                      },
                                    ),

                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),

                                      child: Text(
                                        '${item.quantity}',

                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),

                                    _QuantityButton(
                                      icon: Icons.add,
                                      onTap: () {
                                        context.read<CartCubit>().increment(
                                          item.product.id,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          /// DELETE
                          IconButton(
                            onPressed: () {
                              context.read<CartCubit>().remove(item.product.id);
                            },

                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              /// BOTTOM PAYMENT
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),

                decoration: const BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),

                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Tổng thanh toán',

                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),

                        const Spacer(),

                        Text(
                          '${state.total.toStringAsFixed(0)} đ',

                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 56,

                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF111111),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),

                        onPressed: () {
                          showDialog(
                            context: context,

                            builder: (_) => AlertDialog(
                              title: const Text('Thanh toán'),

                              content: const Text('Đặt hàng thành công!'),

                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);

                                    context.read<CartCubit>().clear();
                                  },

                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },

                        child: const Text(
                          'Thanh toán',

                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextButton.icon(
                      onPressed: () {
                        context.read<CartCubit>().clear();
                      },

                      icon: const Icon(Icons.delete_sweep_outlined),

                      label: const Text('Xoá toàn bộ'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showVariantPicker(
    BuildContext context,
    CartItem item, {
    required bool isColorPicker,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,

      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(20),

          decoration: const BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),

          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                /// TOP INFO
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    /// IMAGE
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),

                      child: CachedNetworkImage(
                        imageUrl: item.product.imageUrl,

                        width: 95,
                        height: 95,
                        fit: BoxFit.cover,

                        errorWidget: (_, __, ___) => Container(
                          width: 95,
                          height: 95,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    /// INFO
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            item.product.name,

                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            '${item.product.price.toStringAsFixed(0)} đ',

                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.redAccent,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'Đã chọn: '
                            '${item.selectedColor ?? ""}'
                            ' ${item.selectedSize ?? ""}',

                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                /// TITLE
                Text(
                  isColorPicker ? 'Màu sắc' : 'Kích thước',

                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                /// OPTIONS
                Wrap(
                  spacing: 10,
                  runSpacing: 12,

                  children:
                      (isColorPicker
                              ? item.product.availableColors
                              : item.product.availableSizes)
                          .map(
                            (value) => ChoiceChip(
                              label: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),

                                child: Text(value),
                              ),

                              selected: isColorPicker
                                  ? item.selectedColor == value
                                  : item.selectedSize == value,

                              onSelected: (_) {
                                context.read<CartCubit>().updateVariant(
                                  item.product.id,

                                  color: isColorPicker
                                      ? value
                                      : item.selectedColor,

                                  size: isColorPicker
                                      ? item.selectedSize
                                      : value,
                                );

                                Navigator.pop(context);
                              },
                            ),
                          )
                          .toList(),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(30),
      ),

      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(100),

      onTap: onTap,

      child: Container(
        width: 32,
        height: 32,

        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),

          shape: BoxShape.circle,
        ),

        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 90,
            color: Colors.grey.shade400,
          ),

          const SizedBox(height: 18),

          const Text(
            'Giỏ hàng trống',

            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            'Hãy thêm sản phẩm vào giỏ hàng',

            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
