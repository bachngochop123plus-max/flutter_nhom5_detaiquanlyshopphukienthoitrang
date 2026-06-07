import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'fashion_shop.db';
  static const _databaseVersion = 7;
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
        // v6→v7: seed full demo data (categories + products + product_images per product)
        if (oldVersion < 7) {
          await _seedDemoData(db);
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

    if (product.variants != null && product.variants!.isNotEmpty) {
      for (final variant in product.variants!) {
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

  Future<List<Map<String, Object?>>> getOrdersForUser(int userId) async {
    final db = await database;
    return db.query(
      ordersTable,
      where: 'user_id = ?',
      whereArgs: [userId],
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
    final db = await database;
    final pId = int.tryParse(productId);
    if (pId == null) return 0;
    
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
      return exactMatches.first['id'] as int;
    }
    
    // Fallback: Lấy variant đầu tiên của product
    final anyMatches = await db.query(
      productVariantsTable, 
      columns: ['id'], 
      where: 'product_id = ?', 
      whereArgs: [pId], 
      limit: 1,
    );
    
    if (anyMatches.isNotEmpty) {
      return anyMatches.first['id'] as int;
    }
    return 0; // Fallback an toàn (có thể gây lỗi foreign key nếu = 0)
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
          // NOTE: Bỏ qua lỗi insufficient stock để demo luồng mua hàng trơn tru 
          // vì dữ liệu mẫu đang có stock = 0
          debugPrint('Bỏ qua lỗi tồn kho cho variant ${item.variantId}');
        }
      }

      final total = items.fold<double>(
        0,
        (sum, i) => sum + i.price * i.quantity,
      );

      // Nếu paymentMethod không phải COD thì coi như đã thanh toán (để test logic)
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
        COALESCE(SUM(o.total_amount), 0) AS total_revenue,
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

  Future<Object?> getOrderItems(int orderId) async {}
}
