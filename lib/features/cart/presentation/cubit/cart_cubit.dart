import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/data/cart_repository.dart';
import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class CartItem extends Equatable {
  const CartItem({
    required this.id, // Unique ID in cart: productId-color-size-userId
    required this.product,
    required this.quantity,
    this.selectedColor,
    this.selectedSize,
  });

  final String id;
  final Product product;
  final int quantity;
  final String? selectedColor;
  final String? selectedSize;

  double get lineTotal => product.price * quantity;

  CartItem copyWith({
    String? id,
    int? quantity,
    String? selectedColor,
    String? selectedSize,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product,
      quantity: quantity ?? this.quantity,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedSize: selectedSize ?? this.selectedSize,
    );
  }

  @override
  List<Object?> get props => [id, product, quantity, selectedColor, selectedSize];
}

class CartState extends Equatable {
  const CartState({
    required this.items,
    required this.selectedItemKeys,
  });

  factory CartState.initial() => const CartState(
        items: {},
        selectedItemKeys: {},
      );

  final Map<String, CartItem> items;
  final Set<String> selectedItemKeys;

  List<CartItem> get itemList => items.values.toList(growable: false);

  double get total =>
      items.values.fold<double>(0, (sum, item) => sum + item.lineTotal);

  int get itemCount =>
      items.values.fold<int>(0, (sum, item) => sum + item.quantity);

  // Tính tổng tiền của các item được chọn
  double get selectedTotal {
    double sum = 0;
    for (final key in selectedItemKeys) {
      final item = items[key];
      if (item != null) {
        sum += item.lineTotal;
      }
    }
    return sum;
  }

  // Lấy danh sách các item được chọn
  List<CartItem> get selectedItems {
    return selectedItemKeys.map((k) => items[k]!).toList();
  }

  CartState copyWith({
    Map<String, CartItem>? items,
    Set<String>? selectedItemKeys,
  }) {
    return CartState(
      items: items ?? this.items,
      selectedItemKeys: selectedItemKeys ?? this.selectedItemKeys,
    );
  }

  @override
  List<Object?> get props => [items, selectedItemKeys];
}

class CartCubit extends Cubit<CartState> {
  CartCubit({
    required CatalogRepository catalogRepository,
    required CartRepository cartRepository,
    required AuthCubit authCubit,
  })  : _catalogRepository = catalogRepository,
        _cartRepository = cartRepository,
        _authCubit = authCubit,
        super(CartState.initial()) {
    _authSubscription = _authCubit.stream.listen((authState) {
      _handleAuthStateChange(authState);
    });

    _initializeCart();
  }

  final CatalogRepository _catalogRepository;
  final CartRepository _cartRepository;
  final AuthCubit _authCubit;
  StreamSubscription<AuthState>? _authSubscription;

