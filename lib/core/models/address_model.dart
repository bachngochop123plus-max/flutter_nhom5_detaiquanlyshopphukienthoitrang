import 'dart:convert';

class Address {
  final String id;
  final String title;
  final String detail;
  bool isDefault;

  Address({
    required this.id,
    required this.title,
    required this.detail,
    this.isDefault = false,
  });

  // Chuyển Object thành Map để mã hóa JSON
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'detail': detail,
      'isDefault': isDefault,
    };
  }

  // Tạo Object từ Map
  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      detail: map['detail'] ?? '',
      isDefault: map['isDefault'] ?? false,
    );
  }

  // Hai hàm bổ trợ để làm việc với SharedPreferences nhanh hơn
  String toJson() => json.encode(toMap());
  factory Address.fromJson(String source) => Address.fromMap(json.decode(source));
}