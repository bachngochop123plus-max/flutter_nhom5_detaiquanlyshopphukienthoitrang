import 'dart:async';
import '../models/product.dart';
import '../models/product_category.dart';
import '../config/supabase_config.dart';
import 'database_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CatalogDataSource { unknown, supabase, sqliteCache }

class CatalogRepository {
  CatalogRepository({
    required DatabaseHelper databaseHelper,
  }) : _databaseHelper = databaseHelper;

  static const _storageBucket = 'Img_products';
  static const _storageFolder = 'Img_Product';

  final DatabaseHelper _databaseHelper;
  List<Product> _memoryProducts = const [];
  List<ProductCategory> _memoryCategories = const [];
  RealtimeChannel? _realtimeChannel;
  CatalogDataSource _lastDataSource = CatalogDataSource.unknown;
  bool _isUsingCacheFallback = false;
  String? _lastWarmUpError;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  CatalogDataSource get lastDataSource => _lastDataSource;

  bool get isUsingCacheFallback => _isUsingCacheFallback;

  String? get lastWarmUpError => _lastWarmUpError;

  String get dataSourceLabel {
    switch (_lastDataSource) {
      case CatalogDataSource.supabase:
        return 'Supabase';
      case CatalogDataSource.sqliteCache:
        return 'SQLite cache';
      case CatalogDataSource.unknown:
        return 'Unknown';
    }
  }

  String get runtimeSummary =>
      'catalogSource=$dataSourceLabel, cacheFallback=$isUsingCacheFallback, '
      'products=${_memoryProducts.length}';

  Future<void> warmUp() async {
    var localProducts = await _databaseHelper.getActiveCatalogProducts();
    if (localProducts.isEmpty) {
      localProducts = await _databaseHelper.getCatalogProducts();
    }
    if (localProducts.isNotEmpty) {
      _memoryProducts = localProducts;
      _lastDataSource = CatalogDataSource.sqliteCache;
    }

    _isUsingCacheFallback = false;
    _lastWarmUpError = null;

    // Load categories in background
    unawaited(loadCategories());

    // Sync from Supabase in background (cache to SQLite)
    if (_usesSupabase) {
      try {
        final remoteProducts = await _fetchProductsFromSupabase();
        // Sync to SQLite for offline fallback
        await _databaseHelper.replaceCatalogProducts(remoteProducts);
        _memoryProducts = remoteProducts;
        _lastDataSource = CatalogDataSource.supabase;
        _isUsingCacheFallback = false;
        // Start real-time sync listener
        startRealtimeSync();
        return;
      } catch (error, stackTrace) {
        _lastWarmUpError = error.toString();
        debugPrint(
          '[CatalogRepository] warmUp: Supabase sync failed. '
          'error=$error\n$stackTrace',
        );
        _isUsingCacheFallback = _memoryProducts.isNotEmpty;
        return;
      }
    }

    if (_memoryProducts.isNotEmpty) {
      _isUsingCacheFallback = true;
    }
  }

