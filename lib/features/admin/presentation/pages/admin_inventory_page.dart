import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../../core/widgets/base_screen.dart';

class AdminInventoryPage extends StatefulWidget {
  const AdminInventoryPage({super.key});

  @override
  State<AdminInventoryPage> createState() => _AdminInventoryPageState();
}

class _AdminInventoryPageState extends State<AdminInventoryPage> {
  late final CatalogRepository _catalogRepository;
  late List<Product> _products;

  @override
  void initState() {
    super.initState();
    _catalogRepository = GetIt.instance<CatalogRepository>();
    _products = _catalogRepository.getProducts();
  }

  Future<void> _reloadProducts() async {
    if (!mounted) return;
    setState(() {
      _products = _catalogRepository.getProducts();
    });
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoa san pham'),
        content: Text('Ban chac chan muon xoa "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _catalogRepository.deleteProduct(product.id);
    await _reloadProducts();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Da xoa san pham: ${product.name}')));
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Quan ly san pham',
      leading: IconButton(
        tooltip: 'Quay lai admin',
        onPressed: () => context.go('/admin'),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(
            onPressed: () async {
              final created = await context.push<bool>('/admin/inventory/new');
              if (created == true) {
                await _reloadProducts();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Them san pham'),
          ),
        ),
      ],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF9ED), Color(0xFFF3F8FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Danh sach san pham',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Nhan vao san pham de chinh sua. Dung nut thung rac de xoa.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(
                                  0xFFC6A15B,
                                ).withValues(alpha: 0.2),
                                child: const Icon(Icons.inventory_2_outlined),
                              ),
                              title: Text(product.name, maxLines: 1),
                              subtitle: Text(
                                '${product.category} • ${product.price.toStringAsFixed(0)} đ',
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Chinh sua',
                                    onPressed: () async {
                                      final updated = await context.push<bool>(
                                        '/admin/inventory/edit',
                                        extra: product,
                                      );
                                      if (updated == true) {
                                        await _reloadProducts();
                                      }
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Xoa',
                                    onPressed: () => _confirmDelete(product),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFC62828),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final updated = await context.push<bool>(
                                  '/admin/inventory/edit',
                                  extra: product,
                                );
                                if (updated == true) {
                                  await _reloadProducts();
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
