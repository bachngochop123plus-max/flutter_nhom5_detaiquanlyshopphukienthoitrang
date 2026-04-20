import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/base_screen.dart';
import '../cubit/cart_cubit.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Giỏ hàng',
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state.items.isEmpty) {
            return const Center(child: Text('Giỏ hàng đang trống'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final item = state.itemList[index];
              return Card(
                child: ListTile(
                  title: Text(item.product.name),
                  subtitle: Text(
                    '${item.product.price.toStringAsFixed(0)} đ • SL ${item.quantity}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => context.read<CartCubit>().decrement(
                          item.product.id,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        onPressed: () => context.read<CartCubit>().increment(
                          item.product.id,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      IconButton(
                        onPressed: () =>
                            context.read<CartCubit>().remove(item.product.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemCount: state.itemList.length,
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.read<CartCubit>().clear(),
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('Xoá hết'),
      ),
    );
  }
}
