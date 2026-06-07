import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/app_notifications.dart';
import '../../../../core/widgets/base_screen.dart';

class OrderDetailPage extends StatefulWidget {
  final int orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final _db = GetIt.instance<DatabaseHelper>();
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

  String _formatDate(DateTime date) {
    return 'Ngày ${date.day.toString().padLeft(2, '0')} tháng ${date.month.toString().padLeft(2, '0')} năm ${date.year} ${DateFormat('HH:mm').format(date)}';
  }

  String _getPaymentMethodDisplay(OrderModel order) {
    final method = order.paymentMethod?.toLowerCase() ?? '';
    if (method == 'cod' || method == 'cash' || method.contains('tiền mặt')) {
      return 'Thanh toán khi nhận hàng (COD)';
    } else if (method.isNotEmpty) {
      return 'Đã thanh toán (Online - ${order.paymentMethod})';
    } else {
      if (order.paymentStatus == 'paid') {
        return 'Đã thanh toán trực tuyến';
      }
      return 'Thanh toán khi nhận hàng';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return const Color(0xFF2D8F6F);
      case 'shipped':
        return const Color(0xFF1A73E8);
      case 'processing':
        return const Color(0xFFC6A15B);
      case 'cancelled':
        return const Color(0xFFB23A48);
      case 'pending':
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle_outline;
      case 'shipped':
        return Icons.local_shipping_outlined;
      case 'processing':
        return Icons.inventory_2_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'pending':
      default:
        return Icons.hourglass_empty_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Chi tiết đơn hàng',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      bottomNavigationBar: _order?.status == 'pending' && !_isLoading && _error == null
          ? _buildBottomActions()
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC6A15B)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadOrderDetail,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC6A15B)),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _order == null
                  ? const Center(child: Text('Không tìm thấy đơn hàng'))
                  : _buildContent(context),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        child: OutlinedButton(
          onPressed: _showCancelDialog,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.red),
            foregroundColor: Colors.red,
          ),
          child: const Text('Huỷ đơn hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  void _showCancelDialog() {
    String selectedReason = 'Thay đổi ý định';
    final reasons = [
      'Thay đổi ý định',
      'Tìm thấy giá rẻ hơn chỗ khác',
      'Cập nhật địa chỉ/SĐT nhận hàng',
      'Phí vận chuyển cao',
      'Khác'
    ];

    AppNotifications.showConfirmationDialog(
      context,
      title: 'Huỷ đơn hàng',
      isDanger: true,
      customContent: StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vui lòng chọn lí do huỷ đơn:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              ...reasons.map((r) => RadioListTile<String>(
                title: Text(r, style: const TextStyle(fontSize: 14)),
                value: r,
                groupValue: selectedReason,
                onChanged: (value) {
                  setDialogState(() => selectedReason = value!);
                },
                contentPadding: EdgeInsets.zero,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                activeColor: Colors.red[700],
              )),
            ],
          );
        }
      ),
      confirmText: 'Xác nhận huỷ',
      onConfirm: () => _cancelOrder(),
    );
  }

  Future<void> _cancelOrder() async {
    setState(() => _isLoading = true);
    try {
      await _db.updateOrderStatus(widget.orderId, 'cancelled');
      
      final method = _order?.paymentMethod?.toLowerCase() ?? '';
      final isOnlinePayment = !(method == 'cod' || method == 'cash' || method.contains('tiền mặt'));
      final isPaid = _order?.paymentStatus == 'paid';
      
      if (!mounted) return;
      
      if (isOnlinePayment || isPaid) {
        AppNotifications.showInfoDialog(
          context,
          title: 'Huỷ Đơn Thành Công',
          customContent: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đơn hàng của bạn đã được huỷ.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC6A15B).withValues(alpha: 0.1),
                  border: Border.all(color: const Color(0xFFC6A15B).withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.currency_exchange_rounded, color: Color(0xFFC6A15B), size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Đang Xử Lý Hoàn Tiền', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC6A15B))),
                          SizedBox(height: 4),
                          Text('Số tiền đã thanh toán sẽ được hoàn về tài khoản ngân hàng của bạn trong vòng 24h tới.', style: TextStyle(fontSize: 13, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          closeText: 'Đã Hiểu',
        );
      } else {
        AppNotifications.showSuccessSnackBar(context, 'Đơn hàng đã được huỷ thành công');
      }
      
      await _loadOrderDetail();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppNotifications.showErrorSnackBar(context, 'Lỗi khi huỷ đơn: $e');
    }
  }

  Widget _buildContent(BuildContext context) {
    final order = _order!;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Status Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            color: _getStatusColor(order.status).withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: _getStatusColor(order.status).withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              Icon(_getStatusIcon(order.status), color: _getStatusColor(order.status), size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.statusLabel.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(order.status),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đơn hàng đã được cập nhật trạng thái',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Shipping Address
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Color(0xFFC6A15B), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Địa chỉ nhận hàng',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.customerName != null) ...[
                      Text(
                        '${order.customerName} | ${order.customerPhone ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      order.shippingAddress,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Order Items
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined, color: Color(0xFFC6A15B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Sản phẩm đã mua',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ..._items.map((item) => _buildItemRow(context, item)),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Order Information
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thông tin đơn hàng',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildInfoRow('Mã đơn hàng', '#${order.id}', isCopyable: true),
              _buildInfoRow('Thời gian đặt', _formatDate(order.orderDate)),
              _buildInfoRow('Phương thức', _getPaymentMethodDisplay(order), valueColor: const Color(0xFFC6A15B)),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Payment Summary
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long_outlined, color: Color(0xFFC6A15B), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Chi tiết thanh toán',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSummaryRow('Tổng tiền hàng', _currencyFormat.format(order.totalAmount)),
              _buildSummaryRow('Phí vận chuyển', 'Miễn phí'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Thành tiền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    _currencyFormat.format(order.totalAmount),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC6A15B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getResolvedThumbnailUrl(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }
    if (clean.startsWith('assets/') || clean.startsWith('images/')) {
      return clean;
    }
    var normalized = clean;
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith('Img_Product/')) {
      normalized = 'Img_Product/$normalized';
    }
    return 'https://qkweoptutabbzulsrpas.supabase.co/storage/v1/object/public/Img_products/$normalized';
  }

  Widget _buildItemRow(BuildContext context, OrderItemModel item) {
    final resolvedThumbnail = item.thumbnail != null ? _getResolvedThumbnailUrl(item.thumbnail!) : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: resolvedThumbnail.isNotEmpty
                  ? (resolvedThumbnail.startsWith('http') || resolvedThumbnail.startsWith('https')
                      ? Image.network(
                          resolvedThumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.grey),
                        )
                      : Image.asset(
                          resolvedThumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.grey),
                        ))
                  : const Icon(Icons.image_not_supported, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName ?? 'Sản phẩm',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 4),
                if (item.color != null || item.size != null)
                  Text(
                    'Phân loại: ${[item.color, item.size].where((e) => e != null && e.isNotEmpty).join(', ')}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _currencyFormat.format(item.priceAtPurchase),
                      style: const TextStyle(color: Color(0xFFC6A15B), fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'x${item.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isCopyable = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
                  ),
                ),
                if (isCopyable) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value.replaceAll('#', '')));
                      AppNotifications.showSuccessSnackBar(context, 'Đã sao chép mã đơn hàng');
                    },
                    child: const Icon(Icons.copy, size: 16, color: Color(0xFFC6A15B)),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
