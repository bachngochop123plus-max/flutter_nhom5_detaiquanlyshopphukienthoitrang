import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';

class CartItem extends Equatable {
  const CartItem({
    required this.product,
    required this.quantity,
    this.selectedColor,
    this.selectedSize,
  });

  final Product product;
  final int quantity;
  final String? selectedColor;
  final String? selectedSize;

  double get lineTotal => product.price * quantity;

  CartItem copyWith({
    int? quantity,
    String? selectedColor,
    String? selectedSize,
  }) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedSize: selectedSize ?? this.selectedSize,
    );
  }

  @override
  List<Object?> get props => [product, quantity, selectedColor, selectedSize];
}

class CartState extends Equatable {
  const CartState({required this.items});

  factory CartState.initial() => const CartState(items: {});

  final Map<String, CartItem> items;

  List<CartItem> get itemList => items.values.toList(growable: false);

  double get total =>
      items.values.fold<double>(0, (sum, item) => sum + item.lineTotal);

  int get itemCount =>
      items.values.fold<int>(0, (sum, item) => sum + item.quantity);

  CartState copyWith({Map<String, CartItem>? items}) {
    return CartState(items: items ?? this.items);
  }

  @override
  List<Object?> get props => [items];
}

class CartCubit extends Cubit<CartState> {
  CartCubit(this._catalogRepository) : super(CartState.initial());

  final CatalogRepository _catalogRepository;

  void addProduct(Product product, {String? color, String? size}) {
    final current = Map<String, CartItem>.from(state.items);
    final existing = current[product.id];
    current[product.id] = existing == null
        ? CartItem(
            product: product,
            quantity: 1,
            selectedColor: color,
            selectedSize: size,
          )
        : existing.copyWith(
            quantity: existing.quantity + 1,
            selectedColor: color,
            selectedSize: size,
          );
    emit(state.copyWith(items: current));
  }

  void increment(String productId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[productId];
    if (item == null) {
      return;
    }

    current[productId] = item.copyWith(quantity: item.quantity + 1);
    emit(state.copyWith(items: current));
  }

  void decrement(String productId) {
    final current = Map<String, CartItem>.from(state.items);
    final item = current[productId];
    if (item == null) {
      return;
    }

    if (item.quantity <= 1) {
      current.remove(productId);
    } else {
      current[productId] = item.copyWith(quantity: item.quantity - 1);
    }

    emit(state.copyWith(items: current));
  }

  void remove(String productId) {
    final current = Map<String, CartItem>.from(state.items)..remove(productId);
    emit(state.copyWith(items: current));
  }

  void clear() => emit(CartState.initial());

  Product getProduct(String id) => _catalogRepository.byId(id);
}
