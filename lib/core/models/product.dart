class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.price,
    required this.isDiscounted,
    required this.rating,
    this.gallery = const [],
    this.availableColors = const [],
    this.availableSizes = const [],
  });

  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String category;
  final double price;
  final bool isDiscounted;
  final double rating;
  final List<String> gallery;
  final List<String> availableColors;
  final List<String> availableSizes;

  Product copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    String? category,
    double? price,
    bool? isDiscounted,
    double? rating,
    List<String>? gallery,
    List<String>? availableColors,
    List<String>? availableSizes,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      price: price ?? this.price,
      isDiscounted: isDiscounted ?? this.isDiscounted,
      rating: rating ?? this.rating,
      gallery: gallery ?? this.gallery,
      availableColors: availableColors ?? this.availableColors,
      availableSizes: availableSizes ?? this.availableSizes,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'category': category,
      'price': price,
      'isDiscounted': isDiscounted ? 1 : 0,
      'rating': rating,
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      imageUrl: map['imageUrl'] as String,
      category: map['category'] as String,
      price: (map['price'] as num).toDouble(),
      isDiscounted: (map['isDiscounted'] as int) == 1,
      rating: (map['rating'] as num).toDouble(),
    );
  }

  factory Product.fromApiMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'San pham',
      description: map['description']?.toString() ?? '',
      imageUrl: map['image']?.toString() ?? map['imageUrl']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Phu kien',
      price: _parsePrice(map['price']),
      isDiscounted: (map['isDiscounted'] as bool?) ?? false,
      rating: (map['rating'] as num?)?.toDouble() ?? 4.5,
      gallery: _parseStringList(map['gallery']),
      availableColors: _parseStringList(map['availableColors']),
      availableSizes: _parseStringList(map['availableSizes']),
    );
  }

  Map<String, dynamic> toApiMap() {
    return {
      'id': id,
      'name': name,
      'image': imageUrl,
      'price': price,
      'description': description,
      'category': category,
      'isDiscounted': isDiscounted,
      'rating': rating,
      'gallery': gallery,
      'availableColors': availableColors,
      'availableSizes': availableSizes,
    };
  }

  static double _parsePrice(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.replaceAll(',', '').trim();
      return double.tryParse(normalized) ?? 0;
    }
    return 0;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return const [];
  }
}
