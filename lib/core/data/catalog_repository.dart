import '../errors/failure.dart';
import '../models/product.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../config/supabase_config.dart';
import 'database_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CatalogDataSource { unknown, supabase, api, sqliteCache }

class CatalogRepository {
  CatalogRepository({
    required ApiService apiService,
    required DatabaseHelper databaseHelper,
  }) : _apiService = apiService,
       _databaseHelper = databaseHelper;

  static const _storageBucket = 'Img_products';
  static const _storageFolder = 'Img_Product';

  final ApiService _apiService;
  final DatabaseHelper _databaseHelper;
  List<Product> _memoryProducts = const [];
  RealtimeChannel? _realtimeChannel;
  CatalogDataSource _lastDataSource = CatalogDataSource.unknown;
  bool _isUsingCacheFallback = false;
  String? _lastWarmUpError;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  bool get _hasApiFallback => ApiConfig.instance.hasProductsUrl;

  bool get _usesApi => !_usesSupabase && _hasApiFallback;

  String get _productsUrl => ApiConfig.instance.productsUrl;

  CatalogDataSource get lastDataSource => _lastDataSource;

  bool get isUsingCacheFallback => _isUsingCacheFallback;

  String? get lastWarmUpError => _lastWarmUpError;

  String get dataSourceLabel {
    switch (_lastDataSource) {
      case CatalogDataSource.supabase:
        return 'Supabase';
      case CatalogDataSource.api:
        return 'Products API';
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
    // Read active cache first so hidden/inactive products do not leak into UI.
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
          '[CatalogRepository] warmUp: Supabase sync failed, trying API fallback. '
          'error=$error\n$stackTrace',
        );
        if (_hasApiFallback) {
          try {
            await refreshFromApiAndCache();
            _isUsingCacheFallback = false;
          } on ApiFailure catch (apiError) {
            _isUsingCacheFallback = _memoryProducts.isNotEmpty;
            debugPrint(
              '[CatalogRepository] warmUp: API fallback also failed '
              '(code=${apiError.code}): ${apiError.message}',
            );
          }
        } else {
          _isUsingCacheFallback = _memoryProducts.isNotEmpty;
        }
        return;
      }
    }

    // Fallback to API JSON if Supabase not configured
    if (_usesApi) {
      try {
        final remoteProducts = await _fetchProductsFromApi();
        if (remoteProducts.isNotEmpty) {
          await _databaseHelper.replaceCatalogProducts(remoteProducts);
          _memoryProducts = remoteProducts;
          _lastDataSource = CatalogDataSource.api;
          _isUsingCacheFallback = false;
        }
      } on ApiFailure catch (apiError) {
        _lastWarmUpError = apiError.message;
        _isUsingCacheFallback = _memoryProducts.isNotEmpty;
        // Keep local cache as-is when API unavailable.
      }
    } else if (_memoryProducts.isNotEmpty) {
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
          '[CatalogRepository] refreshProducts: Supabase failed, trying API fallback. '
          'error=$error\n$stackTrace',
        );
        if (_hasApiFallback) {
          return refreshFromApiAndCache();
        }
        rethrow;
      }
    }

    return refreshFromApiAndCache();
  }

  Future<List<Product>> refreshFromApiAndCache() async {
    if (!_hasApiFallback) {
      throw const ApiFailure(
        message: 'Chua cau hinh PRODUCTS_API_URL cho API fallback',
        code: 'API_FALLBACK_NOT_CONFIGURED',
      );
    }

    final remoteProducts = await _fetchProductsFromApi();
    await _databaseHelper.replaceCatalogProducts(remoteProducts);
    _memoryProducts = remoteProducts;
    _lastDataSource = CatalogDataSource.api;
    _isUsingCacheFallback = false;
    return _memoryProducts;
  }

  Future<List<Product>> _fetchProductsFromApi() async {
    final payload = await _apiService.getJson(Uri.parse(_productsUrl));
    final items = payload['products'] ?? payload['data'];
    if (items is! List) {
      final payloadKeys = payload.keys.join(',');
      throw ApiFailure(
        message:
            'API products khong dung dinh dang. Can list trong key "products" hoac "data" '
            '(url=$_productsUrl, keys=[$payloadKeys])',
        code: 'INVALID_PRODUCTS_PAYLOAD',
      );
    }

    return items
        .whereType<Map>()
        .map((item) => _mapApiProduct(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Product _mapApiProduct(Map<String, dynamic> raw) {
    final images = raw['images'] is List
        ? (raw['images'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final image =
        raw['thumbnail']?.toString() ??
        (images.isNotEmpty ? images.first : raw['image']?.toString() ?? '');

    return Product.fromApiMap({
      'id': raw['id'],
      'name': raw['title'] ?? raw['name'],
      'description': raw['description'],
      'image': image,
      'category': raw['category'],
      'price': raw['price'],
      'isDiscounted': false,
      'rating': raw['rating'],
      'gallery': images,
      'availableColors': const ['Default'],
      'availableSizes': const ['Free size'],
    });
  }

  List<Product> getProducts() {
    return _memoryProducts;
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

  Future<Product> createProduct(Product draft) async {
    if (_usesSupabase) {
      final created = await _createProductInSupabase(draft);
      final refreshed = await _fetchProductsFromSupabase();
      // Sync to SQLite cache after Supabase create
      await _databaseHelper.replaceCatalogProducts(refreshed);
      _memoryProducts = refreshed;
      return created;
    }

    final created = await _createProductInLocalDb(draft);
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

  Future<Product> _createProductInSupabase(Product draft) async {
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

  Future<Product> _createProductInLocalDb(Product draft) async {
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
    );

    return draft.copyWith(id: productId.toString());
  }

  Future<void> _insertVariants(
    SupabaseClient client,
    int productId,
    List<String> colors,
    List<String> sizes,
  ) async {
    if (colors.isEmpty && sizes.isEmpty) {
      await client.from('product_variants').insert({
        'product_id': productId,
        'stock': 0,
      });
      return;
    }

    if (colors.isEmpty) {
      for (final size in sizes) {
        await client.from('product_variants').insert({
          'product_id': productId,
          'size': size,
          'stock': 0,
        });
      }
      return;
    }

    if (sizes.isEmpty) {
      for (final color in colors) {
        await client.from('product_variants').insert({
          'product_id': productId,
          'color': color,
          'stock': 0,
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
          'stock': 0,
        });
      }
    }
  }

  Future<void> _insertLocalVariants(
    dynamic db,
    int productId,
    List<String> colors,
    List<String> sizes,
  ) async {
    if (colors.isEmpty && sizes.isEmpty) {
      await db.insert(DatabaseHelper.productVariantsTable, {
        'product_id': productId,
        'stock': 0,
      });
      return;
    }

    if (colors.isEmpty) {
      for (final size in sizes) {
        await db.insert(DatabaseHelper.productVariantsTable, {
          'product_id': productId,
          'size': size,
          'stock': 0,
        });
      }
      return;
    }

    if (sizes.isEmpty) {
      for (final color in colors) {
        await db.insert(DatabaseHelper.productVariantsTable, {
          'product_id': productId,
          'color': color,
          'stock': 0,
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
          'stock': 0,
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
