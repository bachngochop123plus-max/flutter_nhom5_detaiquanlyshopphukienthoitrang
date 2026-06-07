import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
import '../../features/admin/presentation/pages/admin_edit_product_page.dart';
import '../../features/admin/presentation/pages/admin_inventory_page.dart';
import '../../features/admin/presentation/pages/admin_orders_page.dart';
import '../../features/admin/presentation/pages/admin_revenue_page.dart';
import '../../features/favorites/presentation/pages/favorites_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/login/presentation/pages/login_page.dart';
import '../../features/login/presentation/pages/register_page.dart';
import '../../features/cart/presentation/pages/checkout_page.dart';
import '../../features/cart/presentation/pages/e_invoice_page.dart';
import '../../features/cart/presentation/pages/payment_qr_page.dart';
import '../../features/product_detail/presentation/pages/product_detail_page.dart';
import '../../features/profile/presentation/pages/order_detail_page.dart';
import '../../features/profile/presentation/pages/order_history_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/store_locator/presentation/pages/store_locator_page.dart';
import '../data/catalog_repository.dart';
import 'go_router_refresh_stream.dart';

GoRouter buildAppRouter({required AuthCubit authCubit}) {
  final catalogRepository = GetIt.instance<CatalogRepository>();

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    redirect: (context, state) {
      final currentState = authCubit.state;
      final onLogin = state.matchedLocation == '/login';
      final onRegister = state.matchedLocation == '/register';
      final onAdmin = state.matchedLocation.startsWith('/admin');

      // Đang check session → giữ nguyên trang hiện tại (splash sẽ tự điều hướng)
      if (currentState.isUnknown) return null;

      // Chặn admin route với non-admin user
      if (onAdmin && !currentState.isAdmin) {
        return '/home';
      }

      // Đã đăng nhập mà vào login/register → về home
      if ((onLogin || onRegister) && currentState.isAuthenticated) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
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
      GoRoute(
        path: '/admin/orders',
        builder: (context, state) => const AdminOrdersPage(),
      ),
      GoRoute(
        path: '/admin/revenue',
        builder: (context, state) => const AdminRevenuePage(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) {
              final isOffline = state.extra is bool ? state.extra as bool : false;
              return HomePage(
                products: catalogRepository.getProducts(),
                isOffline: isOffline,
              );
            },
            routes: [
              GoRoute(
                path: 'product',
                builder: (context, state) =>
                    ProductDetailPage(product: state.extra! as dynamic),
              ),
            ],
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const CartPage(),
          ),
          GoRoute(
            path: '/checkout',
            builder: (context, state) => const CheckoutPage(),
          ),
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
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => const EditProfilePage(),
              ),
              GoRoute(
                path: 'orders',
                builder: (context, state) => const OrderHistoryPage(),
                routes: [
                  GoRoute(
                    path: ':orderId',
                    builder: (context, state) {
                      final orderId = int.parse(state.pathParameters['orderId'] ?? '0');
                      return OrderDetailPage(orderId: orderId);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // ── Các trang thanh toán (không có bottom nav bar) ──────────────────
      GoRoute(
        path: '/payment-qr',
        builder: (context, state) {
          final orderId = int.parse(state.uri.queryParameters['orderId'] ?? '0');
          final total = double.parse(state.uri.queryParameters['total'] ?? '0');
          return PaymentQrPage(orderId: orderId, totalAmount: total);
        },
      ),
      GoRoute(
        path: '/e-invoice',
        builder: (context, state) {
          final orderId = int.parse(state.uri.queryParameters['orderId'] ?? '0');
          final total = double.tryParse(state.uri.queryParameters['total'] ?? '');
          final method = state.uri.queryParameters['method'];
          return EInvoicePage(orderId: orderId, totalAmount: total, paymentMethod: method);
        },
      ),
    ],
  );
}
