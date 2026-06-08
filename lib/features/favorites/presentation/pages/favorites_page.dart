import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/models/product.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  Future<void> _reload() async {
    setState(() {});
  }

  String _resolveImageUrl(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }
    if (clean.startsWith('assets/') || clean.startsWith('images/')) {
      return clean;
    }
    var normalized = clean;
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith('Img_Product/')) {
      normalized = 'Img_Product/$normalized';
    }
    return 'https://qkweoptutabbzulsrpas.supabase.co/storage/v1/object/public/Img_products/$normalized';
  }

  Widget _buildSafeImage(
    String imageUrl, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    double placeholderIconSize = 24.0,
  }) {
    final cleanUrl = _resolveImageUrl(imageUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (cleanUrl.isEmpty) {
      return Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        width: width,
        height: height,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: placeholderIconSize,
            color: Colors.grey,
          ),
        ),
      );
    }

    if (cleanUrl.startsWith('assets/') || cleanUrl.startsWith('images/')) {
      return Image.asset(
        cleanUrl,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: isDark ? Colors.grey[900] : Colors.grey[200],
            width: width,
            height: height,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: placeholderIconSize,
                color: Colors.grey,
              ),
            ),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: cleanUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) => Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.luxuryGold,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        width: width,
        height: height,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: placeholderIconSize,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        if (!authState.isAuthenticated) {
          return BaseScreen(
            title: 'Yêu thích',
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 72,
                    color: AppColors.luxuryGold.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Vui lòng đăng nhập để xem danh sách yêu thích',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.push('/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.luxuryGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Đăng nhập'),
                  ),
                ],
              ),
            ),
          );
        }

        final userId = authState.profile!.id;

        return BaseScreen(
          title: 'Yêu thích',
          body: FutureBuilder<List<Product>>(
            future: DatabaseHelper.instance.getFavorites(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.luxuryGold),
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 72,
                        color: AppColors.luxuryGold.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Chưa có sản phẩm yêu thích',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _reload,
                color: AppColors.luxuryGold,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final product = items[index];
                    return Dismissible(
                      key: ValueKey(product.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await DatabaseHelper.instance.toggleFavorite(userId, int.parse(product.id));
                        if (!mounted) return;
                        setState(() {
                          items.removeAt(index);
                        });
                        messenger.showSnackBar(
                          SnackBar(
                            content: const Text('Đã xóa khỏi danh sách yêu thích'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.danger,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
                      ),
                      child: Card(
                        elevation: isDark ? 2 : 4,
                        shadowColor: isDark ? Colors.black26 : Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: AppColors.luxuryGold.withValues(alpha: isDark ? 0.15 : 0.08),
                            width: 1.5,
                          ),
                        ),
                        color: isDark ? const Color(0xFF1B1B1B) : Colors.white,
                        child: InkWell(
                          onTap: () {
                            context.push('/home/product', extra: product);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Product Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: _buildSafeImage(product.imageUrl),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Category
                                      Text(
                                        product.category.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.luxuryGold,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Name
                                      Text(
                                        product.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : AppColors.deepBlack,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Price
                                      Row(
                                        children: [
                                          Text(
                                            '${product.price.toStringAsFixed(0)} đ',
                                            style: const TextStyle(
                                              color: AppColors.luxuryGold,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (product.isDiscounted) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '${(product.price * 1.25).toStringAsFixed(0)} đ',
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 11,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Heart button (unfavorite)
                                IconButton(
                                  icon: const Icon(Icons.favorite_rounded, color: AppColors.danger),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    await DatabaseHelper.instance.toggleFavorite(userId, int.parse(product.id));
                                    if (!mounted) return;
                                    _reload();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Đã xóa khỏi danh sách yêu thích'),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: AppColors.danger,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
