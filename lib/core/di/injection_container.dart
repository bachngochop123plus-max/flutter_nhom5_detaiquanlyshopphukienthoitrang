import 'package:get_it/get_it.dart';

import '../data/catalog_repository.dart';
import '../data/database_helper.dart';
import '../services/api_service.dart';
import '../services/supabase_auth_repository.dart';
import '../services/supabase_storage_service.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/cart/presentation/cubit/cart_cubit.dart';

final GetIt getIt = GetIt.instance;

Future<void> bootstrapDependencies() async {
  if (getIt.isRegistered<DatabaseHelper>()) {
    return;
  }

  getIt.registerLazySingleton<ApiService>(() => ApiService());
  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);
  getIt.registerLazySingleton<SupabaseAuthRepository>(
    () => SupabaseAuthRepository(databaseHelper: getIt<DatabaseHelper>()),
  );
  getIt.registerLazySingleton<SupabaseStorageService>(
    () => SupabaseStorageService(),
  );
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepository(
      apiService: getIt<ApiService>(),
      databaseHelper: getIt<DatabaseHelper>(),
    ),
  );
  getIt.registerLazySingleton<AuthCubit>(() => AuthCubit());
  getIt.registerLazySingleton<CartCubit>(
    () => CartCubit(getIt<CatalogRepository>()),
  );

  await getIt<DatabaseHelper>().init();
  await getIt<CatalogRepository>().warmUp();
}
