import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'database_helper.dart';

class CartRepository {
  CartRepository({
    required DatabaseHelper databaseHelper,
  }) : _databaseHelper = databaseHelper;

  final DatabaseHelper _databaseHelper;
  final _client = Supabase.instance.client;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  // ── SQLite Local Cart ───────────────────────────────────
  Future<List<Map<String, dynamic>>> getLocalCart(String userId) async {
    final list = await _databaseHelper.getLocalCartItems(userId);
    return list.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> saveLocalCartItem({
    required String id,
    required String productId,
    required int quantity,
    required String userId,
    String? color,
    String? size,
  }) async {
    await _databaseHelper.saveLocalCartItem(
      id: id,
      productId: productId,
      quantity: quantity,
      userId: userId,
      color: color,
      size: size,
    );
  }

  Future<void> deleteLocalCartItem(String id, String userId) async {
    await _databaseHelper.deleteLocalCartItem(id, userId);
  }

  Future<void> clearLocalCart(String userId) async {
    await _databaseHelper.clearLocalCart(userId);
  }

  // ── Remote (Supabase) or SQLite fallback ─────────────────
  Future<List<Map<String, dynamic>>> getServerCart(String userId) async {
    if (!_usesSupabase) {
      return getLocalCart(userId);
    }
    try {
      final response = await _client
          .from('cart_items')
          .select()
          .eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[CartRepository] getServerCart error: $e');
      return getLocalCart(userId);
    }
  }

  Future<void> saveServerCartItem({
    required String userId,
    required String productId,
    required int quantity,
    required String localKey,
    String? color,
    String? size,
  }) async {
    if (!_usesSupabase) {
      await saveLocalCartItem(
        id: localKey,
        productId: productId,
        quantity: quantity,
        userId: userId,
        color: color,
        size: size,
      );
      return;
    }
    try {
      final pId = int.tryParse(productId);
      if (pId == null) return;

      var query = _client.from('cart_items').select();
      query = query.eq('user_id', userId).eq('product_id', pId);
      if (color != null) {
        query = query.eq('color', color);
      } else {
        query = query.isFilter('color', null);
      }
      if (size != null) {
        query = query.eq('size', size);
      } else {
        query = query.isFilter('size', null);
      }

      final existingList = await query as List<dynamic>;
      if (existingList.isNotEmpty) {
        var updateQuery = _client.from('cart_items').update({'quantity': quantity});
        updateQuery = updateQuery.eq('user_id', userId).eq('product_id', pId);
        if (color != null) {
          updateQuery = updateQuery.eq('color', color);
        } else {
          updateQuery = updateQuery.isFilter('color', null);
        }
        if (size != null) {
          updateQuery = updateQuery.eq('size', size);
        } else {
          updateQuery = updateQuery.isFilter('size', null);
        }
        await updateQuery;
      } else {
        await _client.from('cart_items').insert({
          'user_id': userId,
          'product_id': pId,
          'quantity': quantity,
          'color': color,
          'size': size,
        });
      }
    } catch (e) {
      debugPrint('[CartRepository] saveServerCartItem error: $e');
      await saveLocalCartItem(
        id: localKey,
        productId: productId,
        quantity: quantity,
        userId: userId,
        color: color,
        size: size,
      );
    }
  }

  Future<void> deleteServerCartItem({
    required String userId,
    required String productId,
    required String localKey,
    String? color,
    String? size,
  }) async {
    if (!_usesSupabase) {
      await deleteLocalCartItem(localKey, userId);
      return;
    }
    try {
      final pId = int.tryParse(productId);
      if (pId == null) return;

      var query = _client.from('cart_items').delete().eq('user_id', userId).eq('product_id', pId);
      if (color != null) {
        query = query.eq('color', color);
      } else {
        query = query.isFilter('color', null);
      }
      if (size != null) {
        query = query.eq('size', size);
      } else {
        query = query.isFilter('size', null);
      }
      await query;
    } catch (e) {
      debugPrint('[CartRepository] deleteServerCartItem error: $e');
      await deleteLocalCartItem(localKey, userId);
    }
  }

  Future<void> clearServerCart(String userId) async {
    if (!_usesSupabase) {
      await clearLocalCart(userId);
      return;
    }
    try {
      await _client.from('cart_items').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('[CartRepository] clearServerCart error: $e');
      await clearLocalCart(userId);
    }
  }
}
