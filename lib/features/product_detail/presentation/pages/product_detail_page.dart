import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.product.availableColors.isEmpty
        ? null
        : widget.product.availableColors.first;
    _selectedSize = widget.product.availableSizes.isEmpty
        ? null
        : widget.product.availableSizes.first;

    // Giả lập load data 800ms để hiển thị Shimmer và Staggered Animation
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Widget _buildShimmerLoading(BuildContext context) {
    final shimmerColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[300]!;
    final highlightColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[700]!
        : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: shimmerColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 200,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 250,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: 80,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (index) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 60,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )),
          ),
        ],
      ),
    );
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
                      final imageWidget = CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      );
                      if (index == 0) {
                        return Hero(
                          tag: 'product-image-${widget.product.id}',
                          child: imageWidget,
                        );
                      }
                      return imageWidget;
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading
                    ? _buildShimmerLoading(context)
                    : Column(
                        key: const ValueKey('product_details_loaded'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SlideUpFadeTransition(
                            delay: Duration.zero,
                            child: Text(
                              widget.product.category,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 80),
                            child: Text(
                              widget.product.name,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 160),
                            child: Text(
                              '${widget.product.price.toStringAsFixed(0)} đ',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 240),
                            child: Text(
                              widget.product.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 320),
                            child: _SelectorSection(
                              title: 'Màu sắc',
                              values: widget.product.availableColors,
                              selectedValue: _selectedColor,
                              onSelected: (value) =>
                                  setState(() => _selectedColor = value),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 400),
                            child: _SelectorSection(
                              title: 'Kích thước',
                              values: widget.product.availableSizes,
                              selectedValue: _selectedSize,
                              onSelected: (value) =>
                                  setState(() => _selectedSize = value),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 480),
                            child: Row(
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
                          ),
                        ],
                      ),
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

class SlideUpFadeTransition extends StatefulWidget {
  const SlideUpFadeTransition({
    super.key,
    required this.child,
    required this.delay,
  });

  final Widget child;
  final Duration delay;

  @override
  State<SlideUpFadeTransition> createState() => _SlideUpFadeTransitionState();
}

class _SlideUpFadeTransitionState extends State<SlideUpFadeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
