import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'fashion_shop.db';
  static const _databaseVersion = 5;
  static const _legacyDefaultUserId = 1;

  // ── Core domain tables ──────────────────────────────────────────────────────
  static const rolesTable = 'roles';
  static const usersTable = 'users';
  static const categoriesTable = 'categories';
  static const productsTable = 'products';
  static const productVariantsTable = 'product_variants';
  static const productImagesTable = 'product_images';
  static const productTagsTable = 'product_tags';
  static const favoritesTable = 'favorites';
  static const ordersTable = 'orders';
  static const orderItemsTable = 'order_items';
  static const reviewsTable = 'reviews';

  // ── Legacy tables (kept for migration only) ──────────────────────────────
  static const _legacyCatalogTable = 'catalog_products';

  Database? _database;

  // ── Initialisation ───────────────────────────────────────────────────────

  Future<void> init() async {
    _database ??= await _openDatabase();
  }

  Future<Database> get database async {
    _database ??= await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final filePath = path.join(databasesPath, _databaseName);

    return openDatabase(
      filePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        await _createAllTables(db);
        await _seedRoles(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1→v2 / v2→v3: legacy migrations (kept for existing installs)
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
        // v3→v4: replace legacy dual-table design with the normalised schema
        if (oldVersion < 4) {
          await _migrateToV4(db);
        }
        // v4→v5: add product activation support for admin enable/disable flows
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
      },
    );
  }

  // ── Schema creation ──────────────────────────────────────────────────────

  Future<void> _createAllTables(Database db) async {
    // roles ─────────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $rolesTable (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL UNIQUE,
        permissions TEXT   NOT NULL DEFAULT ''
      )
    ''');

    // users ─────────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $usersTable (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        role_id       INTEGER NOT NULL DEFAULT 2,
        full_name     TEXT    NOT NULL,
        email         TEXT    NOT NULL UNIQUE,
        password_hash TEXT    NOT NULL,
        phone         TEXT,
        address       TEXT,
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (role_id) REFERENCES $rolesTable(id)
          ON DELETE RESTRICT ON UPDATE CASCADE
      )
    ''');

    // categories (self-referencing for sub-categories) ──────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $categoriesTable (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name      TEXT NOT NULL,
        image_url TEXT,
        FOREIGN KEY (parent_id) REFERENCES $categoriesTable(id)
          ON DELETE SET NULL ON UPDATE CASCADE
      )
    ''');

    // products ──────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $productsTable (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id  INTEGER NOT NULL,
        name         TEXT    NOT NULL,
        description  TEXT,
        base_price   REAL    NOT NULL,
        thumbnail    TEXT,
        is_discounted INTEGER NOT NULL DEFAULT 0,
        is_active    INTEGER NOT NULL DEFAULT 1,
        rating_avg   REAL    NOT NULL DEFAULT 0,
        rating_count INTEGER NOT NULL DEFAULT 0,
        created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (category_id) REFERENCES $categoriesTable(id)
          ON DELETE RESTRICT ON UPDATE CASCADE
      )
    ''');

    // product_variants (colour × size × stock) ──────────────────────────────
    // price_delta: offset from base_price (can be 0, positive, or negative)
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $productVariantsTable (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id  INTEGER NOT NULL,
        color       TEXT,
        size        TEXT,
        stock       INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
        price_delta REAL    NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES $productsTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // product_images (replaces JSON gallery column) ─────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $productImagesTable (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        image_url  TEXT    NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES $productsTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // product_tags (used to compute related products) ───────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $productTagsTable (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        tag        TEXT    NOT NULL,
        UNIQUE (product_id, tag),
        FOREIGN KEY (product_id) REFERENCES $productsTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // favorites ─────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $favoritesTable (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        added_at   TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE (user_id, product_id),
        FOREIGN KEY (user_id)    REFERENCES $usersTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY (product_id) REFERENCES $productsTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // orders ────────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $ordersTable (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id          INTEGER NOT NULL,
        order_date       TEXT    NOT NULL DEFAULT (datetime('now')),
        total_amount     REAL    NOT NULL,
        status           TEXT    NOT NULL DEFAULT 'pending' CHECK (
          status IN ('pending','processing','shipped','delivered','cancelled')
        ),
        payment_status   TEXT    NOT NULL DEFAULT 'unpaid' CHECK (
          payment_status IN ('unpaid','paid','refunded')
        ),
        payment_method   TEXT,
        shipping_address TEXT    NOT NULL,
        FOREIGN KEY (user_id) REFERENCES $usersTable(id)
          ON DELETE RESTRICT ON UPDATE CASCADE
      )
    ''');

    // order_items ───────────────────────────────────────────────────────────
    // References product_variants so we capture the exact colour/size ordered
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $orderItemsTable (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id          INTEGER NOT NULL,
        variant_id        INTEGER NOT NULL,
        quantity          INTEGER NOT NULL CHECK (quantity > 0),
        price_at_purchase REAL    NOT NULL,
        FOREIGN KEY (order_id)   REFERENCES $ordersTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY (variant_id) REFERENCES $productVariantsTable(id)
          ON DELETE RESTRICT ON UPDATE CASCADE
      )
    ''');

    // reviews ───────────────────────────────────────────────────────────────
    // order_id enforces "verified purchase" reviews
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $reviewsTable (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        user_id    INTEGER NOT NULL,
        order_id   INTEGER,
        rating     INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
        comment    TEXT,
        image_url  TEXT,
        created_at TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE (product_id, user_id, order_id),
        FOREIGN KEY (product_id) REFERENCES $productsTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY (user_id)    REFERENCES $usersTable(id)
          ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY (order_id)   REFERENCES $ordersTable(id)
          ON DELETE SET NULL ON UPDATE CASCADE
      )
    ''');

    // useful indexes
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category ON $productsTable(category_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_active ON $productsTable(is_active)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_variants_product ON $productVariantsTable(product_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_unique ON $productVariantsTable(product_id, color, size)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_favorites_user ON $favoritesTable(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_user ON $ordersTable(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reviews_product ON $reviewsTable(product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tags_tag ON $productTagsTable(tag)',
    );
  }

  // ── Seed data ────────────────────────────────────────────────────────────

  Future<void> _seedRoles(Database db) async {
    await db.insert(rolesTable, {
      'name': 'admin',
      'permissions': jsonEncode([
        'manage_products',
        'manage_orders',
        'manage_users',
        'manage_categories',
        'view_reports',
      ]),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(rolesTable, {
      'name': 'customer',
      'permissions': jsonEncode(['place_orders', 'write_reviews']),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Keep one deterministic user so legacy favorites/cart flows can work.
    await db.insert(usersTable, {
      'id': _legacyDefaultUserId,
      'role_id': 2,
      'full_name': 'Default User',
      'email': 'default.user@local.dev',
      'password_hash': 'local-default-user',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ── Migrations ───────────────────────────────────────────────────────────

  Future<void> _migrateToV3(Database db) async {
    // Reproduce legacy v3 migration so old installs can still reach v4
    final hasProducts = await _tableExists(db, 'products');
    final hasCatalog = await _tableExists(db, _legacyCatalogTable);

    if (hasProducts && !hasCatalog) {
      await db.execute('ALTER TABLE products RENAME TO $_legacyCatalogTable');
    } else if (!hasCatalog) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_legacyCatalogTable (
          id            TEXT PRIMARY KEY,
          name          TEXT NOT NULL,
          description   TEXT NOT NULL,
          imageUrl      TEXT NOT NULL,
          category      TEXT NOT NULL,
          price         REAL NOT NULL,
          isDiscounted  INTEGER NOT NULL,
          rating        REAL NOT NULL,
          gallery       TEXT NOT NULL,
          availableColors TEXT NOT NULL,
          availableSizes  TEXT NOT NULL
        )
      ''');
    }
  }

  Future<void> _migrateToV4(Database db) async {
    // 1. Create the full normalised schema
    await _createAllTables(db);
    await _seedRoles(db);

    // 2. Migrate legacy catalog_products → new products + variants + images
    final hasCatalog = await _tableExists(db, _legacyCatalogTable);
    if (hasCatalog) {
      final rows = await db.query(_legacyCatalogTable);
      for (final row in rows) {
        // Resolve or create category
        final categoryName = (row['category'] as String?) ?? 'Uncategorised';
        final catRows = await db.query(
          categoriesTable,
          where: 'name = ?',
          whereArgs: [categoryName],
          limit: 1,
        );
        final int categoryId;
        if (catRows.isNotEmpty) {
          categoryId = catRows.first['id'] as int;
        } else {
          categoryId = await db.insert(categoriesTable, {'name': categoryName});
        }

        // Insert product
        final productId = await db.insert(productsTable, {
          'category_id': categoryId,
          'name': row['name'],
          'description': row['description'],
          'base_price': row['price'],
          'thumbnail': row['imageUrl'],
          'is_discounted': row['isDiscounted'],
          'rating_avg': row['rating'],
        });

        // Migrate gallery → product_images
        final gallery = _decodeStringList(row['gallery'] as String?);
        for (var i = 0; i < gallery.length; i++) {
          await db.insert(productImagesTable, {
            'product_id': productId,
            'image_url': gallery[i],
            'sort_order': i,
          });
        }

        // Migrate availableColors × availableSizes → product_variants
        final colors = _decodeStringList(row['availableColors'] as String?);
        final sizes = _decodeStringList(row['availableSizes'] as String?);
        if (colors.isEmpty && sizes.isEmpty) {
          // Create one default variant so the product is always orderable
          await db.insert(productVariantsTable, {
            'product_id': productId,
            'stock': 0,
          });
        } else if (colors.isEmpty) {
          for (final size in sizes) {
            await db.insert(productVariantsTable, {
              'product_id': productId,
              'size': size,
              'stock': 0,
            });
          }
        } else if (sizes.isEmpty) {
          for (final color in colors) {
            await db.insert(productVariantsTable, {
              'product_id': productId,
              'color': color,
              'stock': 0,
            });
          }
        } else {
          for (final color in colors) {
            for (final size in sizes) {
              await db.insert(productVariantsTable, {
                'product_id': productId,
                'color': color,
                'size': size,
                'stock': 0,
              });
            }
          }
        }
      }

      // 3. Migrate legacy favorites (no user link — attach to a placeholder)
      final hasFavLegacy = await _tableExists(db, 'favorites');
      if (hasFavLegacy) {
        final fallbackUserId = await _ensureLegacyDefaultUser(db);
        final legacyFavs = await db.query('favorites');
        for (final fav in legacyFavs) {
          // Try to find the migrated product by thumbnail (imageUrl)
          final match = await db.query(
            productsTable,
            where: 'thumbnail = ?',
            whereArgs: [fav['imageUrl']],
            limit: 1,
          );
          if (match.isNotEmpty) {
            // Attach legacy favourites to a deterministic local user to keep FK valid.
            await db.insert(favoritesTable, {
              'user_id': fallbackUserId,
              'product_id': match.first['id'],
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }

      // 4. Drop legacy tables
      await db.execute('DROP TABLE IF EXISTS $_legacyCatalogTable');
      // Rename old favorites so the new one takes the canonical name
      // (already created above as part of _createAllTables)
    }
  }

  Future<void> _migrateToV5(Database db) async {
    final hasIsActive = await _columnExists(db, productsTable, 'is_active');
    if (!hasIsActive) {
      await db.execute(
        'ALTER TABLE $productsTable ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
      );
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_unique ON $productVariantsTable(product_id, color, size)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_active ON $productsTable(is_active)',
    );
  }

  // ── Helper ───────────────────────────────────────────────────────────────

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    for (final row in rows) {
      if (row['name'] == columnName) return true;
    }
    return false;
  }

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }

  int? _parseLegacyProductId(String rawId) {
    return int.tryParse(rawId.trim());
  }

  Future<int> _ensureLegacyDefaultUser(DatabaseExecutor db) async {
    final existing = await db.query(
      usersTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [_legacyDefaultUserId],
      limit: 1,
    );
    if (existing.isNotEmpty) return _legacyDefaultUserId;

    final customerRole = await db.query(
      rolesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: ['customer'],
      limit: 1,
    );
    final roleId = customerRole.isNotEmpty
        ? customerRole.first['id'] as int
        : 2;

    await db.insert(usersTable, {
      'id': _legacyDefaultUserId,
      'role_id': roleId,
      'full_name': 'Default User',
      'email': 'default.user@local.dev',
      'password_hash': 'local-default-user',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    return _legacyDefaultUserId;
  }

  Future<Product> _toLegacyProduct(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final productId = row['id'] as int;

    final imageRows = await db.query(
      productImagesTable,
      columns: ['image_url'],
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'sort_order ASC',
    );

    final variantRows = await db.query(
      productVariantsTable,
      columns: ['color', 'size'],
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    final gallery = imageRows
        .map((e) => e['image_url'])
        .whereType<String>()
        .toList(growable: false);
    final colors = variantRows
        .map((e) => e['color'])
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final sizes = variantRows
        .map((e) => e['size'])
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final thumbnail = (row['thumbnail'] as String?) ?? '';
    final fallbackImage = gallery.isNotEmpty ? gallery.first : '';

    return Product(
      id: productId.toString(),
      name: (row['name'] as String?) ?? 'San pham',
      description: (row['description'] as String?) ?? '',
      imageUrl: thumbnail.isNotEmpty ? thumbnail : fallbackImage,
      category: (row['category_name'] as String?) ?? 'Phu kien',
      price: ((row['base_price'] as num?) ?? 0).toDouble(),
      isDiscounted: (row['is_discounted'] as int? ?? 0) == 1,
      rating: ((row['rating_avg'] as num?) ?? 0).toDouble(),
      gallery: gallery,
      availableColors: colors,
      availableSizes: sizes,
    );
  }

  Future<void> _upsertLegacyProductInTx(Transaction tx, Product product) async {
    final parsedId = _parseLegacyProductId(product.id);

    final existingProduct = parsedId == null
        ? const <Map<String, Object?>>[]
        : await tx.query(
            productsTable,
            columns: ['is_active'],
            where: 'id = ?',
            whereArgs: [parsedId],
            limit: 1,
          );
    final isActive = existingProduct.isNotEmpty
        ? (existingProduct.first['is_active'] as int? ?? 1)
        : 1;

    final categoryRows = await tx.query(
      categoriesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [product.category],
      limit: 1,
    );
    final categoryId = categoryRows.isNotEmpty
        ? categoryRows.first['id'] as int
        : await tx.insert(categoriesTable, {'name': product.category});

    final productData = <String, Object?>{
      'category_id': categoryId,
      'name': product.name,
      'description': product.description,
      'base_price': product.price,
      'thumbnail': product.imageUrl,
      'is_discounted': product.isDiscounted ? 1 : 0,
      'is_active': isActive,
      'rating_avg': product.rating,
    };
    if (parsedId != null) {
      productData['id'] = parsedId;
    }

    final productId = await tx.insert(
      productsTable,
      productData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await tx.delete(
      productImagesTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    await tx.delete(
      productVariantsTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    final gallery = product.gallery.isNotEmpty
        ? product.gallery
        : (product.imageUrl.isEmpty ? const <String>[] : [product.imageUrl]);
    for (var i = 0; i < gallery.length; i++) {
      await tx.insert(productImagesTable, {
        'product_id': productId,
        'image_url': gallery[i],
        'sort_order': i,
      });
    }

    final colors = product.availableColors;
    final sizes = product.availableSizes;
    if (colors.isEmpty && sizes.isEmpty) {
      await tx.insert(productVariantsTable, {
        'product_id': productId,
        'stock': 0,
      });
    } else if (colors.isEmpty) {
      for (final size in sizes) {
        await tx.insert(productVariantsTable, {
          'product_id': productId,
          'size': size,
          'stock': 0,
        });
      }
    } else if (sizes.isEmpty) {
      for (final color in colors) {
        await tx.insert(productVariantsTable, {
          'product_id': productId,
          'color': color,
          'stock': 0,
        });
      }
    } else {
      for (final color in colors) {
        for (final size in sizes) {
          await tx.insert(productVariantsTable, {
            'product_id': productId,
            'color': color,
            'size': size,
            'stock': 0,
          });
        }
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  // ── Legacy compatibility API (old Product model) ────────────────────────

  Future<List<Product>> getCatalogProducts({bool onlyActive = false}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM $productsTable p
      JOIN $categoriesTable c ON c.id = p.category_id
      ${onlyActive ? 'WHERE p.is_active = 1' : ''}
      ORDER BY p.name ASC
    ''');

    final products = <Product>[];
    for (final row in rows) {
      products.add(await _toLegacyProduct(db, row));
    }
    return products;
  }

  Future<List<Product>> getActiveCatalogProducts() {
    return getCatalogProducts(onlyActive: true);
  }

  Future<void> replaceCatalogProducts(List<Product> products) async {
    final db = await database;
    await db.transaction((tx) async {
      for (final product in products) {
        await _upsertLegacyProductInTx(tx, product);
      }
    });
  }

  Future<void> updateCatalogProduct(Product updated) async {
    final db = await database;
    await db.transaction((tx) async {
      await _upsertLegacyProductInTx(tx, updated);
    });
  }

  Future<void> setProductActive(int productId, bool active) async {
    final db = await database;
    await db.update(
      productsTable,
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> deleteProduct(int productId) async {
    final db = await database;
    await db.delete(productsTable, where: 'id = ?', whereArgs: [productId]);
  }

  Future<List<Product>> getFavorites() async {
    final db = await database;
    final userId = await _ensureLegacyDefaultUser(db);
    final rows = await getFavoritesForUser(userId);
    final products = <Product>[];
    for (final row in rows) {
      products.add(await _toLegacyProduct(db, row));
    }
    return products;
  }

  Future<void> removeFavorite(String productId) async {
    final parsedId = _parseLegacyProductId(productId);
    if (parsedId == null) return;

    final db = await database;
    final userId = await _ensureLegacyDefaultUser(db);
    await db.delete(
      favoritesTable,
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [userId, parsedId],
    );
  }

  // ── Users ────────────────────────────────────────────────────────────────

  /// Returns the user row including role name & permissions.
  Future<Map<String, Object?>?> getUserWithRole(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT u.*, r.name AS role_name, r.permissions
      FROM $usersTable u
      JOIN $rolesTable r ON r.id = u.role_id
      WHERE u.id = ?
      LIMIT 1
    ''',
      [userId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> isAdmin(int userId) async {
    final user = await getUserWithRole(userId);
    return user?['role_name'] == 'admin';
  }

  Future<bool> hasPermission(int userId, String permission) async {
    final user = await getUserWithRole(userId);
    if (user == null) return false;

    final raw = user['permissions'];
    if (raw is! String || raw.isEmpty) return false;

    final decoded = jsonDecode(raw);
    if (decoded is! List) return false;

    return decoded.map((e) => e.toString()).contains(permission);
  }

  Future<Map<String, Object?>?> authenticateUser({
    required String email,
    required String passwordHash,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT u.*, r.name AS role_name, r.permissions
      FROM $usersTable u
      JOIN $rolesTable r ON r.id = u.role_id
      WHERE u.email = ? AND u.password_hash = ?
      LIMIT 1
    ''',
      [email.trim(), passwordHash],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> createUser({
    required String fullName,
    required String email,
    required String passwordHash,
    String? phone,
    String? address,
    String roleName = 'customer',
  }) async {
    final db = await database;
    final roleRows = await db.query(
      rolesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [roleName],
      limit: 1,
    );
    final roleId = roleRows.isNotEmpty ? roleRows.first['id'] as int : 2;

    return db.insert(usersTable, {
      'role_id': roleId,
      'full_name': fullName,
      'email': email.trim(),
      'password_hash': passwordHash,
      'phone': phone,
      'address': address,
    });
  }

  Future<void> setUserRole(int userId, String roleName) async {
    final db = await database;
    final roleRows = await db.query(
      rolesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [roleName],
      limit: 1,
    );
    if (roleRows.isEmpty) {
      throw Exception('Role "$roleName" not found');
    }

    await db.update(
      usersTable,
      {'role_id': roleRows.first['id']},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, Object?>>> getAllUsersWithRole() async {
    final db = await database;
    return db.rawQuery('''
      SELECT u.*, r.name AS role_name, r.permissions
      FROM $usersTable u
      JOIN $rolesTable r ON r.id = u.role_id
      ORDER BY u.created_at DESC
    ''');
  }

  // ── Favorites ────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> getFavoritesForUser(int userId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT p.*, f.added_at
      FROM $favoritesTable f
      JOIN $productsTable p ON p.id = f.product_id
      WHERE f.user_id = ?
      ORDER BY f.added_at DESC
    ''',
      [userId],
    );
  }

  Future<bool> isFavorite(int userId, int productId) async {
    final db = await database;
    final rows = await db.query(
      favoritesTable,
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [userId, productId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> toggleFavorite(int userId, int productId) async {
    final db = await database;
    final exists = await isFavorite(userId, productId);
    if (exists) {
      await db.delete(
        favoritesTable,
        where: 'user_id = ? AND product_id = ?',
        whereArgs: [userId, productId],
      );
    } else {
      await db.insert(favoritesTable, {
        'user_id': userId,
        'product_id': productId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> clearFavoritesForUser(int userId) async {
    final db = await database;
    await db.delete(favoritesTable, where: 'user_id = ?', whereArgs: [userId]);
  }

  // ── Products ─────────────────────────────────────────────────────────────

  /// Full product detail: base info + variants + images.
  Future<Map<String, Object?>?> getProduct(int productId) async {
    final db = await database;

    final productRows = await db.query(
      productsTable,
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (productRows.isEmpty) return null;

    final variants = await db.query(
      productVariantsTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    final images = await db.query(
      productImagesTable,
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'sort_order ASC',
    );

    return {...productRows.first, 'variants': variants, 'images': images};
  }

  Future<List<Map<String, Object?>>> getProductsByCategory(
    int categoryId,
  ) async {
    final db = await database;
    return db.query(
      productsTable,
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'name ASC',
    );
  }

  /// Related products: share at least one tag, exclude current product.
  Future<List<Map<String, Object?>>> getRelatedProducts(
    int productId, {
    int limit = 10,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT p.*, COUNT(t2.tag) AS shared_tags
      FROM $productTagsTable t1
      JOIN $productTagsTable t2 ON t2.tag = t1.tag AND t2.product_id != t1.product_id
      JOIN $productsTable p ON p.id = t2.product_id
      WHERE t1.product_id = ?
      GROUP BY p.id
      ORDER BY shared_tags DESC
      LIMIT ?
    ''',
      [productId, limit],
    );
  }

  Future<int> insertProduct(Map<String, Object?> data) async {
    final db = await database;
    return db.insert(productsTable, data);
  }

  Future<void> updateProduct(int productId, Map<String, Object?> data) async {
    final db = await database;
    await db.update(
      productsTable,
      data,
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  // ── Product variants ─────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> getVariantsForProduct(
    int productId,
  ) async {
    final db = await database;
    return db.query(
      productVariantsTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> updateVariantStock(int variantId, int newStock) async {
    final db = await database;
    await db.update(
      productVariantsTable,
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [variantId],
    );
  }

  // ── Orders ───────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> getOrdersForUser(int userId) async {
    final db = await database;
    return db.query(
      ordersTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'order_date DESC',
    );
  }

  /// Places an order and decrements stock atomically.
  Future<int> placeOrder({
    required int userId,
    required String shippingAddress,
    required String paymentMethod,
    required List<({int variantId, int quantity, double price})> items,
  }) async {
    final db = await database;
    return db.transaction((tx) async {
      // Validate stock first
      for (final item in items) {
        final row = await tx.query(
          productVariantsTable,
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item.variantId],
          limit: 1,
        );
        if (row.isEmpty) throw Exception('Variant ${item.variantId} not found');
        final stock = row.first['stock'] as int;
        if (stock < item.quantity) {
          throw Exception(
            'Insufficient stock for variant ${item.variantId}: '
            'requested ${item.quantity}, available $stock',
          );
        }
      }

      final total = items.fold<double>(
        0,
        (sum, i) => sum + i.price * i.quantity,
      );

      final orderId = await tx.insert(ordersTable, {
        'user_id': userId,
        'total_amount': total,
        'shipping_address': shippingAddress,
        'payment_method': paymentMethod,
      });

      for (final item in items) {
        await tx.insert(orderItemsTable, {
          'order_id': orderId,
          'variant_id': item.variantId,
          'quantity': item.quantity,
          'price_at_purchase': item.price,
        });
        await tx.rawUpdate(
          '''
          UPDATE $productVariantsTable
          SET stock = stock - ?
          WHERE id = ?
        ''',
          [item.quantity, item.variantId],
        );
      }

      return orderId;
    });
  }

  Future<void> updateOrderStatus(int orderId, String status) async {
    final db = await database;
    await db.transaction((tx) async {
      final orderRows = await tx.query(
        ordersTable,
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) return;

      final oldStatus = orderRows.first['status'] as String?;

      await tx.update(
        ordersTable,
        {'status': status},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // Keep stock consistent when an order transitions to cancelled.
      if (status == 'cancelled' && oldStatus != 'cancelled') {
        final items = await tx.query(
          orderItemsTable,
          columns: ['variant_id', 'quantity'],
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        for (final item in items) {
          await tx.rawUpdate(
            '''
            UPDATE $productVariantsTable
            SET stock = stock + ?
            WHERE id = ?
          ''',
            [item['quantity'], item['variant_id']],
          );
        }
      }
    });
  }

  Future<void> updatePaymentStatus(int orderId, String paymentStatus) async {
    final db = await database;
    await db.update(
      ordersTable,
      {'payment_status': paymentStatus},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  // ── Reviews ──────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> getReviewsForProduct(int productId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT r.*, u.full_name
      FROM $reviewsTable r
      JOIN $usersTable u ON u.id = r.user_id
      WHERE r.product_id = ?
      ORDER BY r.created_at DESC
    ''',
      [productId],
    );
  }

  /// Inserts a review and updates the product's denormalised rating.
  Future<void> addReview({
    required int productId,
    required int userId,
    int? orderId,
    required int rating,
    String? comment,
    String? imageUrl,
  }) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.insert(reviewsTable, {
        'product_id': productId,
        'user_id': userId,
        'order_id': orderId,
        'rating': rating,
        'comment': comment,
        'image_url': imageUrl,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Recompute aggregates in the products row
      await tx.rawUpdate(
        '''
        UPDATE $productsTable
        SET
          rating_avg   = (SELECT AVG(rating)   FROM $reviewsTable WHERE product_id = ?),
          rating_count = (SELECT COUNT(*)       FROM $reviewsTable WHERE product_id = ?)
        WHERE id = ?
      ''',
        [productId, productId, productId],
      );
    });
  }
}
