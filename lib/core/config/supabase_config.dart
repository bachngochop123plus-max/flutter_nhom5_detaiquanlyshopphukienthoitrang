class SupabaseConfig {
  const SupabaseConfig._()
    : url = const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: defaultSupabaseUrl,
      ),
      anonKey = const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: defaultSupabaseAnonKey,
      );

  static const SupabaseConfig instance = SupabaseConfig._();

  static const String defaultSupabaseUrl =
      'https://qkweoptutabbzulsrpas.supabase.co';
  static const String defaultSupabaseAnonKey =
      'sb_publishable_yrhdw3sopoLnzl1Gz457Lw_Cl3-VLAn';

  final String url;
  final String anonKey;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
