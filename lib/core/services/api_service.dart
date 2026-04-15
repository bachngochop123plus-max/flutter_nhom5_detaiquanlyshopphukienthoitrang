import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/failure.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    try {
      final response = await _client.get(uri);
      final decoded = _decodeResponse(response);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw ApiFailure(
        message: 'Dinh dang du lieu khong hop le (yeu cau object JSON)',
        code: 'INVALID_RESPONSE_TYPE',
      );
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw ApiFailure(
        message: 'Không thể kết nối máy chủ',
        code: error.runtimeType.toString(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> getListJson(Uri uri) async {
    try {
      final response = await _client.get(uri);
      final decoded = _decodeResponse(response);

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      throw ApiFailure(
        message: 'Dinh dang du lieu khong hop le (yeu cau danh sach JSON)',
        code: 'INVALID_RESPONSE_TYPE',
      );
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw ApiFailure(
        message: 'Không thể kết nối máy chủ',
        code: error.runtimeType.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? const {}),
      );
      final decoded = _decodeResponse(response);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw ApiFailure(
        message: 'Dinh dang du lieu khong hop le (yeu cau object JSON)',
        code: 'INVALID_RESPONSE_TYPE',
      );
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw ApiFailure(
        message: 'Không thể kết nối máy chủ',
        code: error.runtimeType.toString(),
      );
    }
  }

  dynamic _decodeResponse(http.Response response) {
    final decodedBody = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodedBody;
    }

    String? errorMessage;
    if (decodedBody is Map<String, dynamic>) {
      errorMessage = decodedBody['message']?.toString();
    }

    throw ApiFailure(
      message: errorMessage ?? 'Đã xảy ra lỗi từ máy chủ',
      code: response.statusCode.toString(),
    );
  }
}
