import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/base_screen.dart';
import 'admin_order_detail_page.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _dateFormat = DateFormat('dd/MM/yyyy', 'vi');

  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _error;

  DateTime? _fromDate;
  DateTime? _toDate;

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
      final rows = await _db.getAdminOrders(from: _fromDate, to: _toDate);
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

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: (_fromDate != null && _toDate != null)
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      locale: const Locale('vi'),
      helpText: 'Chọn khoảng thời gian',
      cancelText: 'Huỷ',
      confirmText: 'Xác nhận',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFFC6A15B),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _loadOrders();
    }
  }

  void _clearFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = _fromDate != null || _toDate != null;

    return BaseScreen(
      title: 'Quản lý đơn hàng',
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loadOrders,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Column(
        children: [
          // ── Date filter bar ───────────────────────────────────────────────
          _DateFilterBar(
            fromDate: _fromDate,
            toDate: _toDate,
            dateFormat: _dateFormat,
            hasFilter: hasFilter,
            onPickRange: _pickDateRange,
            onClear: _clearFilter,
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFC6A15B),
                    ),
                  )
                : _error != null
                ? _ErrorView(error: _error!, onRetry: _loadOrders)
                : _orders.isEmpty
                ? _EmptyView(hasFilter: hasFilter, onClear: _clearFilter)
                : _OrderList(
                    orders: _orders,
                    dateFormat: _dateFormat,
                    onTap: (order) => _openDetail(order),
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetail(OrderModel order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminOrderDetailPage(orderId: order.id),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.fromDate,
    required this.toDate,
    required this.dateFormat,
    required this.hasFilter,
    required this.onPickRange,
    required this.onClear,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final DateFormat dateFormat;
  final bool hasFilter;
  final VoidCallback onPickRange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFC6A15B).withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            size: 20,
            color: Color(0xFFC6A15B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onPickRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasFilter
                        ? const Color(0xFFC6A15B)
                        : theme.colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: hasFilter
                      ? const Color(0xFFC6A15B).withValues(alpha: 0.08)
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasFilter
                            ? '${dateFormat.format(fromDate!)}  →  ${dateFormat.format(toDate!)}'
                            : 'Lọc theo khoảng thời gian...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hasFilter
                              ? const Color(0xFFB9852E)
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: hasFilter ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Color(0xFFC6A15B),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Xóa bộ lọc',
              onPressed: onClear,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Color(0xFFB23A48),
              ),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFB23A48).withValues(alpha: 0.1),
                minimumSize: const Size(34, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order list
// ─────────────────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.dateFormat,
    required this.onTap,
  });

  final List<OrderModel> orders;
  final DateFormat dateFormat;
  final void Function(OrderModel) onTap;

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderCard(
          order: order,
          dateFormat: dateFormat,
          currencyFormat: currencyFormat,
          onTap: () => onTap(order),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.dateFormat,
    required this.currencyFormat,
    required this.onTap,
  });

  final OrderModel order;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC6A15B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${order.id}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFB9852E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerName ?? 'Khách hàng #${order.userId}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _OrderStatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Info rows
              _InfoRow(
                icon: Icons.access_time_rounded,
                label: 'Ngày đặt',
                value: dateFormat.format(order.orderDate),
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.payments_outlined,
                label: 'Tổng tiền',
                value: currencyFormat.format(order.totalAmount),
                valueColor: const Color(0xFFB9852E),
                valueBold: true,
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.credit_card_rounded,
                label: 'Thanh toán',
                value: order.paymentStatusLabel,
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Địa chỉ',
                value: order.shippingAddress,
                maxLines: 1,
              ),

              const SizedBox(height: 12),

              // Footer: view detail button
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC6A15B).withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFFB9852E),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Xem chi tiết'),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});

  final String status;

  Color _bgColor() {
    switch (status) {
      case 'delivered':
        return const Color(0xFF2D8F6F);
      case 'shipped':
        return const Color(0xFF1A73E8);
      case 'processing':
        return const Color(0xFFB9852E);
      case 'cancelled':
        return const Color(0xFFB23A48);
      default: // pending
        return const Color(0xFF8C8C8C);
    }
  }

  String _label() {
    switch (status) {
      case 'pending':
        return 'Chờ xử lý';
      case 'processing':
        return 'Đang xử lý';
      case 'shipped':
        return 'Đang giao';
      case 'delivered':
        return 'Đã giao';
      case 'cancelled':
        return 'Đã huỷ';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.maxLines,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        SizedBox(
          width: 85,
          child: Text(
            '$label:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: maxLines != null ? TextOverflow.ellipsis : null,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty & Error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.hasFilter, required this.onClear});

  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
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
            hasFilter
                ? 'Không có đơn hàng trong khoảng thời gian này'
                : 'Chưa có đơn hàng nào',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (hasFilter) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ],
      ),
    );
  }
}

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
            const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFB23A48)),
            const SizedBox(height: 16),
            Text(
              'Có lỗi xảy ra khi tải đơn hàng',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
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
