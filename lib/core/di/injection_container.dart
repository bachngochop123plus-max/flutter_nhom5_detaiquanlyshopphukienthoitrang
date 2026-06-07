import 'package:get_it/get_it.dart';

import '../data/cart_repository.dart';
import '../data/catalog_repository.dart';
import '../data/database_helper.dart';
import '../services/supabase_auth_repository.dart';
import '../services/supabase_storage_service.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/cart/presentation/cubit/cart_cubit.dart';
import '../../features/profile/data/repositories/profile_repository.dart';

final GetIt getIt = GetIt.instance;

Future<void> bootstrapDependencies() async {
  if (getIt.isRegistered<DatabaseHelper>()) {
    return;
  }

  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);
  getIt.registerLazySingleton<SupabaseAuthRepository>(
    () => SupabaseAuthRepository(databaseHelper: getIt<DatabaseHelper>()),
  );
  getIt.registerLazySingleton<SupabaseStorageService>(
    () => SupabaseStorageService(),
  );
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepository(
      databaseHelper: getIt<DatabaseHelper>(),
    ),
  );
  getIt.registerLazySingleton<CartRepository>(
    () => CartRepository(
      databaseHelper: getIt<DatabaseHelper>(),
    ),
  );
  getIt.registerLazySingleton<AuthCubit>(
    () => AuthCubit(getIt<SupabaseAuthRepository>()),
  );
  getIt.registerLazySingleton<CartCubit>(
    () => CartCubit(
      catalogRepository: getIt<CatalogRepository>(),
      cartRepository: getIt<CartRepository>(),
      authCubit: getIt<AuthCubit>(),
    ),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => ProfileRepository(databaseHelper: getIt<DatabaseHelper>()),
  );

  await getIt<DatabaseHelper>().init();
}
