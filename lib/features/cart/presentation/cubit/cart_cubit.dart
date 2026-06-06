import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';

class CartItem extends Equatable {
  const CartItem({
    required this.id, // Unique ID in cart: productId-color-size
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
  CartCubit(this._catalogRepository) : super(CartState.initial());

  final CatalogRepository _catalogRepository;

  String _generateKey(String productId, String? color, String? size) {
    return '${productId}_${color ?? "none"}_${size ?? "none"}';
  }

  void addProduct(Product product, {String? color, String? size}) {
    final key = _generateKey(product.id, color, size);
    final current = Map<String, CartItem>.from(state.items);
    final existing = current[key];

    current[key] = existing == null
        ? CartItem(
            id: key,
            product: product,
            quantity: 1,
            selectedColor: color,
            selectedSize: size,
          )
        : existing.copyWith(
            quantity: existing.quantity + 1,
          );
          
    // Tự động chọn item mới thêm vào
    final newSelected = Set<String>.from(state.selectedItemKeys)..add(key);

    emit(state.copyWith(items: current, selectedItemKeys: newSelected));
  }

  void increment(String cartItemId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[cartItemId];
    if (item == null) return;

    current[cartItemId] = item.copyWith(quantity: item.quantity + 1);
    emit(state.copyWith(items: current));
  }

  void decrement(String cartItemId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[cartItemId];
    if (item == null) return;

    if (item.quantity <= 1) {
      remove(cartItemId);
    } else {
      current[cartItemId] = item.copyWith(quantity: item.quantity - 1);
      emit(state.copyWith(items: current));
    }
  }

  void remove(String cartItemId) {
    final current = Map<String, CartItem>.from(state.items)..remove(cartItemId);
    final newSelected = Set<String>.from(state.selectedItemKeys)..remove(cartItemId);
    emit(state.copyWith(items: current, selectedItemKeys: newSelected));
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
      // Đang chọn tất cả -> Bỏ chọn tất cả
      emit(state.copyWith(selectedItemKeys: {}));
    } else {
      // Chọn tất cả
      emit(state.copyWith(selectedItemKeys: state.items.keys.toSet()));
    }
  }

  // Thay đổi màu/size của một item trong giỏ
  void updateVariant(String oldCartItemId, {String? newColor, String? newSize}) {
    final item = state.items[oldCartItemId];
    if (item == null) return;

    final newKey = _generateKey(item.product.id, newColor, newSize);
    if (newKey == oldCartItemId) return; // Không có gì thay đổi

    final current = Map<String, CartItem>.from(state.items);
    final newSelected = Set<String>.from(state.selectedItemKeys);

    // Nếu variant mới đã có trong giỏ, gộp quantity lại
    if (current.containsKey(newKey)) {
      final existingNew = current[newKey]!;
      current[newKey] = existingNew.copyWith(
        quantity: existingNew.quantity + item.quantity,
      );
    } else {
      // Tạo item mới với key mới
      current[newKey] = item.copyWith(
        id: newKey,
        selectedColor: newColor,
        selectedSize: newSize,
      );
    }

    // Xoá item cũ
    current.remove(oldCartItemId);
    
    // Xử lý selection state
    if (newSelected.contains(oldCartItemId)) {
      newSelected.remove(oldCartItemId);
      newSelected.add(newKey);
    }

    emit(state.copyWith(items: current, selectedItemKeys: newSelected));
  }

  void removeSelectedItems() {
    final current = Map<String, CartItem>.from(state.items);
    for (final key in state.selectedItemKeys) {
      current.remove(key);
    }
    emit(state.copyWith(items: current, selectedItemKeys: {}));
  }

  void clear() => emit(CartState.initial());

  Product getProduct(String id) => _catalogRepository.byId(id);
}
