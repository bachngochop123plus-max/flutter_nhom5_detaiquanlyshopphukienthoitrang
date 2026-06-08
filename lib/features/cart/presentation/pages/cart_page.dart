import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/auth_guard.dart';
import '../../../../core/widgets/base_screen.dart';
import '../cubit/cart_cubit.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _variantLabel(CartItem item) {
    if (item.selectedColor != null && item.selectedSize != null) {
      return '${item.selectedColor}, ${item.selectedSize}';
    } else if (item.selectedColor != null) {
      return item.selectedColor!;
    } else if (item.selectedSize != null) {
      return item.selectedSize!;
    }
    return '';
  }

  // ── Confirmation dialog: xóa tất cả ─────────────────────────────────────

  Future<void> _confirmClearAll(BuildContext context) async {
    final cubit = context.read<CartCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFB23A48).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.delete_sweep_outlined,
            color: Color(0xFFB23A48),
            size: 30,
          ),
        ),
        title: const Text(
          'Xoá tất cả sản phẩm?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const Text(
          'Tất cả sản phẩm trong giỏ hàng sẽ bị xoá.\nBạn có chắc chắn muốn tiếp tục không?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Huỷ'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB23A48),
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      cubit.clear();
    }
  }

  // ── Bottom sheet chỉnh variant (giống Shopee) ─────────────────────────────

  void _showVariantSheet(BuildContext context, CartItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) =>
          _VariantEditorSheet(item: item, cartCubit: context.read<CartCubit>()),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
              onPressed: () => _confirmClearAll(context),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: state.itemList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
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

  // ── Empty state ───────────────────────────────────────────────────────────

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
            onPressed: () => context.go('/home'),
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

  // ── Cart item card ────────────────────────────────────────────────────────

  Widget _buildCartItem(
    BuildContext context,
    CartItem item,
    bool isSelected,
    bool isDark,
  ) {
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );
    final theme = Theme.of(context);
    final label = _variantLabel(item);
    final hasVariants =
        item.product.availableColors.isNotEmpty ||
        item.product.availableSizes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFC6A15B)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
      child: Column(
        children: [
          Row(
            children: [
              // ── Checkbox ───────────────────────────────────────────
              Checkbox(
                value: isSelected,
                activeColor: const Color(0xFFC6A15B),
                onChanged: (_) =>
                    context.read<CartCubit>().toggleSelection(item.id),
              ),

              // ── Thumbnail ──────────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF5F5F5),
                ),
                clipBehavior: Clip.hardEdge,
                child: item.product.imageUrl.isNotEmpty
                    ? Image.network(
                        item.product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                        ),
                      )
                    : const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey,
                      ),
              ),

              const SizedBox(width: 12),

              // ── Product info ───────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ).copyWith(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + close button
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
                          GestureDetector(
                            onTap: () =>
                                context.read<CartCubit>().remove(item.id),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // ── Variant chip (bấm để chỉnh) ────────────────
                      if (hasVariants) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showVariantSheet(context, item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    label.isNotEmpty ? label : 'Chọn phân loại',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (label.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Price + quantity stepper
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
                          _QuantityStepper(item: item),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom checkout bar ───────────────────────────────────────────────────

  Widget _buildBottomCheckoutBar(BuildContext context, bool isDark) {
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return BlocBuilder<CartCubit, CartState>(
      builder: (context, state) {
        if (state.items.isEmpty) return const SizedBox();

        final isAllSelected =
            state.selectedItemKeys.length == state.items.length;
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
                  onChanged: (_) => context.read<CartCubit>().toggleAll(),
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
                          if (!AuthGuard.requireLogin(context)) {
                            return;
                          }
                          context.push('/checkout');
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC6A15B),
                    disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
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

// ════════════════════════════════════════════════════════════════════════════
// Quantity stepper widget — có validate stock, có thể nhập tay
// ════════════════════════════════════════════════════════════════════════════

class _QuantityStepper extends StatefulWidget {
  const _QuantityStepper({required this.item});
  final CartItem item;

  @override
  State<_QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<_QuantityStepper> {
  void _openInputDialog() {
    final cubit = context.read<CartCubit>();
    final maxStock = cubit.stockOf(widget.item);
    final controller = TextEditingController(text: '${widget.item.quantity}');

    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập số lượng'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Tối đa $maxStock',
            helperText: 'Tồn kho: $maxStock sản phẩm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? widget.item.quantity;
              Navigator.pop(ctx, val);
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ).then((val) {
      if (val != null && mounted) {
        final maxStock = cubit.stockOf(widget.item);
        if (val > maxStock) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chỉ còn $maxStock sản phẩm trong kho'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          cubit.setQuantity(widget.item.id, maxStock);
        } else {
          cubit.setQuantity(widget.item.id, val);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CartCubit>();
    final maxStock = cubit.stockOf(widget.item);
    final qty = widget.item.quantity;
    final theme = Theme.of(context);
    final atMax = qty >= maxStock;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nút giảm
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
            ),
            onTap: () => cubit.decrement(widget.item.id),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.remove, size: 16),
            ),
          ),
          Container(width: 1, color: theme.colorScheme.outlineVariant),
          // Số lượng — tap để nhập tay
          InkWell(
            onTap: _openInputDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$qty',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: atMax ? Colors.orange[700] : null,
                ),
              ),
            ),
          ),
          Container(width: 1, color: theme.colorScheme.outlineVariant),
          // Nút tăng — disabled khi đạt tối đa
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(8),
            ),
            onTap: atMax
                ? () {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Chỉ còn $maxStock sản phẩm trong kho'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                : () => cubit.increment(widget.item.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.add,
                size: 16,
                color: atMax
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Bottom sheet chỉnh variant — giống Shopee/Lazada
// ════════════════════════════════════════════════════════════════════════════

class _VariantEditorSheet extends StatefulWidget {
  const _VariantEditorSheet({required this.item, required this.cartCubit});

  final CartItem item;
  final CartCubit cartCubit;

  @override
  State<_VariantEditorSheet> createState() => _VariantEditorSheetState();
}

class _VariantEditorSheetState extends State<_VariantEditorSheet> {
  late String? _color;
  late String? _size;
  late int _quantity;

  /// Lấy stock của variant đang chọn trong sheet
  int get _currentStock {
    final variants = widget.item.product.variants;
    if (variants.isEmpty) return 999;
    final v = variants.firstWhere(
      (v) => v['color'] == _color && v['size'] == _size,
      orElse: () => {},
    );
    final s = (v['stock'] as num?)?.toInt();
    if (s != null) return s;
    // fallback: tìm theo chỉ màu hoặc chỉ size
    final fallback = variants.firstWhere(
      (v) => v['color'] == _color || v['size'] == _size,
      orElse: () => {},
    );
    return (fallback['stock'] as num?)?.toInt() ?? 999;
  }

  @override
  void initState() {
    super.initState();
    _color = widget.item.selectedColor;
    _size = widget.item.selectedSize;
    _quantity = widget.item.quantity;
  }

  void _confirm() {
    final cubit = widget.cartCubit;
    final oldId = widget.item.id;

    // Cap lại quantity theo stock hiện tại
    final maxStock = _currentStock;
    final clampedQty = _quantity.clamp(1, maxStock);

    // Cập nhật variant (màu / size)
    cubit.updateVariant(oldId, newColor: _color, newSize: _size);

    // Sau khi đổi variant, key của item có thể đã thay đổi —
    // tính lại key mới để cập nhật quantity đúng chỗ.
    final userId =
        cubit.state.items.keys
            .where((k) => k.startsWith(widget.item.product.id))
            .firstOrNull
            ?.split('_')
            .last ??
        'guest';
    final newKey =
        '${widget.item.product.id}_${_color ?? "none"}_${_size ?? "none"}_$userId';
    final newItem = cubit.state.items[newKey];
    if (newItem != null && newItem.quantity != clampedQty) {
      cubit.setQuantity(newKey, clampedQty);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.item.product;
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: ảnh + tên + giá ──────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: product.imageUrl.isNotEmpty
                      ? Image.network(
                          product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                            ),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.inventory_2_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(product.price),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFB9852E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Variant đang chọn
                    Text(
                      [
                        if (_color != null) _color!,
                        if (_size != null) _size!,
                      ].join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── Màu sắc ──────────────────────────────────────────────
          if (product.availableColors.isNotEmpty) ...[
            _sectionLabel(context, 'Màu sắc'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: product.availableColors.map((color) {
                final selected = _color == color;
                return GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFC6A15B)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFC6A15B)
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      color,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Kích thước ───────────────────────────────────────────
          if (product.availableSizes.isNotEmpty) ...[
            _sectionLabel(context, 'Kích thước'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: product.availableSizes.map((size) {
                final selected = _size == size;
                return GestureDetector(
                  onTap: () => setState(() => _size = size),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFC6A15B)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFC6A15B)
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      size,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Số lượng ───────────────────────────────────────────
          _sectionLabel(context, 'Số lượng'),
          const SizedBox(height: 4),
          // Hiển thị tồn kho
          Builder(
            builder: (ctx) {
              final stock = _currentStock;
              return Text(
                'Tồn kho: $stock sản phẩm',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stock <= 5
                      ? Colors.orange[700]
                      : theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _QtyButton(
                icon: Icons.remove,
                onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$_quantity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _quantity >= _currentStock
                        ? Colors.orange[700]
                        : null,
                  ),
                ),
              ),
              _QtyButton(
                icon: Icons.add,
                onTap: _quantity < _currentStock
                    ? () => setState(() => _quantity++)
                    : null,
              ),
              const SizedBox(width: 8),
              if (_quantity >= _currentStock)
                Text(
                  'Tối đa',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Nút xác nhận ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC6A15B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Xác nhận',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

// ── Nút +/- số lượng trong sheet ─────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
          border: Border.all(
            color: enabled
                ? theme.colorScheme.outlineVariant
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