  /// Start real-time sync from Supabase products table
  void startRealtimeSync() {
    if (!_usesSupabase || _realtimeChannel != null) return;

    final client = Supabase.instance.client;
    _realtimeChannel = client.realtime.channel('realtime:public:products');

    _realtimeChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            // Auto-sync on any product change (INSERT/UPDATE/DELETE)
            _onSupabaseProductChange();
          },
        )
        .subscribe();
  }

  /// Stop real-time sync listener
  void stopRealtimeSync() {
    if (_realtimeChannel != null) {
      _realtimeChannel!.unsubscribe();
      Supabase.instance.client.realtime.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  /// Handle Supabase product change event
  Future<void> _onSupabaseProductChange() async {
    try {
      final refreshed = await _fetchProductsFromSupabase();
      await _databaseHelper.replaceCatalogProducts(refreshed);
      _memoryProducts = refreshed;
      _lastDataSource = CatalogDataSource.supabase;
      _isUsingCacheFallback = false;
    } catch (_) {
      // Ignore errors in background sync
    }
  }

  Future<List<Product>> refreshProducts() async {
    if (_usesSupabase) {
      try {
        final remoteProducts = await _fetchProductsFromSupabase();
        // Sync to SQLite for offline fallback
        await _databaseHelper.replaceCatalogProducts(remoteProducts);
        _memoryProducts = remoteProducts;
        _lastDataSource = CatalogDataSource.supabase;
        _isUsingCacheFallback = false;
        return _memoryProducts;
      } catch (error, stackTrace) {
        debugPrint(
          '[CatalogRepository] refreshProducts: Supabase failed. '
          'error=$error\n$stackTrace',
        );
        rethrow;
      }
    }

    final localProducts = await _databaseHelper.getCatalogProducts();
    if (localProducts.isNotEmpty) {
      _memoryProducts = localProducts;
      _lastDataSource = CatalogDataSource.sqliteCache;
    }
    return _memoryProducts;
  }

  List<Product> getProducts() {
    return _memoryProducts;
  }

  List<ProductCategory> getCategories() {
    return _memoryCategories;
  }

  Future<void> loadCategories() async {
    if (_usesSupabase) {
      try {
        final categories = await _fetchCategoriesFromSupabase();
        _memoryCategories = categories;
      } catch (error, stackTrace) {
        debugPrint(
          '[CatalogRepository] loadCategories: Failed to fetch categories. '
          'error=$error\n$stackTrace',
        );
      }
    }
  }

  /// Cleanup resources (call when app terminates)
  void dispose() {
    stopRealtimeSync();
  }

  Product byId(String id) =>
      getProducts().firstWhere((product) => product.id == id);

  Future<void> updateProduct(Product updated) async {
    if (_usesSupabase) {
      await _updateProductInSupabase(updated);
      final refreshed = await _fetchProductsFromSupabase();
      // Sync to SQLite cache after Supabase update
      await _databaseHelper.replaceCatalogProducts(refreshed);
      _memoryProducts = refreshed;
      return;
    }

    await _databaseHelper.updateCatalogProduct(updated);
    _memoryProducts = _memoryProducts
        .map((product) => product.id == updated.id ? updated : product)
        .toList(growable: false);
  }

  Future<Product> createProduct(Product draft, {int defaultStock = 0}) async {
    if (_usesSupabase) {
      final created = await _createProductInSupabase(draft,
          defaultStock: defaultStock);
      final refreshed = await _fetchProductsFromSupabase();
      // Sync to SQLite cache after Supabase create
      await _databaseHelper.replaceCatalogProducts(refreshed);
      _memoryProducts = refreshed;
      return created;
    }

    final created = await _createProductInLocalDb(draft,
        defaultStock: defaultStock);
    _memoryProducts = [created, ..._memoryProducts];
    return created;
  }

  Future<void> deleteProduct(String productId) async {
    if (_usesSupabase) {
      await _deleteProductInSupabase(productId);
      final refreshed = await _fetchProductsFromSupabase();
      // Sync to SQLite cache after Supabase delete
      await _databaseHelper.replaceCatalogProducts(refreshed);
      _memoryProducts = refreshed;
      return;
    }

    final parsedId = int.tryParse(productId);
    if (parsedId == null) return;

    await _databaseHelper.deleteProduct(parsedId);
    _memoryProducts = _memoryProducts
        .where((product) => product.id != productId)
        .toList(growable: false);
  }

  // ── Variant / stock management ──────────────────────────────────────────

  /// Lấy tất cả variants của sản phẩm (id, color, size, stock).
  /// Trả về list map với keys: id, color, size, stock.
  Future<List<Map<String, dynamic>>> getVariantsForProduct(
      String productId) async {
    final parsedId = int.tryParse(productId);
    if (parsedId == null) return [];

    if (_usesSupabase) {
      final client = Supabase.instance.client;
      final rows = await client
              .from('product_variants')
              .select('id, color, size, stock')
              .eq('product_id', parsedId)
              .order('id', ascending: true)
          as List<dynamic>;
      return rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    }

    final rows =
        await _databaseHelper.getVariantsForProduct(parsedId);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Cập nhật stock cho 1 variant.
  Future<void> updateVariantStock(int variantId, int newStock) async {
    if (_usesSupabase) {
      final client = Supabase.instance.client;
      await client.from('product_variants').update(
        {'stock': newStock},
      ).eq('id', variantId);
      return;
    }
    await _databaseHelper.updateVariantStock(variantId, newStock);
  }

  /// Lấy gallery ảnh của sản phẩm (danh sách URL theo sort_order).
  Future<List<String>> getGalleryForProduct(String productId) async {
    final parsedId = int.tryParse(productId);
    if (parsedId == null) return [];

    if (_usesSupabase) {
      final client = Supabase.instance.client;
      final rows = await client
              .from('product_images')
              .select('image_url, sort_order')
              .eq('product_id', parsedId)
              .order('sort_order', ascending: true)
          as List<dynamic>;
      return rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .map((r) => r['image_url']?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList();
    }

    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.productImagesTable,
      columns: ['image_url'],
      where: 'product_id = ?',
      whereArgs: [parsedId],
      orderBy: 'sort_order ASC',
    );
    return rows
        .map((r) => r['image_url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }


  Future<List<Product>> _fetchProductsFromSupabase() async {
    final client = Supabase.instance.client;
    final productRows =
        await client
                .from('products')
                .select()
                .order('created_at', ascending: false)
            as List<dynamic>;

    final categoryCache = <int, String>{};
    final products = <Product>[];

    for (final rawRow in productRows) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      products.add(
        await _toSupabaseProduct(
          client: client,
          row: row,
          categoryCache: categoryCache,
        ),
      );
    }

    return products;
  }

  Future<Product> _toSupabaseProduct({
    required SupabaseClient client,
    required Map<String, dynamic> row,
    required Map<int, String> categoryCache,
  }) async {
    final productId = row['id'] as int;
    final categoryId = (row['category_id'] as num?)?.toInt();

    String categoryName = 'Phu kien';
    if (categoryId != null) {
      if (categoryCache.containsKey(categoryId)) {
        categoryName = categoryCache[categoryId]!;
      } else {
        final categoryRows =
            await client
                    .from('categories')
                    .select('name')
                    .eq('id', categoryId)
                    .limit(1)
                as List<dynamic>;
        if (categoryRows.isNotEmpty) {
          final categoryRow = Map<String, dynamic>.from(
            categoryRows.first as Map,
          );
          categoryName = categoryRow['name']?.toString() ?? categoryName;
          categoryCache[categoryId] = categoryName;
        }
      }
    }

    final imageRows =
        await client
                .from('product_images')
                .select('image_url, sort_order')
                .eq('product_id', productId)
                .order('sort_order', ascending: true)
            as List<dynamic>;
    final variantRows =
        await client
                .from('product_variants')
                .select('color, size')
                .eq('product_id', productId)
            as List<dynamic>;

    final gallery = imageRows
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) => item['image_url']?.toString() ?? '')
        .map(_toPublicImageUrl)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final colors = variantRows
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) => item['color']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final sizes = variantRows
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) => item['size']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final thumbnail = _toPublicImageUrl(row['thumbnail']?.toString() ?? '');
    final fallbackImage = gallery.isNotEmpty ? gallery.first : '';

    return Product(
      id: productId.toString(),
      name: row['name']?.toString() ?? 'San pham',
      description: row['description']?.toString() ?? '',
      imageUrl: thumbnail.isNotEmpty ? thumbnail : fallbackImage,
      category: categoryName,
      price: ((row['base_price'] as num?) ?? 0).toDouble(),
      isDiscounted: row['is_discounted'] == true || row['is_discounted'] == 1,
      rating: ((row['rating_avg'] as num?) ?? 0).toDouble(),
      gallery: gallery,
      availableColors: colors,
      availableSizes: sizes,
    );
  }

  String _toPublicImageUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final normalizedPath = value.contains('/')
        ? value
        : '$_storageFolder/$value';

    return Supabase.instance.client.storage
        .from(_storageBucket)
        .getPublicUrl(normalizedPath);
  }

  Future<void> _updateProductInSupabase(Product updated) async {
    final productId = int.tryParse(updated.id);
    if (productId == null) {
      throw Exception('Supabase product id khong hop le');
    }

    final client = Supabase.instance.client;
    final categoryId = await _resolveCategoryId(client, updated.category);
    await client
        .from('products')
        .update({
          'category_id': categoryId,
          'name': updated.name,
          'description': updated.description,
          'base_price': updated.price,
          'thumbnail': updated.imageUrl,
          'is_discounted': updated.isDiscounted,
          'rating_avg': updated.rating,
        })
        .eq('id', productId);

    await client.from('product_images').delete().eq('product_id', productId);
    final gallery = updated.gallery.isNotEmpty
        ? updated.gallery
        : (updated.imageUrl.isNotEmpty ? [updated.imageUrl] : const <String>[]);
    for (var i = 0; i < gallery.length; i++) {
      await client.from('product_images').insert({
        'product_id': productId,
        'image_url': gallery[i],
        'sort_order': i,
      });
    }
  }

  Future<Product> _createProductInSupabase(Product draft,
      {int defaultStock = 0}) async {
    final client = Supabase.instance.client;
    final categoryId = await _resolveCategoryId(client, draft.category);
    final inserted = await client
        .from('products')
        .insert({
          'category_id': categoryId,
          'name': draft.name,
          'description': draft.description,
          'base_price': draft.price,
          'thumbnail': draft.imageUrl,
          'is_discounted': draft.isDiscounted,
          'rating_avg': draft.rating,
          'rating_count': 0,
        })
        .select('id')
        .single();

    final productId = (inserted['id'] as num).toInt();
    final gallery = draft.gallery.isNotEmpty
        ? draft.gallery
        : (draft.imageUrl.isNotEmpty ? [draft.imageUrl] : const <String>[]);

    for (var i = 0; i < gallery.length; i++) {
      await client.from('product_images').insert({
        'product_id': productId,
        'image_url': gallery[i],
        'sort_order': i,
      });
    }

    await _insertVariants(
      client,
      productId,
      draft.availableColors,
      draft.availableSizes,
      defaultStock: defaultStock,
    );

    return draft.copyWith(id: productId.toString());
  }

  Future<void> _deleteProductInSupabase(String productId) async {
    final parsedId = int.tryParse(productId);
    if (parsedId == null) {
      throw Exception('Supabase product id khong hop le');
    }

    final client = Supabase.instance.client;

    final productRows =
        await client
                .from('products')
                .select('thumbnail')
                .eq('id', parsedId)
                .limit(1)
            as List<dynamic>;
    final thumbnail = productRows.isNotEmpty
        ? Map<String, dynamic>.from(
                productRows.first as Map,
              )['thumbnail']?.toString() ??
              ''
        : '';

    final imageRows =
        await client
                .from('product_images')
                .select('image_url')
                .eq('product_id', parsedId)
            as List<dynamic>;

    final storagePaths = <String>{};
    if (thumbnail.isNotEmpty) {
      final path = _extractStoragePath(thumbnail);
      if (path.isNotEmpty) {
        storagePaths.add(path);
      }
    }
    for (final raw in imageRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final imageUrl = row['image_url']?.toString() ?? '';
      final path = _extractStoragePath(imageUrl);
      if (path.isNotEmpty) {
        storagePaths.add(path);
      }
    }

    if (storagePaths.isNotEmpty) {
      await client.storage.from(_storageBucket).remove(storagePaths.toList());
    }

    await client.from('product_images').delete().eq('product_id', parsedId);
    await client.from('product_variants').delete().eq('product_id', parsedId);
    await client.from('products').delete().eq('id', parsedId);
  }

  String _extractStoragePath(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      if (value.startsWith('$_storageFolder/')) {
        return value;
      }
      if (value.contains('/')) {
        return value;
      }
      return '$_storageFolder/$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return '';

    final marker = '/storage/v1/object/public/$_storageBucket/';
    final fullPath = uri.path;
    final markerIndex = fullPath.indexOf(marker);
    if (markerIndex == -1) return '';

    final path = fullPath.substring(markerIndex + marker.length);
    return path.trim();
  }

  Future<Product> _createProductInLocalDb(Product draft,
      {int defaultStock = 0}) async {
    final db = await _databaseHelper.database;
    final categoryId = await _resolveLocalCategoryId(db, draft.category);
    final productId = await db.insert(DatabaseHelper.productsTable, {
      'category_id': categoryId,
      'name': draft.name,
      'description': draft.description,
      'base_price': draft.price,
      'thumbnail': draft.imageUrl,
      'is_discounted': draft.isDiscounted ? 1 : 0,
      'rating_avg': draft.rating,
      'rating_count': 0,
    });

    final gallery = draft.gallery.isNotEmpty
        ? draft.gallery
        : (draft.imageUrl.isNotEmpty ? [draft.imageUrl] : const <String>[]);
    for (var i = 0; i < gallery.length; i++) {
      await db.insert(DatabaseHelper.productImagesTable, {
        'product_id': productId,
        'image_url': gallery[i],
        'sort_order': i,
      });
    }

    await _insertLocalVariants(
      db,
      productId,
      draft.availableColors,
      draft.availableSizes,
      defaultStock: defaultStock,
    );

    return draft.copyWith(id: productId.toString());
  }

  Future<void> _insertVariants(
    SupabaseClient client,
    int productId,
    List<String> colors,
    List<String> sizes, {
    int defaultStock = 0,
  }) async {
    if (colors.isEmpty && sizes.isEmpty) {
      await client.from('product_variants').insert({
        'product_id': productId,
        'stock': defaultStock,
      });
      return;
    }

    if (colors.isEmpty) {
      for (final size in sizes) {
        await client.from('product_variants').insert({
          'product_id': productId,
          'size': size,
          'stock': defaultStock,
        });
      }
      return;
    }

    if (sizes.isEmpty) {
      for (final color in colors) {
        await client.from('product_variants').insert({
          'product_id': productId,
          'color': color,
          'stock': defaultStock,
        });
      }
      return;
    }

    for (final color in colors) {
      for (final size in sizes) {
        await client.from('product_variants').insert({
          'product_id': productId,
          'color': color,
          'size': size,
          'stock': defaultStock,
        });
      }
    }
  }

  Future<void> _insertLocalVariants(
    dynamic db,
    int productId,
    List<String> colors,
    List<String> sizes, {
    int defaultStock = 0,
  }) async {
    if (colors.isEmpty && sizes.isEmpty) {
      await db.insert(DatabaseHelper.productVariantsTable, {
        'product_id': productId,
        'stock': defaultStock,
      });
      return;
    }

    if (colors.isEmpty) {
      for (final size in sizes) {
        await db.insert(DatabaseHelper.productVariantsTable, {
          'product_id': productId,
          'size': size,
          'stock': defaultStock,
        });
      }
      return;
    }

    if (sizes.isEmpty) {
      for (final color in colors) {
        await db.insert(DatabaseHelper.productVariantsTable, {
          'product_id': productId,
          'color': color,
          'stock': defaultStock,
        });
      }
      return;
    }

    for (final color in colors) {
      for (final size in sizes) {
        await db.insert(DatabaseHelper.productVariantsTable, {
          'product_id': productId,
          'color': color,
          'size': size,
          'stock': defaultStock,
        });
      }
    }
  }

  Future<int> _resolveLocalCategoryId(dynamic db, String categoryName) async {
    final rows = await db.query(
      DatabaseHelper.categoriesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [categoryName],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['id'] as int;
    }

    return db.insert(DatabaseHelper.categoriesTable, {'name': categoryName});
  }

  Future<List<ProductCategory>> _fetchCategoriesFromSupabase() async {
    final client = Supabase.instance.client;
    final categoryRows =
        await client.from('categories').select().order('id', ascending: true)
            as List<dynamic>;

    return categoryRows
        .map(
          (row) =>
              ProductCategory.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<int> _resolveCategoryId(
    SupabaseClient client,
    String categoryName,
  ) async {
    final categoryRows =
        await client
                .from('categories')
                .select('id')
                .eq('name', categoryName)
                .limit(1)
            as List<dynamic>;
    if (categoryRows.isNotEmpty) {
      final row = Map<String, dynamic>.from(categoryRows.first as Map);
      return (row['id'] as num).toInt();
    }

    final inserted = await client
        .from('categories')
        .insert({'name': categoryName})
        .select('id')
        .single();
    return (inserted['id'] as num).toInt();
  }
}
