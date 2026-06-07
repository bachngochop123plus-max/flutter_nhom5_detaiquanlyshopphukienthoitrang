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
    this.variants = const [],
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
  final List<Map<String, dynamic>> variants;

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
    List<Map<String, dynamic>>? variants,
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
      variants: variants ?? this.variants,
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
      variants: map['variants'] != null
          ? List<Map<String, dynamic>>.from(
              (map['variants'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : const [],
    );
  }

  String get thumbnail => imageUrl;
}
