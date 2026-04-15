class ApiConfig {
  const ApiConfig._()
    : productsUrl = const String.fromEnvironment('PRODUCTS_API_URL');

  static const ApiConfig instance = ApiConfig._();

  final String productsUrl;

  bool get hasProductsUrl => productsUrl.isNotEmpty;
}
