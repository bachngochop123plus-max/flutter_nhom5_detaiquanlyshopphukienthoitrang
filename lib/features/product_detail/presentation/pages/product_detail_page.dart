import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/product.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../cart/presentation/cubit/cart_cubit.dart';
import '../../../../core/utils/auth_guard.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.product,
    this.animateOnMount = true, // false khi navigate từ sản phẩm liên quan
  });

  final Product product;
  final bool animateOnMount;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  String? _selectedColor;
  String? _selectedSize;
  int _imageIndex = 0;
  bool _isLoading = true;
  bool _isFavorite = false;

  final PageController _pageController = PageController();
  final ScrollController _thumbnailScrollController = ScrollController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final FocusNode _quantityFocusNode = FocusNode();
  Timer? _slideshowTimer;

  // Số lượng sản phẩm muốn mua — luôn trong khoảng [1, _variantStock]
  int _quantity = 1;

  // Custom view database fields
  Map<String, dynamic>? _viewDetail;
  List<dynamic> _variants = [];
  List<String> _galleryImages = [];
  List<Product> _relatedProducts = [];
  double _currentPrice = 0.0;
  int _variantStock = 0;
  double _variantPriceDelta = 0.0;

  @override
  void initState() {
    super.initState();
    _currentPrice = widget.product.price;
    _galleryImages = widget.product.gallery
        .map((url) => _resolveImageUrl(url))
        .where(_isValidImageUrl)
        .toSet()
        .toList();

    if (_galleryImages.isEmpty && widget.product.imageUrl.trim().isNotEmpty) {
      final img = _resolveImageUrl(widget.product.imageUrl);
      if (_isValidImageUrl(img)) {
        _galleryImages = [img];
      }
    }

    _quantityFocusNode.addListener(() {
      if (!_quantityFocusNode.hasFocus) {
        _validateAndNormalizeQuantity();
      }
    });

    _checkFavoriteStatus();
    _loadProductDetails().then((_) {
      // Giả lập load data để hiển thị Shimmer và Staggered Animation
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant ProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldGalleryStr = oldWidget.product.gallery.join(',');
    final newGalleryStr = widget.product.gallery.join(',');
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.product.imageUrl != widget.product.imageUrl ||
        oldGalleryStr != newGalleryStr) {
      _stopSlideshow();
      setState(() {
        _isLoading = true;
        _selectedColor = null;
        _selectedSize = null;
        _imageIndex = 0;
        _currentPrice = widget.product.price;
        _galleryImages = widget.product.gallery
            .map((url) => _resolveImageUrl(url))
            .where(_isValidImageUrl)
            .toSet()
            .toList();

        if (_galleryImages.isEmpty &&
            widget.product.imageUrl.trim().isNotEmpty) {
          final img = _resolveImageUrl(widget.product.imageUrl);
          if (_isValidImageUrl(img)) {
            _galleryImages = [img];
          }
        }
      });
      _checkFavoriteStatus();
      _loadProductDetails().then((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _stopSlideshow();
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    _quantityController.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_galleryImages.length <= 1) return;
      final nextIndex = (_imageIndex + 1) % _galleryImages.length;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
  }

  /// Auto-scroll thanh thumbnail trái đến ô đang active khi slideshow chuyển ảnh.
  /// Mỗi ô cao 34 + margin 8 (4*2) = 42px. padding top 8px.
  void _scrollThumbnailToIndex(int index) {
    if (!_thumbnailScrollController.hasClients) return;
    const double itemHeight = 42.0; // 34 height + 8 margin
    const double paddingTop = 8.0;
    final double targetOffset = paddingTop + index * itemHeight;
    final double maxScroll =
        _thumbnailScrollController.position.maxScrollExtent;
    _thumbnailScrollController.animateTo(
      targetOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _checkFavoriteStatus() async {
    final productId = int.tryParse(widget.product.id);
    if (productId == null) return;
    try {
      final isFav = await DatabaseHelper.instance.isFavorite(1, productId);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
        });
      }
    } catch (e) {
      debugPrint('[ProductDetailPage] check favorite failed: $e');
    }
  }

  Future<void> _loadProductDetails() async {
    final productId = int.tryParse(widget.product.id);
    if (productId == null) return;

    try {
      // 1. Tải chi tiết sản phẩm từ SQLite View v_product_detail
      final detail = await DatabaseHelper.instance.getProductDetailFromView(
        productId,
      );

      // 2. Tải danh sách sản phẩm liên quan cùng danh mục từ SQLite
      final related = await DatabaseHelper.instance.getRelatedProductsForDetail(
        productId,
        widget.product.category,
      );

      if (mounted) {
        setState(() {
          _viewDetail = detail;
          _relatedProducts = related;

          if (detail != null) {
            // Giải mã mảng JSON variants
            final String? variantsRaw = detail['variants'] as String?;
            if (variantsRaw != null && variantsRaw.isNotEmpty) {
              final parsed = jsonDecode(variantsRaw);
              if (parsed is List) {
                _variants = parsed;
              }
            }

            // Giải mã mảng JSON gallery
            final String? galleryRaw =
                (detail['gallery'] ?? detail['images']) as String?;
            List<Map<String, dynamic>> tempGallery = [];
            if (galleryRaw != null && galleryRaw.isNotEmpty) {
              final parsed = jsonDecode(galleryRaw);
              if (parsed is List) {
                tempGallery = parsed
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                // Sắp xếp theo thứ tự sort_order
                tempGallery.sort((a, b) {
                  final sa = a['sort_order'] as num? ?? 0;
                  final sb = b['sort_order'] as num? ?? 0;
                  return sa.compareTo(sb);
                });
              }
            }

            // Map thành danh sách đường dẫn ảnh phụ — lọc URL lỗi TRƯỚC khi đưa vào danh sách
            _galleryImages = tempGallery
                .map((e) => _resolveImageUrl(e['image_url'] as String? ?? ''))
                .where(_isValidImageUrl)
                .toSet()
                .toList();

            // Nếu không có ảnh phụ, dùng ảnh chính của sản phẩm
            if (_galleryImages.isEmpty) {
              final img = _resolveImageUrl(widget.product.imageUrl);
              if (_isValidImageUrl(img)) {
                _galleryImages = [img];
              }
            }

            // Đảm bảo chỉ số ảnh hiển thị không vượt quá số lượng ảnh hiện có
            if (_imageIndex >= _galleryImages.length) {
              _imageIndex = _galleryImages.isNotEmpty
                  ? _galleryImages.length - 1
                  : 0;
            }
          }

          // Lấy danh sách màu sắc và kích thước từ các biến thể để khởi tạo ChoiceChips
          final colors = _variants
              .map((v) => v['color'] as String?)
              .whereType<String>()
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList();

          final sizes = _variants
              .map((v) => v['size'] as String?)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();

          if (_selectedColor == null && colors.isNotEmpty) {
            _selectedColor = colors.first;
          }
          if (_selectedSize == null && sizes.isNotEmpty) {
            _selectedSize = sizes.first;
          }

          _updateSelectedVariant();
          _startSlideshow();
        });
      }
    } catch (e) {
      debugPrint('[ProductDetailPage] load detail failed: $e');
    }
  }

  void _updateSelectedVariant() {
    if (_variants.isEmpty) {
      _variantStock = 99; // Mặc định nếu không có biến thể cụ thể
      _variantPriceDelta = 0.0;
      _currentPrice = widget.product.price;
      setState(() {
        _quantity = 1;
        _quantityController.text = '1';
      });
      return;
    }

    // Tìm biến thể khớp với màu sắc và kích thước đang chọn
    final match = _variants.firstWhere(
      (v) =>
          (v['color'] == null || v['color'] == _selectedColor) &&
          (v['size'] == null || v['size'] == _selectedSize),
      orElse: () => _variants.first,
    );

    setState(() {
      _variantStock = match['stock'] as int? ?? 0;
      _variantPriceDelta = (match['price_delta'] as num? ?? 0.0).toDouble();
      _currentPrice = widget.product.price + _variantPriceDelta;
      // Reset số lượng về 1 nếu còn hàng, 0 nếu hết hàng
      _quantity = _variantStock > 0 ? 1 : 0;
      _quantityController.text = _quantity.toString();
    });
  }

  void _validateAndNormalizeQuantity() {
    final text = _quantityController.text.trim();
    final parsed = int.tryParse(text);
    final maxQty = _variantStock > 0
        ? _variantStock
        : (_variants.isEmpty ? 99 : 0);

    if (maxQty <= 0) {
      setState(() {
        _quantity = 0;
        _quantityController.text = '0';
      });
      return;
    }

    if (parsed == null) {
      setState(() {
        _quantity = 1;
        _quantityController.text = '1';
      });
    } else if (parsed < 1) {
      setState(() {
        _quantity = 1;
        _quantityController.text = '1';
      });
    } else if (parsed > maxQty) {
      setState(() {
        _quantity = maxQty;
        _quantityController.text = maxQty.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chỉ còn $maxQty sản phẩm trong kho!'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      setState(() {
        _quantity = parsed;
        _quantityController.text = parsed.toString();
      });
    }
  }

  void _handleAddToCart({required bool navigateToCart}) {
    if (!AuthGuard.requireLogin(context)) return;

    _validateAndNormalizeQuantity();

    if (_quantity <= 0) return;

    final qty = _quantity;

    // Tạo bản sao Product với mức giá mới đã cộng delta
    final updatedProduct = widget.product.copyWith(price: _currentPrice);

    // Thêm vào giỏ hàng với số lượng người dùng chọn
    for (var i = 0; i < qty; i++) {
      context.read<CartCubit>().addProduct(
        updatedProduct,
        color: _selectedColor,
        size: _selectedSize,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          navigateToCart
              ? 'Đã thêm $qty sản phẩm! Đang chuyển đến giỏ hàng...'
              : 'Đã thêm $qty sản phẩm vào giỏ hàng!',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );

    if (navigateToCart) {
      GoRouter.of(context).push('/cart');
    }
  }

  String _resolveImageUrl(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }
    if (clean.startsWith('assets/') || clean.startsWith('images/')) {
      return clean;
    }
    var normalized = clean;
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith('Img_Product/')) {
      normalized = 'Img_Product/$normalized';
    }
    return 'https://qkweoptutabbzulsrpas.supabase.co/storage/v1/object/public/Img_products/$normalized';
  }

  /// Xác minh URL ảnh hợp lệ TRƯỚC khi thêm vào _galleryImages.
  /// Kiểm tra đuôi file trên TÊN FILE (segment cuối của path), không phải toàn URL.
  /// → Loại ngay các giá trị rác như "Img01.webp_1" (thumbnail || '_1') khỏi database.
  bool _isValidImageUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return false;
    if (clean == 'null' || clean == 'undefined') return false;
    if (clean.endsWith('/null') || clean.endsWith('/undefined')) return false;
    if (clean.toLowerCase().contains('placeholder')) return false;

    // Lấy tên file (segment cuối trước query params)
    // VD: ".../Img_products/Img_Product/Img01.webp_1?t=..." → "Img01.webp_1"
    final pathPart = clean.split('?').first; // bỏ query string
    final fileName = pathPart.split('/').last.toLowerCase(); // lấy tên file

    const validExts = [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
      '.avif',
      '.heic',
    ];
    final hasValidExt = validExts.any((ext) => fileName.endsWith(ext));

    // Bắt buộc phải có đuôi file hợp lệ — dù là Supabase URL hay local asset
    // Điều này loại "Img01.webp_1" (fileName = "img01.webp_1") không kết thúc bằng ".webp"
    return hasValidExt;
  }

  Widget _buildSafeImage(
    String imageUrl, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    double placeholderIconSize = 24.0,
  }) {
    final cleanUrl = _resolveImageUrl(imageUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (cleanUrl.isEmpty) {
      return Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        width: width,
        height: height,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: placeholderIconSize,
            color: Colors.grey,
          ),
        ),
      );
    }

    if (cleanUrl.startsWith('assets/') || cleanUrl.startsWith('images/')) {
      return Image.asset(
        cleanUrl,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            width: width,
            height: height,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: placeholderIconSize,
                color: Colors.grey,
              ),
            ),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: cleanUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) => Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.luxuryGold,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        width: width,
        height: height,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: placeholderIconSize,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: shimmerColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 140,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdminViewingAsUser = context.select<AuthCubit, bool>(
      (cubit) => cubit.state.isAdmin,
    );

    // Dữ liệu hiển thị từ View
    final String categoryName =
        _viewDetail?['category_name'] as String? ?? widget.product.category;
    final double ratingAvg =
        (_viewDetail?['rating_avg'] as num? ?? widget.product.rating)
            .toDouble();
    final int ratingCount = _viewDetail?['rating_count'] as int? ?? 0;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // AppBar với Slider ảnh chất lượng cao và thanh nhỏ chọn ảnh bên trái
          SliverAppBar(
            pinned: true,
            expandedHeight: 420,
            backgroundColor: isDark ? AppColors.deepBlack : AppColors.whiteSilk,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.7),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDark ? Colors.white : AppColors.deepBlack,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: 0.7),
                  child: IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite
                          ? AppColors.danger
                          : (isDark ? Colors.white : AppColors.deepBlack),
                    ),
                    onPressed: () async {
                      if (!AuthGuard.requireLogin(context)) return;
                      final productId = int.tryParse(widget.product.id);
                      if (productId == null) return;

                      await DatabaseHelper.instance.toggleFavorite(
                        1,
                        productId,
                      );
                      await _checkFavoriteStatus();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isFavorite
                                  ? 'Đã thêm vào yêu thích'
                                  : 'Đã xóa khỏi yêu thích',
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.luxuryGold,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // PageView hình ảnh
                  PageView.builder(
                    controller: _pageController,
                    itemCount: _galleryImages.length,
                    onPageChanged: (index) {
                      setState(() => _imageIndex = index);
                      _startSlideshow(); // Reset timer khi lật tay
                      // Auto-scroll thanh thumbnail trái đến ô đang active
                      _scrollThumbnailToIndex(index);
                    },
                    itemBuilder: (context, index) {
                      final imageWidget = _buildSafeImage(
                        _galleryImages[index],
                        fit: BoxFit.cover,
                        placeholderIconSize: 50,
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

                  // Gradient che mờ chân ảnh slider
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            (isDark ? AppColors.deepBlack : AppColors.whiteSilk)
                                .withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // THANH THUMBNAIL NHỎ BÊN TRÁI ẢNH — tự động sinh đúng số ô theo số lượng ảnh
                  if (_galleryImages.length > 1)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          // Giới hạn chiều cao tối đa để scroll khi nhiều ảnh
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.45,
                          ),
                          child: Container(
                            width: 48,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            // intrinsicHeight = co lại theo số ô thực tế
                            child: IntrinsicHeight(
                              child: SingleChildScrollView(
                                controller: _thumbnailScrollController,
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  // itemCount tự động theo số ảnh thực tế — không cứng 5 ô
                                  children: List.generate(_galleryImages.length, (
                                    index,
                                  ) {
                                    final isSelected = _imageIndex == index;
                                    return GestureDetector(
                                      onTap: () {
                                        _pageController.animateToPage(
                                          index,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.luxuryGold
                                                : Colors.white.withValues(
                                                    alpha: 0.4,
                                                  ),
                                            width: isSelected ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          // _galleryImages đã lọc URL lỗi từ trước
                                          // → _buildSafeImage chỉ xử lý ảnh hợp lệ
                                          child: _buildSafeImage(
                                            _galleryImages[index],
                                            fit: BoxFit.cover,
                                            placeholderIconSize: 16,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ════ VIỆN VÀNG + ĐEN PHÂN CÁCH ẢNH VÀ NỘI DUNG ════
          SliverToBoxAdapter(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black,
                    AppColors.luxuryGold,
                    const Color(0xFFD6B570),
                    AppColors.luxuryGold,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // NỘI DUNG CHI TIẾT
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.deepBlack : AppColors.whiteSilk,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.black : const Color(0xFF1A1410),
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Stack(
                children: [
                  // Nội dung thực — luôn tồn tại trong widget tree để SlideUpFadeTransition
                  // KHÔNG bị dispose/recreate. Offstage ẩn hoàn toàn (không mờ) khi load.
                  Offstage(
                    offstage: _isLoading,
                    child: IgnorePointer(
                      ignoring: _isLoading,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hàng Danh mục & Đánh giá
                          SlideUpFadeTransition(
                            delay: Duration.zero,
                            animate: widget.animateOnMount,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.luxuryGold.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    categoryName.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.luxuryGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: AppColors.luxuryGold,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ratingAvg.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '($ratingCount đánh giá)',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ── TÊN SẢN PHẨM ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 80),
                            animate: widget.animateOnMount,
                            child: Text(
                              widget.product.name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.deepBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── GIÁ + BADGE GIẢM GIÁ ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 130),
                            animate: widget.animateOnMount,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _formatPrice(_currentPrice),
                                  style: const TextStyle(
                                    color: AppColors.luxuryGold,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (widget.product.isDiscounted) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatPrice(_currentPrice * 1.25),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      '−20%',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── DIVIDER VÀNG-ĐEN ──
                          Container(
                            height: 2,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black,
                                  AppColors.luxuryGold,
                                  Color(0xFFD6B570),
                                  AppColors.luxuryGold,
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── HÀNG MÃ SP + TỒN KHO ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 160),
                            animate: widget.animateOnMount,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.luxuryGold.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Mã SP
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.tag_rounded,
                                          size: 15,
                                          color: AppColors.luxuryGold,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Mã SP',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                              Text(
                                                '#SP-${widget.product.id.padLeft(4, '0')}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark
                                                      ? Colors.white
                                                      : AppColors.deepBlack,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Divider dọc
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: AppColors.luxuryGold.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Tồn kho
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 15,
                                          color: _variantStock > 0
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Tồn kho',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                              Text(
                                                _variants.isEmpty
                                                    ? 'Không giới hạn'
                                                    : _variantStock > 0
                                                    ? '$_variantStock sản phẩm'
                                                    : 'Hết hàng',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _variantStock > 0
                                                      ? AppColors.success
                                                      : AppColors.danger,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Divider dọc
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: AppColors.luxuryGold.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Xếp hạng
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 15,
                                          color: AppColors.luxuryGold,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Đánh giá',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                              Text(
                                                ratingCount > 0
                                                    ? '$ratingAvg ★'
                                                    : 'Mới',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.luxuryGold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── MÔ TẢ SẢN PHẨM ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 200),
                            animate: widget.animateOnMount,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1B1B1B)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: const Border(
                                  left: BorderSide(
                                    color: AppColors.luxuryGold,
                                    width: 3.5,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.2 : 0.04,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.article_outlined,
                                        color: AppColors.luxuryGold,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'Mô tả sản phẩm',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.deepBlack,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.product.description.isNotEmpty
                                        ? widget.product.description
                                        : 'Chưa có mô tả chi tiết cho sản phẩm này.',
                                    style: TextStyle(
                                      height: 1.6,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[700],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── BIẾN THỂ MÀU SẮC ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 280),
                            animate: widget.animateOnMount,
                            child: _buildVariantsColorSection(),
                          ),
                          const SizedBox(height: 14),

                          // ── BIẾN THỂ KÍCH THƯỚC ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 340),
                            animate: widget.animateOnMount,
                            child: _buildVariantsSizeSection(),
                          ),
                          const SizedBox(height: 20),

                          // ── CHỌN SỐ LƯỢNG ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 400),
                            animate: widget.animateOnMount,
                            child: _buildQuantitySelector(isDark),
                          ),
                          const SizedBox(height: 24),

                          // ── HAI NÚT HÀNH ĐỘNG ──
                          SlideUpFadeTransition(
                            delay: const Duration(milliseconds: 460),
                            animate: widget.animateOnMount,
                            child: Row(
                              children: [
                                // Nút Thêm vào giỏ
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.shopping_cart_outlined,
                                      size: 17,
                                      color: AppColors.luxuryGold,
                                    ),
                                    label: const Text(
                                      'THÊM VÀO GIỎ',
                                      style: TextStyle(
                                        color: AppColors.luxuryGold,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      side: const BorderSide(
                                        color: AppColors.luxuryGold,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed:
                                        _variantStock <= 0 ||
                                            isAdminViewingAsUser
                                        ? null
                                        : () => _handleAddToCart(
                                            navigateToCart: false,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Nút Mua ngay
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient:
                                          _variantStock > 0 &&
                                              !isAdminViewingAsUser
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF1A1A1A),
                                                Color(0xFF2D2D2D),
                                              ],
                                            )
                                          : null,
                                      color:
                                          _variantStock <= 0 ||
                                              isAdminViewingAsUser
                                          ? Colors.grey[700]
                                          : null,
                                      borderRadius: BorderRadius.circular(14),
                                      border:
                                          _variantStock > 0 &&
                                              !isAdminViewingAsUser
                                          ? Border.all(
                                              color: AppColors.luxuryGold,
                                              width: 1.5,
                                            )
                                          : null,
                                    ),
                                    child: ElevatedButton.icon(
                                      icon: const Icon(
                                        Icons.flash_on_rounded,
                                        size: 17,
                                        color: AppColors.luxuryGold,
                                      ),
                                      label: const Text(
                                        'MUA NGAY',
                                        style: TextStyle(
                                          color: AppColors.luxuryGold,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          _variantStock <= 0 ||
                                              isAdminViewingAsUser
                                          ? null
                                          : () => _handleAddToCart(
                                              navigateToCart: true,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ÉP SẢN PHẨM LIÊN QUAN XUỐNG CHÂN TRANG VỚI KHOẢNG CÁCH RỘNG RÃI
                          if (_relatedProducts.isNotEmpty) ...[
                            const SizedBox(height: 54),
                            const Divider(height: 1),
                            const SizedBox(height: 36),
                            SlideUpFadeTransition(
                              delay: const Duration(milliseconds: 520),
                              animate: widget.animateOnMount,
                              child: _buildRelatedProductsSection(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Shimmer skeleton hiện khi đang load, tự ẩn khi nội dung sẵn sàng
                  if (_isLoading) _buildShimmerLoading(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Định dạng giá tiền với dấu phẩy ngàn và ký hiệu "đ"
  String _formatPrice(double price) {
    final intVal = price.toInt();
    final formatted = intVal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return '$formatted đ';
  }

  /// Widget chọn số lượng: nút −, ô nhập tay, nút +
  /// Validation: không cho phép vượt quá _variantStock từ database
  Widget _buildQuantitySelector(bool isDark) {
    final maxQty = _variantStock > 0
        ? _variantStock
        : (_variants.isEmpty ? 99 : 0);
    final canBuy = maxQty > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Số lượng',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.deepBlack,
              ),
            ),
            if (canBuy) ...[
              const SizedBox(width: 8),
              Text(
                '(Tối đa $maxQty)',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Nút −
            _buildQtyButton(
              icon: Icons.remove,
              enabled: canBuy && _quantity > 1,
              onTap: () {
                if (_quantity > 1) {
                  setState(() {
                    _quantity--;
                    _quantityController.text = _quantity.toString();
                  });
                }
              },
              isDark: isDark,
            ),
            const SizedBox(width: 10),
            // Ô nhập số lượng
            Container(
              width: 68,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: canBuy
                      ? AppColors.luxuryGold.withValues(alpha: 0.6)
                      : Colors.grey.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _quantityController,
                focusNode: _quantityFocusNode,
                enabled: canBuy,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.deepBlack,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) {
                  if (val.trim().isEmpty) return;
                  final parsed = int.tryParse(val.trim());
                  if (parsed == null) return;
                  if (parsed > maxQty) {
                    setState(() {
                      _quantity = maxQty;
                      _quantityController.text = maxQty.toString();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Chỉ còn $maxQty sản phẩm trong kho!'),
                        backgroundColor: AppColors.danger,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else if (parsed >= 1) {
                    setState(() {
                      _quantity = parsed;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            // Nút +
            _buildQtyButton(
              icon: Icons.add,
              enabled: canBuy && _quantity < maxQty,
              onTap: () {
                if (_quantity < maxQty) {
                  setState(() {
                    _quantity++;
                    _quantityController.text = _quantity.toString();
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Chỉ còn $maxQty sản phẩm trong kho!'),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              isDark: isDark,
            ),
            const SizedBox(width: 16),
            // Tổng giá hiển thị khi qty > 1
            if (_quantity > 1 && canBuy)
              Expanded(
                child: Text(
                  '= ${_formatPrice(_currentPrice * _quantity)}',
                  style: const TextStyle(
                    color: AppColors.luxuryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildQtyButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? (isDark
                    ? AppColors.luxuryGold.withValues(alpha: 0.15)
                    : Colors.black)
              : Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? AppColors.luxuryGold
                : Colors.grey.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? (isDark ? AppColors.luxuryGold : AppColors.luxuryGold)
              : Colors.grey.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildVariantsColorSection() {
    final colors = _variants
        .map((v) => v['color'] as String?)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    if (colors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Màu sắc',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = _selectedColor == color;
            return ChoiceChip(
              label: Text(color),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedColor = color;
                    _updateSelectedVariant();
                  });
                }
              },
              selectedColor: AppColors.luxuryGold.withValues(alpha: 0.2),
              checkmarkColor: AppColors.luxuryGold,
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.luxuryGold : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isSelected
                      ? AppColors.luxuryGold
                      : Colors.grey.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVariantsSizeSection() {
    final sizes = _variants
        .map((v) => v['size'] as String?)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (sizes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kích cỡ',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sizes.map((size) {
            final isSelected = _selectedSize == size;
            return ChoiceChip(
              label: Text(size),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedSize = size;
                    _updateSelectedVariant();
                  });
                }
              },
              selectedColor: AppColors.luxuryGold.withValues(alpha: 0.2),
              checkmarkColor: AppColors.luxuryGold,
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.luxuryGold : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isSelected
                      ? AppColors.luxuryGold
                      : Colors.grey.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRelatedProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 18, color: AppColors.luxuryGold),
            const SizedBox(width: 8),
            const Text(
              'SẢN PHẨM CÙNG LOẠI',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _relatedProducts.length,
            itemBuilder: (context, index) {
              final prod = _relatedProducts[index];
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 14),
                child: InkWell(
                  onTap: () {
                    // Chuyển tiếp mượt mà dùng Hero flight, tắt animation slide-up khi vào sp liên quan
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductDetailPage(
                          product: prod,
                          animateOnMount: false,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ảnh sản phẩm liên quan — KHÔNG bọc Hero để tránh tag collision với home page
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: _buildSafeImage(
                            prod.imageUrl,
                            fit: BoxFit.cover,
                            placeholderIconSize: 32,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
                      // Tên sản phẩm
                      Text(
                        prod.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Giá sản phẩm liên quan
                      Row(
                        children: [
                          Text(
                            '${prod.price.toStringAsFixed(0)} đ',
                            style: const TextStyle(
                              color: AppColors.luxuryGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (prod.isDiscounted) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${(prod.price * 1.25).toStringAsFixed(0)} đ',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Điểm đánh giá sản phẩm liên quan
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.luxuryGold,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            prod.rating.toStringAsFixed(1),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
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
    this.animate =
        true, // false = hiện ngay không chạy animation (dùng khi navigate từ sp liên quan)
  });

  final Widget child;
  final Duration delay;
  final bool animate;

  @override
  State<SlideUpFadeTransition> createState() => _SlideUpFadeTransitionState();
}

class _SlideUpFadeTransitionState extends State<SlideUpFadeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  // Guard: animation chỉ chạy đúng 1 lần duy nhất khi widget được mount lần đầu.
  // Tránh trường hợp setState bên ngoài khiến animation bị replay gây hiệu ứng nhảy.
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (!_hasStarted) {
      _hasStarted = true;
      if (!widget.animate) {
        // Không chạy animation, hiện nội dung ngay lập tức
        _controller.value = 1.0;
      } else {
        Future.delayed(widget.delay, () {
          if (mounted && !_controller.isCompleted) {
            _controller.forward();
          }
        });
      }
    }
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
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
