class ApiConfig {
  const ApiConfig._()
    : productsUrl = const String.fromEnvironment(
        'PRODUCTS_API_URL',
        defaultValue: _defaultProductsApiUrl,
      );

  static const ApiConfig instance = ApiConfig._();

  static const String _defaultProductsApiUrl = 'https://dummyjson.com/products';

  final String productsUrl;

  bool get hasProductsUrl => productsUrl.isNotEmpty;
}
