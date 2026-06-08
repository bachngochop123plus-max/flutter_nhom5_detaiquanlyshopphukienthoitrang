import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/product.dart';

class InsufficientStockException implements Exception {
  const InsufficientStockException({
    required this.variantId,
    required this.available,
    required this.requested,
  });

  final int variantId;
  final int available;
  final int requested;

  @override
  String toString() =>
      'Sản phẩm (variant #$variantId) chỉ còn $available trong kho, '
      'nhưng bạn đặt $requested.';
}

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'fashion_shop.db';
  static const _databaseVersion = 9;
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
  static const cartItemsTable = 'cart_items';

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
        await _seedDemoData(db);
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

        // v5→v6: add v_product_detail view for unified variant and gallery fetching
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
        // v6→v7: seed full demo data and add cart_items table
        if (oldVersion < 7) {
          await _seedDemoData(db);
          await _migrateToV7(db);
        }
        // v7→v8: rebuild cart_items with user_id for per-account partitioning
        if (oldVersion < 8) {
          await _migrateToV8(db);
        }
        // v8→v9: add img_user TEXT column to users table
        if (oldVersion < 9) {
          try {
            await db.execute('ALTER TABLE users ADD COLUMN img_user TEXT');
          } catch (e) {
            debugPrint('[DatabaseHelper] Migration to v9 error (img_user might already exist): $e');
          }
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
        bank_info     TEXT,
        img_user      TEXT,
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

    // Create view v_product_detail (safe version without JSON functions)
    await db.execute('DROP VIEW IF EXISTS v_product_detail');
    await db.execute('''
      CREATE VIEW v_product_detail AS
      SELECT 
        p.*,
        c.name AS category_name
      FROM products p
      JOIN categories c ON c.id = p.category_id
    ''');

    // cart_items ────────────────────────────────────────────────────────────
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $cartItemsTable (
        id         TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity   INTEGER NOT NULL,
        color      TEXT,
        size       TEXT,
        user_id    TEXT NOT NULL DEFAULT 'guest'
      )
    ''');
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

  // ── Demo seed data ───────────────────────────────────────────────────────
  // Seed dữ liệu mẫu đầy đủ: categories, products, variants, tags, product_images
  // product_images được phân riêng từng sản phẩm → gallery sidebar đúng logic

  Future<void> _seedDemoData(Database db) async {
    // 1. CATEGORIES
    final catIds = <String, int>{};
    for (final cat in [
      {'name': 'Túi Xách Thời Trang', 'image_url': ''},
      {'name': 'Kính Mắt Gentry', 'image_url': ''},
      {'name': 'Đồng Hồ Cao Cấp', 'image_url': ''},
      {'name': 'Trang Sức Quý Phái', 'image_url': ''},
      {'name': 'Mũ & Nón Thời Trang', 'image_url': ''},
    ]) {
      final existing = await db.query(categoriesTable,
          columns: ['id'], where: 'name = ?', whereArgs: [cat['name']], limit: 1);
      if (existing.isNotEmpty) {
        catIds[cat['name']!] = existing.first['id'] as int;
      } else {
        catIds[cat['name']!] = await db.insert(categoriesTable, cat,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // 2. PRODUCTS — thumbnail là ảnh chính hiển thị trong danh sách
    // product_images sẽ là các ảnh gallery phụ cho từng sản phẩm
    final products = [
      // Túi Xách
      {'cat': 'Túi Xách Thời Trang', 'name': 'Túi Xách Da Vân Cá Sấu Đen',
        'desc': 'Thiết kế sang trọng quai bện thừng thủ công.', 'price': 450000.0,
        'thumb': 'Img_Product/Img_04.webp', 'discount': 1,
        'images': ['Img_Product/tui_xach_1.webp', 'Img_Product/tui_xach_2.webp', 'Img_Product/tui_xach_3.webp']},
      {'cat': 'Túi Xách Thời Trang', 'name': 'Túi Hộp Nữ Họa Tiết Gấu',
        'desc': 'Chất liệu da PU dập họa tiết chìm trẻ trung.', 'price': 385000.0,
        'thumb': 'Img_Product/Img05.webp', 'discount': 0,
        'images': ['Img_Product/tui_xach_4.webp', 'Img_Product/tui_xach_5.webp', 'Img_Product/tui_xach_6.webp']},
      {'cat': 'Túi Xách Thời Trang', 'name': 'Túi Tote Đỏ Đô Khóa Vàng',
        'desc': 'Form rộng thanh lịch, phù hợp cho công sở.', 'price': 520000.0,
        'thumb': 'Img_Product/Img06.webp', 'discount': 0,
        'images': ['Img_Product/tui_xach_7.webp', 'Img_Product/tui_xach_8.webp', 'Img_Product/tui_xach_9.webp']},
      // Kính Mắt
      {'cat': 'Kính Mắt Gentry', 'name': 'Kính Mát Chữ Nhật Retro',
        'desc': 'Gọng nhựa dày phong cách unisex cổ điển.', 'price': 120000.0,
        'thumb': 'Img_Product/Img01.webp', 'discount': 1,
        'images': ['Img_Product/kinh_1.webp', 'Img_Product/kinh_2.webp', 'Img_Product/kinh_3.webp']},
      {'cat': 'Kính Mắt Gentry', 'name': 'Kính Gọng Kim Loại Vuông',
        'desc': 'Gọng mảnh mạ vàng cao cấp.', 'price': 195000.0,
        'thumb': 'Img_Product/Img02.webp', 'discount': 0,
        'images': ['Img_Product/kinh_4.webp', 'Img_Product/kinh_5.webp', 'Img_Product/kinh_6.webp']},
      {'cat': 'Kính Mắt Gentry', 'name': 'Kính Mát Nữ Oversize Aviator',
        'desc': 'Thiết kế bảo vệ toàn diện.', 'price': 150000.0,
        'thumb': 'Img_Product/Img03.webp', 'discount': 0,
        'images': ['Img_Product/kinh_7.webp', 'Img_Product/kinh_8.webp', 'Img_Product/kinh_9.webp']},
      // Đồng Hồ
      {'cat': 'Đồng Hồ Cao Cấp', 'name': 'Đồng Hồ Nam LIGE Mặt Đen',
        'desc': 'Dây thép không gỉ.', 'price': 890000.0,
        'thumb': 'Img_Product/Img07.webp', 'discount': 1,
        'images': ['Img_Product/dong_ho_1.webp', 'Img_Product/dong_ho_2.webp', 'Img_Product/dong_ho_3.webp']},
      {'cat': 'Đồng Hồ Cao Cấp', 'name': 'Đồng Hồ Vàng Luxury Full Gold',
        'desc': 'Mạ vàng PVD cao cấp.', 'price': 1250000.0,
        'thumb': 'Img_Product/Img08.webp', 'discount': 0,
        'images': ['Img_Product/dong_ho_4.webp', 'Img_Product/dong_ho_5.webp', 'Img_Product/dong_ho_6.webp', 'Img_Product/dong_ho_7.webp']},
      {'cat': 'Đồng Hồ Cao Cấp', 'name': 'Đồng Hồ Nữ Dây Da Classic',
        'desc': 'Thiết kế tối giản.', 'price': 420000.0,
        'thumb': 'Img_Product/Img09.webp', 'discount': 0,
        'images': ['Img_Product/dong_ho_8.webp', 'Img_Product/dong_ho_9.webp', 'Img_Product/dong_ho_10.webp']},
      // Trang Sức — Dây Chuyền
      {'cat': 'Trang Sức Quý Phái', 'name': 'Vòng Cổ Kim Cương Đa Tầng',
        'desc': 'Trang sức dự tiệc.', 'price': 2500000.0,
        'thumb': 'Img_Product/Img10.webp', 'discount': 0,
        'images': ['Img_Product/day_chuyen_1.webp', 'Img_Product/day_chuyen_2.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Dây Chuyền Mặt Đá Khối Tròn',
        'desc': 'Thiết kế xoáy.', 'price': 280000.0,
        'thumb': 'Img_Product/Img11.webp', 'discount': 1,
        'images': ['Img_Product/day_chuyen_3.webp', 'Img_Product/day_chuyen_4.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Bộ Vòng Cổ Layer Coin',
        'desc': 'Phong cách Boho.', 'price': 350000.0,
        'thumb': 'Img_Product/Img12.webp', 'discount': 0,
        'images': ['Img_Product/day_chuyen_5.webp', 'Img_Product/day_chuyen_6.webp']},
      // Trang Sức — Bông Tai
      {'cat': 'Trang Sức Quý Phái', 'name': 'Bông Tai Bạc Ý Nút Thắt',
        'desc': 'Đính đá cao cấp.', 'price': 150000.0,
        'thumb': 'Img_Product/Img13.webp', 'discount': 1,
        'images': ['Img_Product/khuyen_tai_1.webp', 'Img_Product/khuyen_tai_2.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Set Bông Tai Tuyết & Ngọc Trai',
        'desc': 'Bộ sưu tập.', 'price': 220000.0,
        'thumb': 'Img_Product/Img14.webp', 'discount': 0,
        'images': ['Img_Product/khuyen_tai_3.webp', 'Img_Product/khuyen_tai_4.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Bông Tai Bạc Chữ U Modern',
        'desc': 'Hiện đại.', 'price': 180000.0,
        'thumb': 'Img_Product/Img15.webp', 'discount': 0,
        'images': ['Img_Product/khuyen_tai_5.webp']},
      // Trang Sức — Nhẫn
      {'cat': 'Trang Sức Quý Phái', 'name': 'Nhẫn Đôi Bạc Everlasting',
        'desc': 'Thiết kế hở.', 'price': 450000.0,
        'thumb': 'Img_Product/Img16.webp', 'discount': 1,
        'images': ['Img_Product/nhan_1.webp', 'Img_Product/nhan_2.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Nhẫn Cặp Bạc Hiểu Minh',
        'desc': 'Bạc 925.', 'price': 480000.0,
        'thumb': 'Img_Product/Img17.webp', 'discount': 0,
        'images': ['Img_Product/nhan_3.webp']},
      {'cat': 'Trang Sức Quý Phái', 'name': 'Nhẫn Cặp GIX Vàng Hồng',
        'desc': 'Đính đá.', 'price': 1200000.0,
        'thumb': 'Img_Product/Img18.webp', 'discount': 0,
        'images': ['Img_Product/nhan_4.webp']},
      // Mũ & Nón
      {'cat': 'Mũ & Nón Thời Trang', 'name': 'Mũ Ca-pô Thủy Thủ Beret',
        'desc': 'Vải nỉ cao cấp.', 'price': 195000.0,
        'thumb': 'Img_Product/Img19.webp', 'discount': 0,
        'images': ['Img_Product/mu_1.webp', 'Img_Product/mu_2.webp', 'Img_Product/mu_3.webp']},
      {'cat': 'Mũ & Nón Thời Trang', 'name': 'Mũ Bucket Denim GC',
        'desc': 'Streetwear.', 'price': 250000.0,
        'thumb': 'Img_Product/Img20.webp', 'discount': 1,
        'images': ['Img_Product/mu_4.webp', 'Img_Product/mu_5.webp']},
    ];

    for (final p in products) {
      final catId = catIds[p['cat'] as String] ?? 0;
      if (catId == 0) continue;

      // Kiểm tra đã tồn tại chưa (tránh seed lại khi upgrade)
      final exists = await db.query(productsTable,
          columns: ['id'], where: 'thumbnail = ?',
          whereArgs: [p['thumb']], limit: 1);
      if (exists.isNotEmpty) continue;

      final productId = await db.insert(productsTable, {
        'category_id': catId,
        'name': p['name'],
        'description': p['desc'],
        'base_price': p['price'],
        'thumbnail': p['thumb'],
        'is_discounted': p['discount'],
        'is_active': 1,
        'rating_avg': 0.0,
        'rating_count': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      if (productId <= 0) continue;

      // Seed product_images riêng cho từng sản phẩm (tự động sinh đủ ô gallery)
      final images = p['images'] as List<String>;
      for (var i = 0; i < images.length; i++) {
        await db.insert(productImagesTable, {
          'product_id': productId,
          'image_url': images[i],
          'sort_order': i + 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // 3. VARIANTS
    final variantSeeds = [
      {'thumb': 'Img_Product/Img18.webp', 'color': 'Vàng Hồng', 'size': 'Nam (Size 18)', 'stock': 15, 'delta': 0.0},
      {'thumb': 'Img_Product/Img18.webp', 'color': 'Vàng Hồng', 'size': 'Nữ (Size 15)', 'stock': 15, 'delta': 0.0},
      {'thumb': 'Img_Product/Img01.webp', 'color': 'Đen',     'size': 'Free size',    'stock': 50, 'delta': 0.0},
      {'thumb': 'Img_Product/Img01.webp', 'color': 'Nâu Trà', 'size': 'Free size',    'stock': 35, 'delta': 0.0},
      {'thumb': 'Img_Product/Img_04.webp', 'color': 'Đen',   'size': 'Size M',        'stock': 20, 'delta': 0.0},
      {'thumb': 'Img_Product/Img_04.webp', 'color': 'Đen',   'size': 'Size L',        'stock': 10, 'delta': 70000.0},
    ];
    for (final v in variantSeeds) {
      final pRows = await db.query(productsTable,
          columns: ['id'], where: 'thumbnail = ?', whereArgs: [v['thumb']], limit: 1);
      if (pRows.isEmpty) continue;
      final pid = pRows.first['id'] as int;
      await db.insert(productVariantsTable, {
        'product_id': pid,
        'color': v['color'],
        'size': v['size'],
        'stock': v['stock'],
        'price_delta': v['delta'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 4. TAGS
    final tagSeeds = [
      {'thumb': 'Img_Product/Img16.webp', 'tag': 'Couple'},
      {'thumb': 'Img_Product/Img17.webp', 'tag': 'Couple'},
      {'thumb': 'Img_Product/Img18.webp', 'tag': 'Couple'},
      {'thumb': 'Img_Product/Img10.webp', 'tag': 'Luxury'},
      {'thumb': 'Img_Product/Img08.webp', 'tag': 'Luxury'},
      {'thumb': 'Img_Product/Img19.webp', 'tag': 'Streetwear'},
      {'thumb': 'Img_Product/Img20.webp', 'tag': 'Streetwear'},
    ];
    for (final t in tagSeeds) {
      final pRows = await db.query(productsTable,
          columns: ['id'], where: 'thumbnail = ?', whereArgs: [t['thumb']], limit: 1);
      if (pRows.isEmpty) continue;
      final pid = pRows.first['id'] as int;
      await db.insert(productTagsTable, {
        'product_id': pid,
        'tag': t['tag'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }



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

  Future<void> _migrateToV6(Database db) async {

    await db.execute('DROP VIEW IF EXISTS v_product_detail');
    await db.execute('''
      CREATE VIEW v_product_detail AS
      SELECT 
        p.*,
        c.name AS category_name
      FROM products p
      JOIN categories c ON c.id = p.category_id
    ''');
  }

  Future<void> _migrateToV7(Database db) async {
    // Original migration: create cart_items without user_id
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart_items (
        id         TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity   INTEGER NOT NULL,
        color      TEXT,
        size       TEXT
      )
    ''');
  }

  Future<void> _migrateToV8(Database db) async {
    // Rebuild cart_items with user_id column for per-account partitioning
    await db.execute('DROP TABLE IF EXISTS cart_items');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart_items (
        id         TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity   INTEGER NOT NULL,
        color      TEXT,
        size       TEXT,
        user_id    TEXT NOT NULL DEFAULT 'guest'
      )
    ''');
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
      columns: ['color', 'size', 'stock', 'price_delta'],
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    final gallery = imageRows
        .map((e) => (e['image_url'] as String? ?? '').trim())
        .where((url) =>
            url.isNotEmpty &&
            url != 'null' &&
            url != 'undefined' &&
            !url.toLowerCase().contains('placeholder') &&
            !url.endsWith('/null') &&
            !url.endsWith('/undefined'))
        .toSet()
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

    final sqliteVariants = variantRows.map((v) => {
      'color': v['color'],
      'size': v['size'],
      'stock': v['stock'] as int? ?? 0,
      'price_delta': (v['price_delta'] as num? ?? 0.0).toDouble(),
    }).toList();

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
      variants: sqliteVariants,
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

    // Ưu tiên dùng variants data nếu có (khi đồng bộ từ Supabase/remote),
    // fallback về availableColors × availableSizes khi tạo từ local legacy data.
    if (product.variants.isNotEmpty) {
      for (final variant in product.variants) {
        await tx.insert(productVariantsTable, {
          'product_id': productId,
          'color': variant['color'],
          'size': variant['size'],
          'stock': variant['stock'] ?? 0,
          'price_delta': variant['price_delta'] ?? 0.0,
        });
      }
    } else {
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
      final syncedIds = <int>[];
      for (final product in products) {
        await _upsertLegacyProductInTx(tx, product);
        final id = _parseLegacyProductId(product.id);
        if (id != null) {
          syncedIds.add(id);
        }
      }
      if (syncedIds.isNotEmpty) {
        final idPlaceholders = List.filled(syncedIds.length, '?').join(',');
        await tx.delete(
          productsTable,
          where: 'id NOT IN ($idPlaceholders)',
          whereArgs: syncedIds,
        );
      } else {
        await tx.delete(productsTable);
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

  Future<List<Product>> getFavorites(String userId) async {
    final db = await database;
    final rows = await getFavoritesForUser(userId);
    final products = <Product>[];
    for (final row in rows) {
      final productId = (row['product_id'] ?? row['id']) as int;
      final productRows = await db.rawQuery('''
        SELECT p.*, c.name AS category_name
        FROM $productsTable p
        JOIN $categoriesTable c ON c.id = p.category_id
        WHERE p.id = ?
        LIMIT 1
      ''', [productId]);
      if (productRows.isNotEmpty) {
        products.add(await _toLegacyProduct(db, productRows.first));
      }
    }
    return products;
  }

  Future<void> removeFavorite(String userId, String productId) async {
    final parsedId = _parseLegacyProductId(productId);
    if (parsedId == null) return;

    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        await client
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('product_id', parsedId);
      } catch (e) {
        debugPrint('[removeFavorite] Supabase error: $e');
      }
    }

    final db = await database;
    final localUserId = int.tryParse(userId) ?? 1;
    await db.delete(
      favoritesTable,
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [localUserId, parsedId],
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

  Future<List<Map<String, Object?>>> getFavoritesForUser(String userId) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        final rows = await client
            .from('v_user_favorites')
            .select()
            .eq('user_id', userId)
            as List<dynamic>;
        return rows.map((e) => Map<String, Object?>.from(e as Map)).toList();
      } catch (e) {
        debugPrint('[getFavoritesForUser] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final localUserId = int.tryParse(userId) ?? 1;
    final db = await database;
    return db.rawQuery(
      '''
      SELECT p.*, f.added_at
      FROM $favoritesTable f
      JOIN $productsTable p ON p.id = f.product_id
      WHERE f.user_id = ?
      ORDER BY f.added_at DESC
    ''',
      [localUserId],
    );
  }

  Future<bool> isFavorite(String userId, int productId) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        final rows = await client
            .from('favorites')
            .select()
            .eq('user_id', userId)
            .eq('product_id', productId);
        return (rows as List).isNotEmpty;
      } catch (e) {
        debugPrint('[isFavorite] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final localUserId = int.tryParse(userId) ?? 1;
    final db = await database;
    final rows = await db.query(
      favoritesTable,
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [localUserId, productId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite(String userId, int productId) async {
    final exists = await isFavorite(userId, productId);
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        if (exists) {
          await client
              .from('favorites')
              .delete()
              .eq('user_id', userId)
              .eq('product_id', productId);
          try {
            final localUserId = int.tryParse(userId) ?? 1;
            final db = await database;
            await db.delete(
              favoritesTable,
              where: 'user_id = ? AND product_id = ?',
              whereArgs: [localUserId, productId],
            );
          } catch (_) {}
          return false;
        } else {
          await client.from('favorites').insert({
            'user_id': userId,
            'product_id': productId,
          });
          try {
            final localUserId = int.tryParse(userId) ?? 1;
            final db = await database;
            await db.insert(favoritesTable, {
              'user_id': localUserId,
              'product_id': productId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {}
          return true;
        }
      } catch (e) {
        debugPrint('[toggleFavorite] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final localUserId = int.tryParse(userId) ?? 1;
    final db = await database;
    if (exists) {
      await db.delete(
        favoritesTable,
        where: 'user_id = ? AND product_id = ?',
        whereArgs: [localUserId, productId],
      );
      return false;
    } else {
      await db.insert(favoritesTable, {
        'user_id': localUserId,
        'product_id': productId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    }
  }

  Future<void> clearFavoritesForUser(dynamic userId) async {
    final db = await database;
    final localUserId = (userId is int) ? userId : (int.tryParse(userId.toString()) ?? 1);
    await db.delete(favoritesTable, where: 'user_id = ?', whereArgs: [localUserId]);
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

  Future<Map<String, Object?>?> getProductDetailFromView(int productId) async {
    final db = await database;
    final rows = await db.query(
      'v_product_detail',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final productDetail = Map<String, Object?>.from(rows.first);

    // Tải các biến thể của sản phẩm thủ công
    final variants = await db.query(
      productVariantsTable,
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    // Tải bộ sưu tập hình ảnh phụ thủ công
    final images = await db.query(
      productImagesTable,
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'sort_order ASC',
    );

    // Chuẩn hóa và map dữ liệu giống PostgreSQL để trả về JSON String
    final mappedVariants = variants.map((v) => {
      'id': v['id'],
      'color': v['color'],
      'size': v['size'],
      'stock': v['stock'],
      'price_delta': v['price_delta'],
    }).toList();

    final mappedImages = images.map((i) => {
      'id': i['id'],
      'image_url': i['image_url'],
      'sort_order': i['sort_order'],
    }).toList();

    productDetail['variants'] = jsonEncode(mappedVariants);
    productDetail['gallery'] = jsonEncode(mappedImages);

    return productDetail;
  }

  Future<List<Map<String, Object?>>> getRelatedProductsWithFallback(
    int productId,
    int categoryId, {
    int limit = 10,
  }) async {
    final db = await database;
    // 1. Thử tìm theo tags trước
    final tagged = await getRelatedProducts(productId, limit: limit);
    if (tagged.isNotEmpty) return tagged;

    // 2. Cùng danh mục — JOIN categories để có category_name cho _toLegacyProduct
    final sameCategory = await db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM $productsTable p
      JOIN $categoriesTable c ON c.id = p.category_id
      WHERE p.category_id = ? AND p.id != ? AND p.is_active = 1
      LIMIT ?
    ''', [categoryId, productId, limit]);
    if (sameCategory.isNotEmpty) return sameCategory;

    // 3. Fallback: tất cả sản phẩm active khác — JOIN để đầy đủ category_name
    return db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM $productsTable p
      JOIN $categoriesTable c ON c.id = p.category_id
      WHERE p.id != ? AND p.is_active = 1
      LIMIT ?
    ''', [productId, limit]);
  }

  Future<List<Product>> getRelatedProductsForDetail(
    int productId,
    String categoryName, {
    int limit = 10,
  }) async {
    final db = await database;

    // Resolve category id by name
    final catRows = await db.query(
      categoriesTable,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [categoryName],
      limit: 1,
    );
    final categoryId = catRows.isNotEmpty ? (catRows.first['id'] as int) : 0;

    final rows = await getRelatedProductsWithFallback(productId, categoryId, limit: limit);
    final list = <Product>[];
    for (final row in rows) {
      list.add(await _toLegacyProduct(db, row));
    }
    return list;
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

  Future<List<Map<String, Object?>>> getOrdersForUser(String userId) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        final rows = await client
            .from('orders')
            .select()
            .eq('user_id', userId)
            .order('order_date', ascending: false)
            as List<dynamic>;
        return rows.map((e) => Map<String, Object?>.from(e as Map)).toList();
      } catch (e) {
        debugPrint('[getOrdersForUser] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final localUserId = int.tryParse(userId) ?? 1;
    final db = await database;
    return db.query(
      ordersTable,
      where: 'user_id = ?',
      whereArgs: [localUserId],
      orderBy: 'order_date DESC',
    );
  }

  // ── Admin order queries ────────────────────────────────────────────────────

  /// All orders for admin, optionally filtered by date range (inclusive).
  /// Joins [usersTable] for customer name and email.
  Future<List<Map<String, Object?>>> getAdminOrders({
    DateTime? from,
    DateTime? to,
  }) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        var query = client.from('orders').select('*, profiles(full_name, email)');
        if (from != null) {
          query = query.gte('order_date', from.toIso8601String());
        }
        if (to != null) {
          query = query.lte('order_date', to.toIso8601String());
        }
        final rows = await query.order('order_date', ascending: false) as List<dynamic>;

        return rows.map((row) {
          final map = Map<String, Object?>.from(row as Map);
          final profile = map['profiles'] != null ? Map<String, dynamic>.from(map['profiles'] as Map) : null;
          return {
            ...map,
            'customer_name': profile?['full_name'] ?? 'Khách hàng',
            'customer_email': profile?['email'] ?? '',
          };
        }).toList();
      } catch (e) {
        debugPrint('[getAdminOrders] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final db = await database;

    final conditions = <String>[];
    final args = <Object>[];

    if (from != null) {
      conditions.add('o.order_date >= ?');
      args.add(
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')} 00:00:00',
      );
    }
    if (to != null) {
      conditions.add('o.order_date <= ?');
      args.add(
        '${to.year.toString().padLeft(4, '0')}-'
        '${to.month.toString().padLeft(2, '0')}-'
        '${to.day.toString().padLeft(2, '0')} 23:59:59',
      );
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        o.*,
        u.full_name AS customer_name,
        u.email     AS customer_email
      FROM $ordersTable o
      LEFT JOIN $usersTable u ON u.id = o.user_id
      $where
      ORDER BY o.order_date DESC
      ''', args);
  }

  /// Full order detail including items, product name, color, size, thumbnail.
  Future<Map<String, Object?>?> getOrderWithItems(int orderId) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        
        // 1. Fetch Order without joining profiles to avoid relationship schema errors
        final orderRow = await client
            .from('orders')
            .select()
            .eq('id', orderId)
            .maybeSingle();
            
        if (orderRow == null) return null;

        final orderMap = Map<String, Object?>.from(orderRow as Map);
        
        // 2. Safely fetch profile if needed
        Map<String, dynamic>? profile;
        try {
          if (orderMap['user_id'] != null) {
            final profileRow = await client
                .from('profiles')
                .select()
                .eq('id', orderMap['user_id']!)
                .maybeSingle();
            if (profileRow != null) {
              profile = Map<String, dynamic>.from(profileRow as Map);
            }
          }
        } catch (_) {
          // Ignore profile fetch error
        }

        List<dynamic> itemRows = [];
        try {
          itemRows = await client
              .from('order_items')
              .select('*, product_variants(*, products(*))')
              .eq('order_id', orderId)
              as List<dynamic>;
        } catch (_) {
          // If deep join fails, fetch just items
          itemRows = await client
              .from('order_items')
              .select()
              .eq('order_id', orderId)
              as List<dynamic>;
        }

        final mappedItems = [];
        for (final rawItem in itemRows) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          Map<String, dynamic>? variant;
          Map<String, dynamic>? product;

          if (item['product_variants'] != null) {
            variant = Map<String, dynamic>.from(item['product_variants'] as Map);
            if (variant['products'] != null) {
              product = Map<String, dynamic>.from(variant['products'] as Map);
            }
          } else {
            // Fallback: fetch variant and product manually if deep join failed
            try {
              final vRow = await client.from('product_variants').select().eq('id', item['variant_id']!).maybeSingle();
              if (vRow != null) {
                variant = Map<String, dynamic>.from(vRow as Map);
                final pRow = await client.from('products').select().eq('id', variant['product_id']!).maybeSingle();
                if (pRow != null) {
                  product = Map<String, dynamic>.from(pRow as Map);
                }
              }
            } catch (_) {}
          }

          mappedItems.add({
            'id': item['id'],
            'order_id': item['order_id'],
            'variant_id': item['variant_id'],
            'quantity': item['quantity'],
            'price_at_purchase': item['price_at_purchase'],
            'color': variant?['color'],
            'size': variant?['size'],
            'product_name': product?['name'],
            'thumbnail': product?['thumbnail'],
          });
        }

        return {
          ...orderMap,
          'customer_name': profile?['full_name'],
          'customer_email': profile?['email'],
          'customer_phone': profile?['phone'],
          'customer_address': profile?['address'],
          'order_items': mappedItems,
        };
      } catch (e) {
        debugPrint('[getOrderWithItems] Supabase error: $e. Falling back to SQLite.');
      }
    }

    final db = await database;

    final orderRows = await db.rawQuery(
      '''
      SELECT
        o.*,
        u.full_name AS customer_name,
        u.email     AS customer_email,
        u.phone     AS customer_phone,
        u.address   AS customer_address
      FROM $ordersTable o
      LEFT JOIN $usersTable u ON u.id = o.user_id
      WHERE o.id = ?
      LIMIT 1
      ''',
      [orderId],
    );
    if (orderRows.isEmpty) return null;

    final itemRows = await db.rawQuery(
      '''
      SELECT
        oi.*,
        pv.color,
        pv.size,
        p.name      AS product_name,
        p.thumbnail AS thumbnail
      FROM $orderItemsTable oi
      JOIN $productVariantsTable pv ON pv.id = oi.variant_id
      JOIN $productsTable        p  ON p.id  = pv.product_id
      WHERE oi.order_id = ?
      ORDER BY oi.id ASC
      ''',
      [orderId],
    );

    return {...orderRows.first, 'order_items': itemRows};
  }

  /// Lấy Variant ID dựa trên Product ID, Color và Size. 
  /// Trả về ID của variant tìm thấy hoặc variant đầu tiên của sản phẩm nếu không match.
  Future<int> getVariantId(String productId, String? color, String? size) async {
    final pId = int.tryParse(productId);
    debugPrint('[getVariantId] INPUT → productId=$productId, color=$color, size=$size, parsedPId=$pId');
    if (pId == null) return 0;

    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        
        // Query exact match trên Supabase
        var query = client.from('product_variants').select('id').eq('product_id', pId);
        if (color != null && color.isNotEmpty) {
          query = query.eq('color', color);
        }
        if (size != null && size.isNotEmpty) {
          query = query.eq('size', size);
        }
        
        final exactRows = await query.limit(1).maybeSingle();
        if (exactRows != null) {
          final id = (exactRows['id'] as num).toInt();
          debugPrint('[getVariantId] ✅ Supabase exact match → variantId=$id');
          return id;
        }

        // Fallback: Lấy variant đầu tiên của product trên Supabase
        final fallbackRows = await client
            .from('product_variants')
            .select('id')
            .eq('product_id', pId)
            .limit(1)
            .maybeSingle();
        if (fallbackRows != null) {
          final id = (fallbackRows['id'] as num).toInt();
          debugPrint('[getVariantId] ⚠️ Supabase fallback (first variant) → variantId=$id');
          return id;
        }
        debugPrint('[getVariantId] ❌ Supabase: không tìm thấy variant nào cho productId=$pId');
      } catch (e) {
        debugPrint('[getVariantId] ❌ Supabase error: $e → Falling back to SQLite.');
      }
    }

    // SQLite local fallback
    final db = await database;
    
    String whereStr = 'product_id = ?';
    List<Object?> whereArgsList = [pId];
    
    if (color != null && color.isNotEmpty) {
      whereStr += ' AND color = ?';
      whereArgsList.add(color);
    }
    if (size != null && size.isNotEmpty) {
      whereStr += ' AND size = ?';
      whereArgsList.add(size);
    }
    
    final exactMatches = await db.query(
      productVariantsTable, 
      columns: ['id'], 
      where: whereStr, 
      whereArgs: whereArgsList, 
      limit: 1,
    );
    
    if (exactMatches.isNotEmpty) {
      final id = exactMatches.first['id'] as int;
      debugPrint('[getVariantId] ⚠️ SQLite exact match → variantId=$id (có thể không khớp Supabase!)');
      return id;
    }
    
    // Fallback: Lấy variant đầu tiên của product trong SQLite
    final anyMatches = await db.query(
      productVariantsTable, 
      columns: ['id'], 
      where: 'product_id = ?', 
      whereArgs: [pId], 
      limit: 1,
    );
    
    if (anyMatches.isNotEmpty) {
      final id = anyMatches.first['id'] as int;
      debugPrint('[getVariantId] ⚠️ SQLite fallback (first variant) → variantId=$id (có thể không khớp Supabase!)');
      return id;
    }
    debugPrint('[getVariantId] ❌ Không tìm thấy variant nào → trả về 0');
    return 0;
  }

  /// Kiểm tra tồn kho trước khi đặt hàng.
  /// Trả về danh sách [variantId] bị thiếu hàng. Nếu rỗng → đủ hàng.
  Future<List<int>> checkStockAvailability(
    List<({int variantId, int quantity})> items,
  ) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        final outOfStock = <int>[];
        for (final item in items) {
          final row = await client
              .from('product_variants')
              .select('stock')
              .eq('id', item.variantId)
              .maybeSingle();
          if (row == null) {
            // Variant không tìm thấy trên Supabase (có thể là ID local khác ID Supabase)
            // → bỏ qua, không báo hết hàng để tránh false positive
            debugPrint('[checkStockAvailability] Variant ${item.variantId} không tìm thấy trên Supabase, bỏ qua kiểm tra.');
            continue;
          }
          final stock = (row['stock'] as num?)?.toInt() ?? 0;
          if (stock < item.quantity) {
            outOfStock.add(item.variantId);
          }
        }
        return outOfStock;
      } catch (e) {
        debugPrint('[checkStockAvailability] Supabase error: $e. Bỏ qua kiểm tra tồn kho.');
        // Nếu Supabase lỗi, bỏ qua hoàn toàn kiểm tra → không block đặt hàng
        return [];
      }
    }

    // Offline: kiểm tra SQLite local
    final db = await database;
    final outOfStock = <int>[];
    for (final item in items) {
      final row = await db.query(
        productVariantsTable,
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [item.variantId],
        limit: 1,
      );
      if (row.isEmpty) {
        outOfStock.add(item.variantId);
        continue;
      }
      final stock = row.first['stock'] as int? ?? 0;
      if (stock < item.quantity) {
        outOfStock.add(item.variantId);
      }
    }
    return outOfStock;
  }

  /// Places an order and decrements stock atomically.
  /// Throws [InsufficientStockException] nếu bất kỳ variant nào hết hàng.
  Future<int> placeOrder({
    required int userId,
    required String shippingAddress,
    required String paymentMethod,
    required List<({int variantId, int quantity, double price})> items,
    String? supabaseUserId,
  }) async {
    // Nếu sử dụng Supabase và có supabaseUserId
    if (SupabaseConfig.instance.isConfigured && supabaseUserId != null) {
      final client = Supabase.instance.client;

      // Bỏ kiểm tra stock ở đây — đã được checkStockAvailability() kiểm tra
      // trước đó trong checkout_page.dart. Không kiểm tra lại để tránh
      // bất nhất khi variantId là ID local SQLite thay vì ID Supabase.

      final total = items.fold<double>(
        0,
        (sum, i) => sum + i.price * i.quantity,
      );
      final paymentStatus = paymentMethod == 'COD' ? 'unpaid' : 'paid';

      // Log để debug variantId đang được dùng
      for (final item in items) {
        debugPrint('[placeOrder] Placing order with variantId=${item.variantId}, qty=${item.quantity}');
      }

      // 1. Insert đơn hàng vào bảng 'orders' trên Supabase
      final orderInsert = await client.from('orders').insert({
        'user_id': supabaseUserId,
        'total_amount': total,
        'shipping_address': shippingAddress,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
        'status': 'pending',
      }).select('id').single();

      final supabaseOrderId = (orderInsert['id'] as num).toInt();

      // 2. Insert chi tiết đơn hàng (order_items)
      for (final item in items) {
        // Lấy tồn kho trước khi insert để đối chiếu với tồn kho sau khi insert
        int stockBefore = 0;
        try {
          final variantRow = await client
              .from('product_variants')
              .select('stock')
              .eq('id', item.variantId)
              .maybeSingle();
          if (variantRow != null) {
            stockBefore = (variantRow['stock'] as num).toInt();
          }
        } catch (e) {
          debugPrint('[placeOrder] Không thể đọc stock trước cho variant ${item.variantId}: $e');
        }

        await client.from('order_items').insert({
          'order_id': supabaseOrderId,
          'variant_id': item.variantId,
          'quantity': item.quantity,
          'price_at_purchase': item.price,
        });

        // Giảm tồn kho trên Supabase (chỉ giảm thủ công nếu không có DB trigger tự động giảm)
        try {
          final variantRow = await client
              .from('product_variants')
              .select('stock')
              .eq('id', item.variantId)
              .maybeSingle();
          if (variantRow != null) {
            final stockAfter = (variantRow['stock'] as num).toInt();

            // Nếu stockAfter < stockBefore, điều đó chứng tỏ database đã có trigger 
            // tự động trừ tồn kho (ví dụ: trigger ON INSERT order_items).
            // Chúng ta KHÔNG được trừ thêm lần nữa để tránh lỗi trừ gấp đôi (double decrement).
            if (stockAfter == stockBefore) {
              final newStock = (stockAfter - item.quantity).clamp(0, stockAfter);
              await client
                  .from('product_variants')
                  .update({'stock': newStock})
                  .eq('id', item.variantId);
              debugPrint('[placeOrder] Đã trừ tồn kho thủ công từ Flutter: $stockAfter -> $newStock');
            } else {
              debugPrint('[placeOrder] Phát hiện DB Trigger đã tự động trừ tồn kho: $stockBefore -> $stockAfter. Bỏ qua trừ thủ công.');
            }
          }
        } catch (e) {
          debugPrint('[placeOrder] Không thể cập nhật/kiểm tra tồn kho Supabase cho variant ${item.variantId}: $e');
          // Tiếp tục xử lý — không block đặt hàng do lỗi update stock
        }
      }

      // 4. Đồng bộ đơn hàng xuống SQLite local (chỉ lưu đơn + chi tiết để xem offline)
      // Không trừ tồn kho SQLite vì Supabase là nguồn sự thật duy nhất cho stock.
      try {
        final db = await database;
        await db.transaction((tx) async {
          await tx.insert(ordersTable, {
            'id': supabaseOrderId,
            'user_id': userId,
            'total_amount': total,
            'shipping_address': shippingAddress,
            'payment_method': paymentMethod,
            'payment_status': paymentStatus,
            'status': 'pending',
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          for (final item in items) {
            await tx.insert(orderItemsTable, {
              'order_id': supabaseOrderId,
              'variant_id': item.variantId,
              'quantity': item.quantity,
              'price_at_purchase': item.price,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            // Tồn kho đã được trừ trên Supabase — bỏ qua UPDATE SQLite để tránh lỗi CHECK constraint.
          }
        });
      } catch (e) {
        debugPrint('[placeOrder] Ghi cache SQLite thất bại: $e');
      }

      return supabaseOrderId;
    }

    // Nếu Supabase đã được cấu hình nhưng không có supabaseUserId → người dùng chưa đăng nhập
    if (SupabaseConfig.instance.isConfigured) {
      throw Exception('Bạn cần đăng nhập để đặt hàng.');
    }

    // Luồng SQLite Local thuần (chỉ dùng khi hoàn toàn offline, không cấu hình Supabase)
    final db = await database;
    return db.transaction((tx) async {
      // Kiểm tra tồn kho — ném exception rõ ràng nếu không đủ hàng
      for (final item in items) {
        final row = await tx.query(
          productVariantsTable,
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item.variantId],
          limit: 1,
        );
        if (row.isEmpty) {
          throw InsufficientStockException(
            variantId: item.variantId,
            available: 0,
            requested: item.quantity,
          );
        }
        final stock = row.first['stock'] as int? ?? 0;
        if (stock < item.quantity) {
          throw InsufficientStockException(
            variantId: item.variantId,
            available: stock,
            requested: item.quantity,
          );
        }
      }

      final total = items.fold<double>(
        0,
        (sum, i) => sum + i.price * i.quantity,
      );

      final paymentStatus = paymentMethod == 'COD' ? 'unpaid' : 'paid';

      final orderId = await tx.insert(ordersTable, {
        'user_id': userId,
        'total_amount': total,
        'shipping_address': shippingAddress,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
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
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;

        final orderRow = await client
            .from('orders')
            .select('status')
            .eq('id', orderId)
            .maybeSingle();
        final oldStatus = orderRow != null ? orderRow['status'] as String? : null;

        if (status != oldStatus) {
          // 1. Lấy thông tin chi tiết các order items
          final items = await client
              .from('order_items')
              .select('variant_id, quantity')
              .eq('order_id', orderId)
              as List<dynamic>;

          if (items.isNotEmpty) {
            final List<Map<String, dynamic>> itemList = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final variantIds = itemList.map((e) => e['variant_id'] as int).toList();

            // 2. Lấy stock trước khi cập nhật status (1 query duy nhất)
            final stockBeforeRows = await client
                .from('product_variants')
                .select('id, stock')
                .filter('id', 'in', '(${variantIds.join(",")})');
            
            final stockBeforeMap = {
              for (final r in stockBeforeRows)
                (r['id'] as num).toInt(): (r['stock'] as num).toInt()
            };

            // 3. Cập nhật status của order (lúc này Trigger trên Supabase sẽ tự động chạy nếu có)
            await client.from('orders').update({'status': status}).eq('id', orderId);

            // 4. Lấy lại stock sau khi cập nhật status (1 query duy nhất) để kiểm tra trigger
            final stockAfterRows = await client
                .from('product_variants')
                .select('id, stock')
                .filter('id', 'in', '(${variantIds.join(",")})');
            
            final stockAfterMap = {
              for (final r in stockAfterRows)
                (r['id'] as num).toInt(): (r['stock'] as num).toInt()
            };

            // 5. So sánh và thực hiện cộng/trừ thủ công nếu không có trigger
            for (final item in itemList) {
              final variantId = item['variant_id'] as int;
              final qty = item['quantity'] as int;
              final before = stockBeforeMap[variantId] ?? 0;
              final after = stockAfterMap[variantId] ?? 0;

              if (status == 'cancelled' && oldStatus != 'cancelled') {
                // Nếu stock sau khi update status vẫn bằng stock trước đó -> Không có trigger cộng lại stock
                if (after == before) {
                  final newStock = before + qty;
                  await client
                      .from('product_variants')
                      .update({'stock': newStock})
                      .eq('id', variantId);
                  debugPrint('[updateOrderStatus] Đã cộng tồn kho thủ công: $before -> $newStock');
                } else {
                  debugPrint('[updateOrderStatus] Phát hiện DB Trigger đã tự động cộng tồn kho: $before -> $after. Bỏ qua cộng thủ công.');
                }
              } else if (status != 'cancelled' && oldStatus == 'cancelled') {
                // Nếu phục hồi đơn hàng: kiểm tra nếu stock sau khi update status vẫn bằng stock trước đó -> Không có trigger trừ stock
                if (after == before) {
                  final newStock = (before - qty).clamp(0, before);
                  await client
                      .from('product_variants')
                      .update({'stock': newStock})
                      .eq('id', variantId);
                  debugPrint('[updateOrderStatus] Đã trừ tồn kho thủ công: $before -> $newStock');
                } else {
                  debugPrint('[updateOrderStatus] Phát hiện DB Trigger đã tự động trừ tồn kho: $before -> $after. Bỏ qua trừ thủ công.');
                }
              }
            }
          } else {
            // Không có items, chỉ cần cập nhật status
            await client.from('orders').update({'status': status}).eq('id', orderId);
          }
        }
      } catch (e) {
        debugPrint('[updateOrderStatus] Supabase error: $e');
      }
    }

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

      if (status != oldStatus) {
        await tx.update(
          ordersTable,
          {'status': status},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        // Trả lại tồn kho SQLite local khi đơn bị huỷ
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
        // Trừ lại tồn kho SQLite local khi đơn được phục hồi từ trạng thái huỷ
        else if (status != 'cancelled' && oldStatus == 'cancelled') {
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
              SET stock = stock - ?
              WHERE id = ?
            ''',
              [item['quantity'], item['variant_id']],
            );
          }
        }
      }
    });
  }

  Future<void> updatePaymentStatus(int orderId, String paymentStatus) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        await client.from('orders').update({'payment_status': paymentStatus}).eq('id', orderId);
      } catch (e) {
        debugPrint('[updatePaymentStatus] Supabase error: $e');
      }
    }

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

  // ── Revenue / statistics API ─────────────────────────────────────────────

  /// Tổng quan doanh thu trong khoảng thời gian (chỉ đơn đã giao hoặc đang xử lý).
  Future<Map<String, Object?>> getRevenueSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;

    final conditions = <String>[];
    final args = <Object>[];

    conditions.add("o.status NOT IN ('cancelled')");

    if (from != null) {
      conditions.add('o.order_date >= ?');
      args.add(
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')} 00:00:00',
      );
    }
    if (to != null) {
      conditions.add('o.order_date <= ?');
      args.add(
        '${to.year.toString().padLeft(4, '0')}-'
        '${to.month.toString().padLeft(2, '0')}-'
        '${to.day.toString().padLeft(2, '0')} 23:59:59',
      );
    }

    final where = 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        COUNT(*)          AS total_orders,
        COALESCE(SUM(CASE WHEN o.status = 'delivered' THEN o.total_amount ELSE 0 END), 0) AS total_revenue,
        COALESCE(AVG(o.total_amount), 0) AS avg_order_value,
        SUM(CASE WHEN o.status = 'delivered'  THEN 1 ELSE 0 END) AS delivered_count,
        SUM(CASE WHEN o.status = 'processing' THEN 1 ELSE 0 END) AS processing_count,
        SUM(CASE WHEN o.status = 'shipped'    THEN 1 ELSE 0 END) AS shipped_count,
        SUM(CASE WHEN o.status = 'pending'    THEN 1 ELSE 0 END) AS pending_count
      FROM $ordersTable o
      $where
      ''', args);
    return rows.isNotEmpty ? rows.first : {};
  }

  /// Doanh thu theo ngày trong khoảng thời gian (không tính đơn huỷ).
  Future<List<Map<String, Object?>>> getRevenueByDay({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;

    final conditions = <String>["o.status NOT IN ('cancelled')"];
    final args = <Object>[];

    if (from != null) {
      conditions.add('o.order_date >= ?');
      args.add(
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')} 00:00:00',
      );
    }
    if (to != null) {
      conditions.add('o.order_date <= ?');
      args.add(
        '${to.year.toString().padLeft(4, '0')}-'
        '${to.month.toString().padLeft(2, '0')}-'
        '${to.day.toString().padLeft(2, '0')} 23:59:59',
      );
    }

    final where = 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        strftime('%Y-%m-%d', o.order_date) AS day,
        COALESCE(SUM(o.total_amount), 0)   AS revenue,
        COUNT(*)                           AS orders
      FROM $ordersTable o
      $where
      GROUP BY day
      ORDER BY day ASC
      ''', args);
  }

  /// Top sản phẩm bán chạy theo doanh thu trong khoảng thời gian.
  Future<List<Map<String, Object?>>> getTopProductsByRevenue({
    DateTime? from,
    DateTime? to,
    int limit = 5,
  }) async {
    final db = await database;

    final conditions = <String>["o.status NOT IN ('cancelled')"];
    final args = <Object>[];

    if (from != null) {
      conditions.add('o.order_date >= ?');
      args.add(
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')} 00:00:00',
      );
    }
    if (to != null) {
      conditions.add('o.order_date <= ?');
      args.add(
        '${to.year.toString().padLeft(4, '0')}-'
        '${to.month.toString().padLeft(2, '0')}-'
        '${to.day.toString().padLeft(2, '0')} 23:59:59',
      );
    }
    args.add(limit);

    final where = 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        p.name                                         AS product_name,
        p.thumbnail                                    AS thumbnail,
        SUM(oi.quantity)                               AS total_qty,
        SUM(oi.quantity * oi.price_at_purchase)        AS total_revenue
      FROM $orderItemsTable oi
      JOIN $ordersTable           o  ON o.id = oi.order_id
      JOIN $productVariantsTable  pv ON pv.id = oi.variant_id
      JOIN $productsTable         p  ON p.id  = pv.product_id
      $where
      GROUP BY p.id
      ORDER BY total_revenue DESC
      LIMIT ?
      ''', args);
  }

  /// Doanh thu theo danh mục trong khoảng thời gian.
  Future<List<Map<String, Object?>>> getRevenueByCategory({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;

    final conditions = <String>["o.status NOT IN ('cancelled')"];
    final args = <Object>[];

    if (from != null) {
      conditions.add('o.order_date >= ?');
      args.add(
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')} 00:00:00',
      );
    }
    if (to != null) {
      conditions.add('o.order_date <= ?');
      args.add(
        '${to.year.toString().padLeft(4, '0')}-'
        '${to.month.toString().padLeft(2, '0')}-'
        '${to.day.toString().padLeft(2, '0')} 23:59:59',
      );
    }

    final where = 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        c.name                                  AS category_name,
        SUM(oi.quantity * oi.price_at_purchase) AS total_revenue,
        SUM(oi.quantity)                        AS total_qty
      FROM $orderItemsTable oi
      JOIN $ordersTable           o  ON o.id = oi.order_id
      JOIN $productVariantsTable  pv ON pv.id = oi.variant_id
      JOIN $productsTable         p  ON p.id  = pv.product_id
      JOIN $categoriesTable       c  ON c.id  = p.category_id
      $where
      GROUP BY c.id
      ORDER BY total_revenue DESC
      ''', args);
  }

  /// Tính tổng số tiền đã mua của user (đã thanh toán hoặc nhận hàng thành công)
  Future<double> getTotalPurchasedAmount(int userId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(total_amount) as total
      FROM $ordersTable
      WHERE user_id = ? AND (payment_status = 'paid' OR status = 'delivered')
      ''',
      [userId],
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  /// Tính tổng số tiền đã mua của user từ các đơn hàng có trạng thái 'delivered' (đã giao)
  Future<double> getUserTotalSpent(String userId) async {
    if (SupabaseConfig.instance.isConfigured) {
      try {
        final client = Supabase.instance.client;
        final rows = await client
            .from('orders')
            .select('total_amount')
            .eq('user_id', userId)
            .eq('status', 'delivered') as List<dynamic>;

        double total = 0.0;
        for (var row in rows) {
          final amt = row['total_amount'];
          if (amt != null) {
            total += (amt as num).toDouble();
          }
        }
        return total;
      } catch (e) {
        debugPrint('[getUserTotalSpent] Supabase error: \$e. Falling back to SQLite.');
      }
    }

    final localUserId = int.tryParse(userId) ?? 1;
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(total_amount) as total
      FROM $ordersTable
      WHERE user_id = ? AND status = 'delivered'
      ''',
      [localUserId],
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }


  Future<Object?> getOrderItems(int orderId) async {
    return null;
  }

  Future<List<Map<String, Object?>>> getLocalCartItems(String userId) async {
    final db = await database;
    return db.query(
      cartItemsTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> saveLocalCartItem({
    required String id,
    required String productId,
    required int quantity,
    required String userId,
    String? color,
    String? size,
  }) async {
    final db = await database;
    await db.insert(
      cartItemsTable,
      {
        'id': id,
        'product_id': productId,
        'quantity': quantity,
        'color': color,
        'size': size,
        'user_id': userId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteLocalCartItem(String id, String userId) async {
    final db = await database;
    await db.delete(
      cartItemsTable,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> clearLocalCart(String userId) async {
    final db = await database;
    await db.delete(
      cartItemsTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
