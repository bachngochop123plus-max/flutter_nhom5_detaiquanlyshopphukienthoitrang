class Category {
  const Category({required this.id, required this.name, this.imageUrl = ''});

  final int id;
  final String name;
  final String imageUrl;

  Category copyWith({int? id, String? name, String? imageUrl}) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'image_url': imageUrl};
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? 'Unknown',
      imageUrl: map['image_url'] as String? ?? '',
    );
  }

  @override
  String toString() => 'Category(id: $id, name: $name, imageUrl: $imageUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          imageUrl == other.imageUrl;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ imageUrl.hashCode;
}
