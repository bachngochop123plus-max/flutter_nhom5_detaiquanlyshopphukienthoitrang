import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/base_screen.dart';

class AdminOrderDetailPage extends StatefulWidget {
  const AdminOrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  State<AdminOrderDetailPage> createState() => _AdminOrderDetailPageState();
}

class _AdminOrderDetailPageState extends State<AdminOrderDetailPage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _dateTimeFormat = DateFormat('HH:mm - dd/MM/yyyy');
  final _currencyFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  OrderModel? _order;
  bool _isLoading = true;
  String? _error;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_usesSupabase) {
        final order = await _fetchOrderFromSupabase(widget.orderId);
        if (order == null) {
          setState(() {
            _error = 'Không tìm thấy đơn hàng #${widget.orderId}';
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _order = order;
          _isLoading = false;
        });
      } else {
        final raw = await _db.getOrderWithItems(widget.orderId);
        if (raw == null) {
          setState(() {
            _error = 'Không tìm thấy đơn hàng #${widget.orderId}';
            _isLoading = false;
          });
          return;
        }
        final itemRaws = raw['order_items'];
        final List<OrderItemModel> items;
        if (itemRaws is List<Map<String, Object?>>) {
          items = itemRaws.map(OrderItemModel.fromMap).toList();
        } else if (itemRaws is List) {
          items = itemRaws
              .map((e) => OrderItemModel.fromMap(
                  Map<String, Object?>.from(e as Map)))
              .toList();
        } else {
          items = [];
        }
        setState(() {
          _order = OrderModel.fromMap(raw).copyWith(items: items);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Lấy chi tiết đơn hàng từ Supabase (kèm items, variant, product)
  Future<OrderModel?> _fetchOrderFromSupabase(int orderId) async {
    final client = Supabase.instance.client;

    // Fetch order without joining users
    final orderRows = await client
        .from('orders')
        .select('*')
        .eq('id', orderId)
        .limit(1) as List<dynamic>;

    if (orderRows.isEmpty) return null;
    final raw = Map<String, dynamic>.from(orderRows.first as Map);

    int safeInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? val.hashCode;
      return 0;
    }

    double safeDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    final userId = safeInt(raw['user_id']);

    final order = OrderModel(
      id: safeInt(raw['id']),
      userId: userId,
      orderDate: DateTime.tryParse(raw['order_date']?.toString() ?? '') ?? DateTime.now(),
      totalAmount: safeDouble(raw['total_amount']),
      status: raw['status']?.toString() ?? 'pending',
      paymentStatus: raw['payment_status']?.toString() ?? 'unpaid',
      shippingAddress: raw['shipping_address']?.toString() ?? '',
      paymentMethod: raw['payment_method']?.toString(),
      customerName: 'Khách hàng #$userId',
    );

    // Fetch items
    final itemRows = await client
        .from('order_items')
        .select(
          'id, order_id, variant_id, quantity, price_at_purchase, '
          'product_variants(color, size, products(name, thumbnail))',
        )
        .eq('order_id', orderId) as List<dynamic>;

    final items = itemRows.map((raw) {
      final r = Map<String, dynamic>.from(raw as Map);
      final variant = r['product_variants'] != null
          ? Map<String, dynamic>.from(r['product_variants'] as Map)
          : <String, dynamic>{};
      final product = variant['products'] != null
          ? Map<String, dynamic>.from(variant['products'] as Map)
          : <String, dynamic>{};

      return OrderItemModel(
        id: safeInt(r['id']),
        orderId: safeInt(r['order_id']),
        variantId: safeInt(r['variant_id']),
        quantity: safeInt(r['quantity']),
        priceAtPurchase: safeDouble(r['price_at_purchase']),
        color: variant['color']?.toString(),
        size: variant['size']?.toString(),
        productName: product['name']?.toString(),
        thumbnail: product['thumbnail']?.toString(),
      );
    }).toList();

    return order.copyWith(items: items);
  }

  Future<void> _changeStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      if (_usesSupabase) {
        await Supabase.instance.client
            .from('orders')
            .update({'status': newStatus})
            .eq('id', widget.orderId);
      } else {
        await _db.updateOrderStatus(widget.orderId, newStatus);
      }
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: const Color(0xFFB23A48),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _changePaymentStatus(String newPaymentStatus) async {
    setState(() => _isUpdating = true);
    try {
      if (_usesSupabase) {
        await Supabase.instance.client
            .from('orders')
            .update({'payment_status': newPaymentStatus})
            .eq('id', widget.orderId);
      } else {
        await _db.updatePaymentStatus(widget.orderId, newPaymentStatus);
      }
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: const Color(0xFFB23A48),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Chi tiết đơn hàng #${widget.orderId}',
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      automaticallyImplyLeading: false,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC6A15B)),
            )
          : _error != null
          ? _ErrorView(error: _error!, onRetry: _loadDetail)
          : _order == null
          ? const SizedBox.shrink()
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final order = _order!;
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header: order id + status
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Đơn hàng #${order.id}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFB9852E),
                          ),
                        ),
                      ),
                      _StatusBadge(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Đặt lúc ${_dateTimeFormat.format(order.orderDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Customer info
            _SectionCard(
              title: 'Thông tin khách hàng',
              icon: Icons.person_outline_rounded,
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Họ và tên',
                    value: order.customerName ?? 'Không rõ',
                  ),
                  if (order.customerEmail != null)
                    _DetailRow(
                        label: 'Email', value: order.customerEmail!),
                  _DetailRow(
                    label: 'Địa chỉ giao hàng',
                    value: order.shippingAddress,
                  ),
                  if (order.paymentMethod != null)
                    _DetailRow(
                      label: 'Phương thức TT',
                      value: order.paymentMethod!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Payment status
            _SectionCard(
              title: 'Trạng thái thanh toán',
              icon: Icons.payments_outlined,
              child: Row(
                children: [
                  _PaymentBadge(paymentStatus: order.paymentStatus),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Cập nhật thanh toán',
                    onSelected: _changePaymentStatus,
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'unpaid',
                        child: Text('Chưa thanh toán'),
                      ),
                      const PopupMenuItem(
                        value: 'paid',
                        child: Text('Đã thanh toán'),
                      ),
                      const PopupMenuItem(
                        value: 'refunded',
                        child: Text('Đã hoàn tiền'),
                      ),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Cập nhật'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB9852E),
                        side: const BorderSide(
                            color: Color(0xFFC6A15B)),
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Products
            _SectionCard(
              title: 'Sản phẩm đã đặt (${order.items.length})',
              icon: Icons.shopping_bag_outlined,
              child: order.items.isEmpty
                  ? Text(
                      'Không có sản phẩm nào',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      children: order.items
                          .map(
                            (item) => _OrderItemTile(
                              item: item,
                              currencyFormat: _currencyFormat,
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 14),

            // Total
            _SectionCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_outlined,
                    color: Color(0xFFC6A15B),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Tổng cộng',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _currencyFormat.format(order.totalAmount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB9852E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Status update
            _SectionCard(
              title: 'Cập nhật trạng thái đơn hàng',
              icon: Icons.update_rounded,
              child: _StatusSelector(
                currentStatus: order.status,
                onChanged: _changeStatus,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),

        // Loading overlay
        if (_isUpdating)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFC6A15B),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title, this.icon});

  final Widget child;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFC6A15B).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: const Color(0xFFC6A15B)),
                  const SizedBox(width: 8),
                ],
                Text(
                  title!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB9852E),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail row
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order item tile
// ─────────────────────────────────────────────────────────────────────────────

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile(
      {required this.item, required this.currencyFormat});

  final OrderItemModel item;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage =
        item.thumbnail != null && item.thumbnail!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: item.thumbnail!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          _PlaceholderImage(),
                    )
                  : _PlaceholderImage(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName ?? 'Sản phẩm #${item.variantId}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.color != null || item.size != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (item.color != null)
                          _VariantChip(label: item.color!),
                        if (item.size != null)
                          _VariantChip(label: item.size!),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'x${item.quantity}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      currencyFormat.format(item.lineTotal),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB9852E),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${currencyFormat.format(item.priceAtPurchase)} / sản phẩm',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFC6A15B).withValues(alpha: 0.1),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFFC6A15B),
        size: 28,
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFC6A15B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFB9852E),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Badges
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  (Color, String) _info() {
    switch (status) {
      case 'delivered':
        return (const Color(0xFF2D8F6F), 'Đã giao');
      case 'shipped':
        return (const Color(0xFF1A73E8), 'Đang giao');
      case 'processing':
        return (const Color(0xFFB9852E), 'Đang xử lý');
      case 'cancelled':
        return (const Color(0xFFB23A48), 'Đã huỷ');
      default:
        return (const Color(0xFF8C8C8C), 'Chờ xử lý');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _info();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.paymentStatus});

  final String paymentStatus;

  (Color, String) _info() {
    switch (paymentStatus) {
      case 'paid':
        return (const Color(0xFF2D8F6F), 'Đã thanh toán');
      case 'refunded':
        return (const Color(0xFF1A73E8), 'Đã hoàn tiền');
      default:
        return (const Color(0xFFB23A48), 'Chưa thanh toán');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _info();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status selector
// ─────────────────────────────────────────────────────────────────────────────

const _kStatuses = [
  ('pending', 'Chờ xử lý', Color(0xFF8C8C8C)),
  ('processing', 'Đang xử lý', Color(0xFFB9852E)),
  ('shipped', 'Đang giao', Color(0xFF1A73E8)),
  ('delivered', 'Đã giao', Color(0xFF2D8F6F)),
  ('cancelled', 'Đã huỷ', Color(0xFFB23A48)),
];

class _StatusSelector extends StatelessWidget {
  const _StatusSelector({
    required this.currentStatus,
    required this.onChanged,
  });

  final String currentStatus;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kStatuses.map((entry) {
        final (value, label, color) = entry;
        final isSelected = currentStatus == value;
        return GestureDetector(
          onTap: isSelected ? null : () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? color
                  : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Color(0xFFB23A48),
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC6A15B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