  String get _currentUserId => _authCubit.state.isAuthenticated ? _authCubit.state.profile!.id : 'guest';

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }

  void _initializeCart() {
    final authState = _authCubit.state;
    // Chỉ load khi đã biết trạng thái (không load khi unknown)
    if (authState.status == AuthStatus.authenticated && authState.profile != null) {
      _loadServerCart(authState.profile!.id);
    } else if (authState.status == AuthStatus.unauthenticated) {
      _loadLocalCart('guest');
    }
    // Nếu status = unknown thì chờ stream emit trạng thái thực
  }

  void _handleAuthStateChange(AuthState authState) async {
    if (authState.isAuthenticated) {
      final userId = authState.profile!.id;

      // NGAY LẬP TỨC reset UI để tránh hiển thị cart cũ trong lúc load
      emit(CartState.initial());

      try {
        // 1. Lấy giỏ hàng Guest hiện tại từ SQLite (user_id = 'guest')
        final guestItems = await _cartRepository.getLocalCart('guest');

        if (guestItems.isNotEmpty) {
          // 2. Lấy giỏ hàng hiện tại của User từ Server/SQLite fallback
          final userItems = await _cartRepository.getServerCart(userId);

          // 3. Gộp guest items vào user cart
          for (final guestItem in guestItems) {
            final productId = guestItem['product_id'] as String;
            final guestQty = guestItem['quantity'] as int;
            final color = guestItem['color'] as String?;
            final size = guestItem['size'] as String?;

            final match = userItems.firstWhere(
              (srvItem) =>
                  srvItem['product_id'].toString() == productId &&
                  srvItem['color'] == color &&
                  srvItem['size'] == size,
              orElse: () => {},
            );

            final localKey = _generateKey(productId, color, size, userId);
            final serverQty = match.isNotEmpty ? (match['quantity'] as int? ?? 1) : 0;
            await _cartRepository.saveServerCartItem(
              userId: userId,
              productId: productId,
              quantity: serverQty + guestQty,
              localKey: localKey,
              color: color,
              size: size,
            );
          }

          // 4. Xóa sạch giỏ hàng Guest local
          await _cartRepository.clearLocalCart('guest');
        }

        // 5. Tải giỏ hàng hoàn chỉnh của user về
        await _loadServerCart(userId);
      } catch (e) {
        debugPrint('[CartCubit] handleAuthStateChange (login) error: $e');
      }
    } else if (authState.status == AuthStatus.unauthenticated) {
      // ĐĂNG XUẤT:
      // 1. Reset memory state NGAY LẬP TỨC - đây là bước quan trọng nhất
      //    để UI xóa cart ngay khi logout, không cần chờ async
      emit(CartState.initial());

      // 2. Dọn dẹp guest cart local trong background (không block UI)
      _cartRepository.clearLocalCart('guest').catchError((e) {
        debugPrint('[CartCubit] clearLocalCart guest error: $e');
      });
    }
  }

  Future<void> _loadLocalCart(String userId) async {
    try {
      final localItems = await _cartRepository.getLocalCart(userId);
      final Map<String, CartItem> itemsMap = {};
      final Set<String> keys = {};

      for (final raw in localItems) {
        final id = raw['id'] as String;
        final productId = raw['product_id'] as String;
        final quantity = raw['quantity'] as int;
        final color = raw['color'] as String?;
        final size = raw['size'] as String?;

        try {
          final product = _catalogRepository.byId(productId);
          itemsMap[id] = CartItem(
            id: id,
            product: product,
            quantity: quantity,
            selectedColor: color,
            selectedSize: size,
          );
          keys.add(id);
        } catch (e) {
          debugPrint('[CartCubit] product $productId not found in catalog: $e');
        }
      }

      emit(state.copyWith(items: itemsMap, selectedItemKeys: keys));
    } catch (e) {
      debugPrint('[CartCubit] loadLocalCart error: $e');
    }
  }

  Future<void> _loadServerCart(String userId) async {
    try {
      final serverItems = await _cartRepository.getServerCart(userId);
      final Map<String, CartItem> itemsMap = {};
      final Set<String> keys = {};

      for (final raw in serverItems) {
        final productId = (raw['product_id'] ?? '').toString();
        final quantity = raw['quantity'] as int? ?? 1;
        final color = raw['color'] as String?;
        final size = raw['size'] as String?;
        
        final id = _generateKey(productId, color, size, userId);

        try {
          final product = _catalogRepository.byId(productId);
          itemsMap[id] = CartItem(
            id: id,
            product: product,
            quantity: quantity,
            selectedColor: color,
            selectedSize: size,
          );
          keys.add(id);
        } catch (e) {
          debugPrint('[CartCubit] product $productId not found in catalog: $e');
        }
      }

      emit(state.copyWith(items: itemsMap, selectedItemKeys: keys));
    } catch (e) {
      debugPrint('[CartCubit] loadServerCart error: $e');
    }
  }

  String _generateKey(String productId, String? color, String? size, String userId) {
    return '${productId}_${color ?? "none"}_${size ?? "none"}_$userId';
  }

  void addProduct(Product product, {String? color, String? size}) {
    final userId = _currentUserId;
    final key = _generateKey(product.id, color, size, userId);
    final current = Map<String, CartItem>.from(state.items);
    final existing = current[key];

    final newQty = (existing?.quantity ?? 0) + 1;
    current[key] = existing == null
        ? CartItem(
            id: key,
            product: product,
            quantity: 1,
            selectedColor: color,
            selectedSize: size,
          )
        : existing.copyWith(
            quantity: newQty,
          );
          
    final newSelected = Set<String>.from(state.selectedItemKeys)..add(key);

    emit(state.copyWith(items: current, selectedItemKeys: newSelected));

    _persistItem(product.id, newQty, color, size, key, userId);
  }

  /// Tăng số lượng. Trả về true nếu thành công, false nếu đã đạt tồn kho tối đa.
  bool increment(String cartItemId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[cartItemId];
    if (item == null) return false;

    final maxStock = _stockOf(item);
    if (item.quantity >= maxStock) return false;

    final newQty = item.quantity + 1;
    current[cartItemId] = item.copyWith(quantity: newQty);
    emit(state.copyWith(items: current));

    final userId = _currentUserId;
    _persistItem(item.product.id, newQty, item.selectedColor, item.selectedSize, cartItemId, userId);
    return true;
  }

  void decrement(String cartItemId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[cartItemId];
    if (item == null) return;

    if (item.quantity <= 1) {
      remove(cartItemId);
    } else {
      final newQty = item.quantity - 1;
      current[cartItemId] = item.copyWith(quantity: newQty);
      emit(state.copyWith(items: current));

      final userId = _currentUserId;
      _persistItem(item.product.id, newQty, item.selectedColor, item.selectedSize, cartItemId, userId);
    }
  }

  void remove(String cartItemId) {
    final item = state.items[cartItemId];
    if (item == null) return;

    final current = Map<String, CartItem>.from(state.items)..remove(cartItemId);
    final newSelected = Set<String>.from(state.selectedItemKeys)..remove(cartItemId);
    emit(state.copyWith(items: current, selectedItemKeys: newSelected));

    final userId = _currentUserId;
    final authState = _authCubit.state;
    if (authState.isAuthenticated) {
      _cartRepository.deleteServerCartItem(
        userId: userId,
        productId: item.product.id,
        localKey: cartItemId,
        color: item.selectedColor,
        size: item.selectedSize,
      ).catchError((e) {
        debugPrint('[CartCubit] delete server failed: $e');
      });
    } else {
      _cartRepository.deleteLocalCartItem(cartItemId, userId).catchError((e) {
        debugPrint('[CartCubit] delete local failed: $e');
      });
    }
  }

  void toggleSelection(String cartItemId) {
    final newSelected = Set<String>.from(state.selectedItemKeys);
    if (newSelected.contains(cartItemId)) {
      newSelected.remove(cartItemId);
    } else {
      newSelected.add(cartItemId);
    }
    emit(state.copyWith(selectedItemKeys: newSelected));
  }

  void toggleAll() {
    if (state.selectedItemKeys.length == state.items.length) {
      emit(state.copyWith(selectedItemKeys: {}));
    } else {
      emit(state.copyWith(selectedItemKeys: state.items.keys.toSet()));
    }
  }

  void updateVariant(String oldCartItemId, {String? newColor, String? newSize}) {
    final item = state.items[oldCartItemId];
    if (item == null) return;

    final userId = _currentUserId;
    final newKey = _generateKey(item.product.id, newColor, newSize, userId);
    if (newKey == oldCartItemId) return;

    final current = Map<String, CartItem>.from(state.items);
    final newSelected = Set<String>.from(state.selectedItemKeys);

    int finalQuantity = item.quantity;

    if (current.containsKey(newKey)) {
      final existingNew = current[newKey]!;
      finalQuantity = existingNew.quantity + item.quantity;
      current[newKey] = existingNew.copyWith(
        quantity: finalQuantity,
      );
    } else {
      current[newKey] = item.copyWith(
        id: newKey,
        selectedColor: newColor,
        selectedSize: newSize,
      );
    }

    current.remove(oldCartItemId);
    
    if (newSelected.contains(oldCartItemId)) {
      newSelected.remove(oldCartItemId);
      newSelected.add(newKey);
    }

    emit(state.copyWith(items: current, selectedItemKeys: newSelected));

    final authState = _authCubit.state;
    if (authState.isAuthenticated) {
      _cartRepository.deleteServerCartItem(
        userId: userId,
        productId: item.product.id,
        localKey: oldCartItemId,
        color: item.selectedColor,
        size: item.selectedSize,
      ).then((_) {
        return _cartRepository.saveServerCartItem(
          userId: userId,
          productId: item.product.id,
          quantity: finalQuantity,
          localKey: newKey,
          color: newColor,
          size: newSize,
        );
      }).catchError((e) {
        debugPrint('[CartCubit] updateVariant server failed: $e');
      });
    } else {
      _cartRepository.deleteLocalCartItem(oldCartItemId, userId).then((_) {
        return _cartRepository.saveLocalCartItem(
          id: newKey,
          productId: item.product.id,
          quantity: finalQuantity,
          userId: userId,
          color: newColor,
          size: newSize,
        );
      }).catchError((e) {
        debugPrint('[CartCubit] updateVariant local failed: $e');
      });
    }
  }

  void removeSelectedItems() {
    final selectedKeys = List<String>.from(state.selectedItemKeys);
    if (selectedKeys.isEmpty) return;

    final current = Map<String, CartItem>.from(state.items);
    final itemsToRemove = <CartItem>[];
    
    for (final key in selectedKeys) {
      final item = current.remove(key);
      if (item != null) {
        itemsToRemove.add(item);
      }
    }
    
    emit(state.copyWith(items: current, selectedItemKeys: {}));

    final userId = _currentUserId;
    final authState = _authCubit.state;
    if (authState.isAuthenticated) {
      for (final item in itemsToRemove) {
        _cartRepository.deleteServerCartItem(
          userId: userId,
          productId: item.product.id,
          localKey: item.id,
          color: item.selectedColor,
          size: item.selectedSize,
        ).catchError((e) {
          debugPrint('[CartCubit] delete server item failed: $e');
        });
      }
    } else {
      for (final key in selectedKeys) {
        _cartRepository.deleteLocalCartItem(key, userId).catchError((e) {
          debugPrint('[CartCubit] delete local item failed: $e');
        });
      }
    }
  }

  void clear() {
    emit(CartState.initial());

    final userId = _currentUserId;
    final authState = _authCubit.state;
    if (authState.isAuthenticated) {
      _cartRepository.clearServerCart(userId).catchError((e) {
        debugPrint('[CartCubit] clear server cart failed: $e');
      });
    } else {
      _cartRepository.clearLocalCart(userId).catchError((e) {
        debugPrint('[CartCubit] clear local cart failed: $e');
      });
    }
  }

  /// Set số lượng cụ thể cho item trong giỏ hàng.
  /// Số lượng sẽ được giới hạn trong khoảng [1, stock].
  /// Nếu qty <= 0 thì xóa item khỏi giỏ.
  void setQuantity(String cartItemId, int qty) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[cartItemId];
    if (item == null) return;

    if (qty <= 0) {
      remove(cartItemId);
      return;
    }

    final maxStock = _stockOf(item);
    final clamped = qty.clamp(1, maxStock);

    if (clamped == item.quantity) return;

    current[cartItemId] = item.copyWith(quantity: clamped);
    emit(state.copyWith(items: current));

    final userId = _currentUserId;
    _persistItem(item.product.id, clamped, item.selectedColor, item.selectedSize, cartItemId, userId);
  }

  /// Lấy số lượng tồn kho tối đa của một CartItem dựa trên variant đang chọn.
  int stockOf(CartItem item) => _stockOf(item);

  static int _stockOf(CartItem item) {
    final v = item.product.variants.firstWhere(
      (v) =>
          v['color'] == item.selectedColor &&
          v['size'] == item.selectedSize,
      orElse: () => {},
    );
    final stock = (v['stock'] as num?)?.toInt();
    if (stock != null) return stock;

    // Fallback: tổng stock của tất cả variant sản phẩm
    if (item.product.variants.isNotEmpty) {
      final total = item.product.variants.fold<int>(
        0,
        (sum, vv) => sum + ((vv['stock'] as num?)?.toInt() ?? 0),
      );
      return total > 0 ? total : 999;
    }
    return 999;
  }

  Product getProduct(String id) => _catalogRepository.byId(id);

  void _persistItem(String productId, int quantity, String? color, String? size, String localKey, String userId) {
    final authState = _authCubit.state;
    if (authState.isAuthenticated) {
      _cartRepository.saveServerCartItem(
        userId: userId,
        productId: productId,
        quantity: quantity,
        localKey: localKey,
        color: color,
        size: size,
      ).catchError((e) {
        debugPrint('[CartCubit] persist to server failed: $e');
      });
    } else {
      _cartRepository.saveLocalCartItem(
        id: localKey,
        productId: productId,
        quantity: quantity,
        userId: userId,
        color: color,
        size: size,
      ).catchError((e) {
        debugPrint('[CartCubit] persist to local failed: $e');
      });
    }
  }
}
