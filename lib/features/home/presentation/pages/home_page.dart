import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/widgets/app_notifications.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../../core/utils/auth_guard.dart';
import '../widgets/product_search_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.products,
    required this.isOffline,
  });

  final List<Product> products;
  final bool isOffline;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _categoryFilter;
  String _searchQuery = '';
  double? _minPrice;
  double? _maxPrice;

  late bool _currentOfflineState;
  late List<Product> _currentProducts;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  final PageController _bannerPageController = PageController(initialPage: 0);
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  final List<Map<String, String>> _banners = [
    {
      'image': 'assets/images/banner_bags.png',
      'title': 'Luxury Accessories',
      'subtitle': 'Bộ sưu tập túi xách thượng lưu',
    },
    {
      'image': 'assets/images/banner_watches.png',
      'title': 'Gentry Watches',
      'subtitle': 'Đồng hồ cơ khí đẳng cấp quý ông',
    },
    {
      'image': 'assets/images/banner_sunglasses.png',
      'title': 'Designer Eyewear',
      'subtitle': 'Kính mắt thời trang sang trọng',
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentOfflineState = widget.isOffline;
    _currentProducts = widget.products;
    _registerConnectivityListener();
    _startBannerAutoPlay();
  }

  void _startBannerAutoPlay() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerPageController.hasClients) {
        final nextPage = (_currentBannerIndex + 1) % _banners.length;
        _bannerPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _registerConnectivityListener() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasNetwork = results.any((result) => result != ConnectivityResult.none);
      final isNowOffline = !hasNetwork;

      if (_currentOfflineState != isNowOffline) {
        setState(() {
          _currentOfflineState = isNowOffline;
        });

        if (hasNetwork) {
          _syncProductsInBackground();
        } else {
          if (mounted) {
            AppNotifications.showErrorSnackBar(
              context,
              'Đã mất kết nối mạng. Bạn đang ở chế độ ngoại tuyến.',
            );
          }
        }
      }
    });
  }

  Future<void> _syncProductsInBackground() async {
    if (_isSyncing) return;
    _isSyncing = true;

    if (mounted) {
      AppNotifications.showInfoSnackBar(
        context,
        'Đã khôi phục kết nối! Đang cập nhật sản phẩm mới...',
      );
    }

    try {
      final catalogRepository = GetIt.instance<CatalogRepository>();
      final freshProducts = await catalogRepository.refreshProducts();
      if (mounted) {
        setState(() {
          _currentProducts = freshProducts;
        });
        AppNotifications.showSuccessSnackBar(
          context,
          'Đồng bộ sản phẩm mới thành công!',
        );
      }
    } catch (e) {
      debugPrint('[SyncError] Không thể đồng bộ sản phẩm: $e');
    } finally {
      _isSyncing = false;
    }
  }

  List<Product> _getFilteredProducts(List<Product> products) {
    var filtered = products;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (product) =>
                product.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                product.description.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }

    // Filter by price range
    if (_minPrice != null) {
      filtered = filtered
          .where((product) => product.price >= _minPrice!)
          .toList();
    }
    if (_maxPrice != null) {
      filtered = filtered
          .where((product) => product.price <= _maxPrice!)
          .toList();
    }

    // Filter by category
    if (_categoryFilter != null) {
      filtered = filtered
          .where((product) => product.category == _categoryFilter)
          .toList(growable: false);
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final catalogRepository = GetIt.instance<CatalogRepository>();
    final isCacheFallback = catalogRepository.isUsingCacheFallback;
    final categories = catalogRepository.getCategories();

    final filteredProducts = _getFilteredProducts(_currentProducts);

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        return BaseScreen(
          title: '',
          actions: [
            IconButton(
              tooltip: 'Làm mới sản phẩm',
              onPressed: _isSyncing ? null : _syncProductsInBackground,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFC6A15B),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Chip(
                label: Text(
                  _currentOfflineState ? 'OFFLINE' : 'ONLINE',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: _currentOfflineState ? Colors.red : Colors.green,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            // Phần phân quyền của AppBar: chưa đăng nhập thì hiện Login,
            // còn đã đăng nhập thì hiển thị lối tắt đúng theo vai trò.
            if (!authState.isAuthenticated)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  // Dùng push để trang đăng nhập có thể quay lại trang trước đó.
                  onPressed: () => context.push('/login'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Login'),
                ),
              )
            else if (authState.isAdmin)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Admin Panel',
                    onPressed: () => context.go('/admin'),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Đăng xuất',
                    onPressed: () {
                      AppNotifications.showConfirmationDialog(
                        context,
                        title: 'Xác nhận đăng xuất',
                        content: 'Bạn có chắc chắn muốn đăng xuất không?',
                        confirmText: 'Đăng xuất',
                        cancelText: 'Hủy',
                        isDanger: true,
                        onConfirm: () {
                          context.read<AuthCubit>().logout();
                          context.go('/home');
                        },
                      );
                    },
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Profile',
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.person_outline),
                  ),
                  IconButton(
                    tooltip: 'Đăng xuất',
                    onPressed: () {
                      AppNotifications.showConfirmationDialog(
                        context,
                        title: 'Xác nhận đăng xuất',
                        content: 'Bạn có chắc chắn muốn đăng xuất không?',
                        confirmText: 'Đăng xuất',
                        cancelText: 'Hủy',
                        isDanger: true,
                        onConfirm: () {
                          context.read<AuthCubit>().logout();
                          context.go('/home');
                        },
                      );
                    },
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ],
              ),
          ],
          body: CustomScrollView(
            slivers: [
              // Auto-playing Banner Slider
              SliverToBoxAdapter(
                child: Container(
                  height: 180,
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _bannerPageController,
                          itemCount: _banners.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentBannerIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            final banner = _banners[index];
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  banner['image']!,
                                  fit: BoxFit.cover,
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.65),
                                        Colors.transparent,
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 20,
                                  left: 20,
                                  right: 20,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        banner['title']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        banner['subtitle']!,
                                        style: const TextStyle(
                                          color: Color(0xFFF6E8C7),
                                          fontSize: 13,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        Positioned(
                          bottom: 12,
                          right: 20,
                          child: Row(
                            children: List.generate(
                              _banners.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(right: 6),
                                width: _currentBannerIndex == index ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _currentBannerIndex == index
                                      ? const Color(0xFFC6A15B)
                                      : Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Shop Trust Decorators Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B1B1B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.grey[900]! : Colors.grey[200]!,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildShopFeature(context, Icons.verified_user_outlined, '100% Chính hãng'),
                            _buildShopFeature(context, Icons.local_shipping_outlined, 'Giao hàng nhanh'),
                            _buildShopFeature(context, Icons.workspace_premium_outlined, 'Bảo hành 2 năm'),
                          ],
                        ),
                      );
                    }
                  ),
                ),
              ),
              if (isCacheFallback)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFD58A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFB26A00),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Đang hiển thị dữ liệu cache cũ. Kiểm tra kết nối Supabase nếu dữ liệu không mới.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF6B4100)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Search Bar
              SliverToBoxAdapter(
                child: ProductSearchBar(
                  onSearch: (query, {minPrice, maxPrice}) {
                    setState(() {
                      _searchQuery = query;
                      _minPrice = minPrice;
                      _maxPrice = maxPrice;
                    });
                  },
                  onPriceRangeChanged: (minPrice, maxPrice) {
                    setState(() {
                      _minPrice = minPrice;
                      _maxPrice = maxPrice;
                    });
                  },
                ),
              ),
              // Categories (Scrollable)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildCategoryTab(
                          context,
                          label: 'Tất cả',
                          isSelected: _categoryFilter == null,
                          onSelected: () => setState(() => _categoryFilter = null),
                        ),
                        if (categories.isEmpty)
                          ...[
                            'Túi Xách Thời Trang',
                            'Kính Mắt Gentry',
                            'Đồng Hồ Cao Cấp',
                            'Trang Sức Quý Phái',
                            'Mũ & Nón Thời Trang',
                          ].map(
                            (category) => _buildCategoryTab(
                              context,
                              label: category,
                              isSelected: _categoryFilter == category,
                              onSelected: () => setState(() => _categoryFilter = category),
                            ),
                          )
                        else
                          ...categories.map(
                            (category) => _buildCategoryTab(
                              context,
                              label: category.name,
                              isSelected: _categoryFilter == category.name,
                              onSelected: () => setState(() => _categoryFilter = category.name),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Result count
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Kết quả: ${filteredProducts.length} sản phẩm',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              // Products grid
              if (filteredProducts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Không tìm thấy sản phẩm',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Vui lòng thử lại với bộ lọc khác',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final product = filteredProducts[index];
                      return _ProductCard(product: product);
                    }, childCount: filteredProducts.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryTab(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? const Color(0xFFC6A15B) : const Color(0xFF111111))
                  : (isDark ? const Color(0xFF1B1B1B) : Colors.white),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? Colors.transparent
                    : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey[400] : Colors.grey[800]),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShopFeature(BuildContext context, IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: const Color(0xFFC6A15B),
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[300] : const Color(0xFF4A4A4A),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final authState = context.read<AuthCubit>().state;
    if (!authState.isAuthenticated) {
      if (mounted) {
        setState(() {
          _isFav = false;
        });
      }
      return;
    }
    final productId = int.tryParse(widget.product.id);
    if (productId != null) {
      final isFav = await DatabaseHelper.instance.isFavorite(authState.profile!.id, productId);
      if (mounted) {
        setState(() {
          _isFav = isFav;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!AuthGuard.requireLogin(context)) return;
    final authState = context.read<AuthCubit>().state;
    final userId = authState.profile!.id;
    final productId = int.tryParse(widget.product.id);
    if (productId != null) {
      final newFav = await DatabaseHelper.instance.toggleFavorite(userId, productId);
      setState(() {
        _isFav = newFav;
      });
      if (mounted) {
        AppNotifications.showSuccessSnackBar(
          context,
          newFav ? 'Đã thêm vào mục yêu thích' : 'Đã xóa khỏi mục yêu thích',
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.animateTo(0.94);
  }

  void _onTapUp(TapUpDetails details) {
    _controller.animateTo(1.0);
  }

  void _onTapCancel() {
    _controller.animateTo(1.0);
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

  Widget _buildSafeImage(String imageUrl) {
    final cleanUrl = _resolveImageUrl(imageUrl);
    if (cleanUrl.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey),
        ),
      );
    }
    if (cleanUrl.startsWith('assets/') || cleanUrl.startsWith('images/')) {
      return Image.asset(
        cleanUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.image_not_supported_outlined, color: Colors.grey),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: cleanUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFC6A15B)),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cleanImgUrl = _resolveImageUrl(widget.product.imageUrl);
    final isImgUrlValid = cleanImgUrl.isNotEmpty &&
        cleanImgUrl != 'null' &&
        cleanImgUrl != 'undefined' &&
        !cleanImgUrl.endsWith('/null') &&
        !cleanImgUrl.endsWith('/undefined') &&
        !cleanImgUrl.toLowerCase().contains('placeholder');

    final displayImageUrl = isImgUrlValid
        ? cleanImgUrl
        : widget.product.gallery
            .map((url) => _resolveImageUrl(url))
            .firstWhere(
              (url) =>
                  url.isNotEmpty &&
                  url != 'null' &&
                  url != 'undefined' &&
                  !url.endsWith('/null') &&
                  !url.endsWith('/undefined') &&
                  !url.toLowerCase().contains('placeholder'),
              orElse: () => '',
            );

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        context.go('/home/product', extra: widget.product);
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111111) : const Color(0xFFFBF9F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF3B3120) : const Color(0xFF4A3F28),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'product-image-${widget.product.id}',
                        child: _buildSafeImage(displayImageUrl),
                      ),
                      if (widget.product.isDiscounted)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC6A15B),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'SALE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _toggleFavorite,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: _isFav ? const Color(0xFFB23A48) : Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 1.0,
                color: isDark ? const Color(0xFF3B3120) : const Color(0xFF4A3F28),
              ),
              Container(
                color: isDark ? const Color(0xFF1B160E) : const Color(0xFFF6EFE0),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.category.toUpperCase(),
                      style: TextStyle(
                        color: isDark ? const Color(0xFFC6A15B).withValues(alpha: 0.7) : const Color(0xFF8A7A5F),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF111111),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF251E14) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFC6A15B).withValues(alpha: 0.4),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            '${widget.product.price.toStringAsFixed(0)} đ',
                            style: TextStyle(
                              color: isDark ? const Color(0xFFC6A15B) : const Color(0xFF8C6D30),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC6A15B).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart_rounded,
                            color: Color(0xFFC6A15B),
                            size: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
