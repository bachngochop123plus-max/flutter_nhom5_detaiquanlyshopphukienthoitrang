import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/api_config.dart';
import 'core/config/supabase_config.dart';
import 'core/data/catalog_repository.dart';
import 'core/di/injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const launchProfile = String.fromEnvironment(
    'APP_PROFILE',
    defaultValue: 'UNSPECIFIED',
  );
  final apiConfig = ApiConfig.instance;
  final supabaseConfig = SupabaseConfig.instance;
  if (supabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: supabaseConfig.url,
      anonKey: supabaseConfig.anonKey,
    );
  }
  await bootstrapDependencies();
  final catalogRepository = getIt<CatalogRepository>();
  debugPrint(
    '[Startup] profile=$launchProfile, '
    'supabaseConfigured=${supabaseConfig.isConfigured}, '
    'apiConfigured=${apiConfig.hasProductsUrl}, '
    '${catalogRepository.runtimeSummary}',
  );
  runApp(const FashionShopApp());
}
