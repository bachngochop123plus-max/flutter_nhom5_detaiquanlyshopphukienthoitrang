import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/product.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../cart/presentation/cubit/cart_cubit.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  String? _selectedColor;
  String? _selectedSize;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.product.availableColors.isEmpty
        ? null
        : widget.product.availableColors.first;
    _selectedSize = widget.product.availableSizes.isEmpty
        ? null
        : widget.product.availableSizes.first;
  }

  @override
  Widget build(BuildContext context) {
    final isAdminViewingAsUser = context.select<AuthCubit, bool>(
      (cubit) => cubit.state.isAdmin,
    );
    final images = widget.product.gallery.isNotEmpty
        ? widget.product.gallery
        : (widget.product.imageUrl.isNotEmpty
              ? [widget.product.imageUrl]
              : const <String>[]);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 360,
            actions: [
              IconButton(
                icon: const Icon(Icons.favorite_outline),
                onPressed: () async {
                  final productId = int.tryParse(widget.product.id);
                  if (productId == null) return;
                  await DatabaseHelper.instance.toggleFavorite(1, productId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã cập nhật yêu thích')),
                    );
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: images.length,
                    onPageChanged: (index) =>
                        setState(() => _imageIndex = index),
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '${_imageIndex + 1} / ${images.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.category,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.product.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.product.price.toStringAsFixed(0)} đ',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.product.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _SelectorSection(
                    title: 'Màu sắc',
                    values: widget.product.availableColors,
                    selectedValue: _selectedColor,
                    onSelected: (value) =>
                        setState(() => _selectedColor = value),
                  ),
                  const SizedBox(height: 20),
                  _SelectorSection(
                    title: 'Kích thước',
                    values: widget.product.availableSizes,
                    selectedValue: _selectedSize,
                    onSelected: (value) =>
                        setState(() => _selectedSize = value),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _showSelectionSheet(context),
                          child: const Text('Chọn nhanh'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: isAdminViewingAsUser
                              ? null
                              : () {
                                  context.read<CartCubit>().addProduct(
                                    widget.product,
                                    color: _selectedColor,
                                    size: _selectedSize,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã thêm vào giỏ hàng'),
                                    ),
                                  );
                                },
                          child: Text(
                            isAdminViewingAsUser
                                ? 'Mua hàng (Admin đang xem)'
                                : 'Thêm vào giỏ',
                          ),
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

  void _showSelectionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chọn biến thể',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _SelectionRow(
                  label: 'Màu',
                  values: widget.product.availableColors,
                  selectedValue: _selectedColor,
                  onChanged: (value) => setState(() => _selectedColor = value),
                ),
                const SizedBox(height: 12),
                _SelectionRow(
                  label: 'Size',
                  values: widget.product.availableSizes,
                  selectedValue: _selectedSize,
                  onChanged: (value) => setState(() => _selectedSize = value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectorSection extends StatelessWidget {
  const _SelectorSection({
    required this.title,
    required this.values,
    required this.selectedValue,
    required this.onSelected,
  });

  final String title;
  final List<String> values;
  final String? selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: selectedValue == value,
                  onSelected: (_) => onSelected(value),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.label,
    required this.values,
    required this.selectedValue,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final String? selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: values
                .map(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: selectedValue == value,
                    onSelected: (_) => onChanged(value),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}
