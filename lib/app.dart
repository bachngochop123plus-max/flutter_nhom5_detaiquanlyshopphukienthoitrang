import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/cart/presentation/cubit/cart_cubit.dart';

class FashionShopApp extends StatelessWidget {
  const FashionShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authCubit = GetIt.instance<AuthCubit>();
    final cartCubit = GetIt.instance<CartCubit>();

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: authCubit),
        BlocProvider.value(value: cartCubit),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Fashion Accessories Shop',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: buildAppRouter(authCubit: authCubit),
      ),
    );
  }
}
