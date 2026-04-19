class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.imageUrl = '',
  });

  final int id;
  final String name;
  final String imageUrl;

  ProductCategory copyWith({int? id, String? name, String? imageUrl}) {
    return ProductCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'image_url': imageUrl};
  }

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? 'Unknown',
      imageUrl: map['image_url'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'ProductCategory(id: $id, name: $name, imageUrl: $imageUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductCategory &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          imageUrl == other.imageUrl;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ imageUrl.hashCode;
}
