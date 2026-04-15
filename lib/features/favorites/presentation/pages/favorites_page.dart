import 'package:flutter/material.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/product.dart';
import '../../../../core/widgets/base_screen.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  Future<void> _reload() async {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Yêu thích',
      body: FutureBuilder<List<Product>>(
        future: DatabaseHelper.instance.getFavorites(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('Chưa có sản phẩm yêu thích'));
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final product = items[index];
                return Dismissible(
                  key: ValueKey(product.id),
                  onDismissed: (_) async {
                    await DatabaseHelper.instance.removeFavorite(product.id);
                    _reload();
                  },
                  background: Container(color: Colors.redAccent),
                  child: Card(
                    child: ListTile(
                      title: Text(product.name),
                      subtitle: Text(product.category),
                      trailing: Text('${product.price.toStringAsFixed(0)} đ'),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: items.length,
            ),
          );
        },
      ),
    );
  }
}
