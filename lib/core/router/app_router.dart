import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
import '../../features/admin/presentation/pages/admin_edit_product_page.dart';
import '../../features/admin/presentation/pages/admin_inventory_page.dart';
import '../../features/favorites/presentation/pages/favorites_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/login/presentation/pages/login_page.dart';
import '../../features/login/presentation/pages/register_page.dart';
import '../../features/product_detail/presentation/pages/product_detail_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/store_locator/presentation/pages/store_locator_page.dart';
import '../data/catalog_repository.dart';
import 'go_router_refresh_stream.dart';

GoRouter buildAppRouter({required AuthCubit authCubit}) {
  final catalogRepository = GetIt.instance<CatalogRepository>();

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      final onAdmin = state.matchedLocation.startsWith('/admin');
      final isAdmin = authCubit.state.isAdmin;

      // Không chặn trang chủ để đúng luồng yêu cầu, chỉ giới hạn màn admin.
      if (onAdmin && !isAdmin) {
        return '/home';
      }

      if (onLogin && authCubit.state.isAuthenticated) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(path: '/admin', builder: (context, state) => const AdminPage()),
      GoRoute(
        path: '/admin/inventory',
        builder: (context, state) => const AdminInventoryPage(),
      ),
      GoRoute(
        path: '/admin/inventory/new',
        builder: (context, state) =>
            const AdminEditProductPage(isCreating: true),
      ),
      GoRoute(
        path: '/admin/inventory/edit',
        builder: (context, state) =>
            AdminEditProductPage(product: state.extra as dynamic),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) =>
                HomePage(products: catalogRepository.getProducts()),
            routes: [
              GoRoute(
                path: 'product',
                builder: (context, state) =>
                    ProductDetailPage(product: state.extra! as dynamic),
              ),
            ],
          ),
          GoRoute(path: '/cart', builder: (context, state) => const CartPage()),
          GoRoute(
            path: '/favorites',
            builder: (context, state) => const FavoritesPage(),
          ),
          GoRoute(
            path: '/stores',
            builder: (context, state) => const StoreLocatorPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    ],
  );
}
