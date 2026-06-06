import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/base_screen.dart';

class OrderDetailPage extends StatefulWidget {
  final int orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _currencyFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  OrderModel? _order;
  List<OrderItemModel> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrderDetail();
  }

  Future<void> _loadOrderDetail() async {
    try {
      final orderWithItems = await _db.getOrderWithItems(widget.orderId);
      if (orderWithItems == null) throw Exception('Không tìm thấy đơn hàng');

      final order = OrderModel.fromMap(orderWithItems);

      final rawItems = orderWithItems['order_items'];
      final List<Map<String, Object?>> itemRows = rawItems is List
          ? rawItems.cast<Map<String, Object?>>()
          : const [];
      final items = itemRows.map(OrderItemModel.fromMap).toList();

      setState(() {
        _order = order;
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Chi tiết đơn hàng',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _order == null
                  ? const Center(child: Text('Không tìm thấy đơn hàng'))
                  : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mã đơn hàng: #${order.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Ngày đặt: ${_dateFormat.format(order.orderDate)}'),
                const SizedBox(height: 8),
                Text('Trạng thái: ${order.statusLabel}'),
                const SizedBox(height: 8),
                Text('Thanh toán: ${order.paymentStatusLabel} (${order.paymentMethod})'),
                const Divider(height: 24),
                Text('Giao đến:', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(order.shippingAddress),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Sản phẩm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        ..._items.map((item) => _buildItemCard(context, item)),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng thanh toán:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  _currencyFormat.format(order.totalAmount),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFFB9852E)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(BuildContext context, OrderItemModel item) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          item.productName ?? 'Sản phẩm',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('Số lượng: ${item.quantity}\nĐơn giá: ${_currencyFormat.format(item.priceAtPurchase)}'),
        trailing: Text(
          _currencyFormat.format(item.priceAtPurchase * item.quantity),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
