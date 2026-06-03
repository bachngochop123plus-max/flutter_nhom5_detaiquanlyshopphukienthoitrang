import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
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

  @override
  void initState() {
    super.initState();
    _currentOfflineState = widget.isOffline;
    _currentProducts = widget.products;
    _registerConnectivityListener();
  }

  @override
  void dispose() {
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
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã mất kết nối mạng. Bạn đang ở chế độ ngoại tuyến.'),
                backgroundColor: Colors.orange,
              ),
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
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.wifi, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đã khôi phục kết nối! Đang cập nhật sản phẩm mới...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFFC6A15B),
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      final catalogRepository = GetIt.instance<CatalogRepository>();
      final freshProducts = await catalogRepository.refreshProducts();
      if (mounted) {
        setState(() {
          _currentProducts = freshProducts;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đồng bộ sản phẩm mới thành công!'),
            backgroundColor: Colors.green,
          ),
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
          title: 'Trang chủ',
          actions: [
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
                      context.read<AuthCubit>().logout();
                      context.go('/home');
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
                      context.read<AuthCubit>().logout();
                      context.go('/home');
                    },
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ],
              ),
          ],
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF111111), Color(0xFFC6A15B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Luxury Accessories',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Bộ sưu tập phụ kiện thời trang\ncho đồ án Flutter',
                        style: TextStyle(
                          color: Color(0xFFF6E8C7),
                          fontSize: 18,
                          height: 1.4,
                        ),
                      ),
                    ],
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
              // Categories
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Tất cả'),
                            selected: _categoryFilter == null,
                            onSelected: (_) =>
                                setState(() => _categoryFilter = null),
                          ),
                          if (categories.isEmpty)
                            ...[
                              'Túi Xách Thời Trang',
                              'Kính Mắt Gentry',
                              'Đồng Hồ Cao Cấp',
                              'Trang Sức Quý Phái',
                              'Mũ & Nón Thời Trang',
                            ].map(
                              (category) => ChoiceChip(
                                label: Text(category),
                                selected: _categoryFilter == category,
                                onSelected: (_) =>
                                    setState(() => _categoryFilter = category),
                              ),
                            )
                          else
                            ...categories.map(
                              (category) => ChoiceChip(
                                label: Text(category.name),
                                selected: _categoryFilter == category.name,
                                onSelected: (_) => setState(
                                  () => _categoryFilter = category.name,
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final displayImageUrl = product.imageUrl.isNotEmpty
        ? product.imageUrl
        : (product.gallery.isNotEmpty ? product.gallery.first : '');

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.go('/home/product', extra: product),
      child: Card(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: displayImageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                  if (product.isDiscounted)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _Badge(text: 'Giảm giá'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.category,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${product.price.toStringAsFixed(0)} đ',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
