import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/base_screen.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _currencyFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = context.read<AuthCubit>().state.profile;
      if (profile == null) {
        throw Exception('Bạn chưa đăng nhập');
      }

      final userIdStr = profile.id;
      final userId = int.tryParse(userIdStr) ?? 1; // 1 is default local user

      final rows = await _db.getOrdersForUser(userId);
      setState(() {
        _orders = rows.map(OrderModel.fromMap).toList();
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
      title: 'Lịch sử mua hàng',
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loadOrders,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC6A15B)),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 56, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadOrders,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 72,
                            color: const Color(0xFFC6A15B).withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Bạn chưa có đơn hàng nào',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        return _buildOrderCard(context, order);
                      },
                    ),
    );
  }

  Widget _buildOrderCard(BuildContext context, OrderModel order) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => context.push('/profile/orders/${order.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Đơn hàng #${order.id}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                _buildStatusBadge(order.status),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Ngày đặt: ${_dateFormat.format(order.orderDate)}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Giao đến: ${order.shippingAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Thanh toán: ${order.paymentStatusLabel}'),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tổng cộng:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  _currencyFormat.format(order.totalAmount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    String label;
    switch (status) {
      case 'delivered':
        bgColor = const Color(0xFF2D8F6F);
        label = 'Đã giao';
        break;
      case 'shipped':
        bgColor = const Color(0xFF1A73E8);
        label = 'Đang giao';
        break;
      case 'processing':
        bgColor = const Color(0xFFB9852E);
        label = 'Đang xử lý';
        break;
      case 'cancelled':
        bgColor = const Color(0xFFB23A48);
        label = 'Đã huỷ';
        break;
      case 'pending':
      default:
        bgColor = Colors.grey;
        label = 'Chờ xử lý';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
