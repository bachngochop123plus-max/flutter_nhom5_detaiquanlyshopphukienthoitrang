import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/base_screen.dart';
import 'admin_order_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level constants
// ─────────────────────────────────────────────────────────────────────────────

const _kOrderStatuses = [
  (null, 'Tất cả'),
  ('pending', 'Chờ xử lý'),
  ('processing', 'Đang xử lý'),
  ('shipped', 'Đang giao'),
  ('delivered', 'Đã giao'),
  ('cancelled', 'Đã huỷ'),
];

enum _FilterMode { day, month, year }

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _error;

  // ── Filter state
  _FilterMode _filterMode = _FilterMode.day;

  // Day mode
  DateTime? _selectedDay;

  // Month mode
  int? _selectedMonth;
  int? _selectedMonthYear;

  // Year mode
  int? _selectedYear;

  // Status filter
  String? _statusFilter;

  DateTime? get _fromDate {
    switch (_filterMode) {
      case _FilterMode.day:
        if (_selectedDay == null) return null;
        return DateTime(
            _selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      case _FilterMode.month:
        if (_selectedMonth == null || _selectedMonthYear == null) return null;
        return DateTime(_selectedMonthYear!, _selectedMonth!, 1);
      case _FilterMode.year:
        if (_selectedYear == null) return null;
        return DateTime(_selectedYear!, 1, 1);
    }
  }

  DateTime? get _toDate {
    switch (_filterMode) {
      case _FilterMode.day:
        if (_selectedDay == null) return null;
        return DateTime(
            _selectedDay!.year, _selectedDay!.month, _selectedDay!.day, 23, 59, 59);
      case _FilterMode.month:
        if (_selectedMonth == null || _selectedMonthYear == null) return null;
        final lastDay = DateTime(_selectedMonthYear!, _selectedMonth! + 1, 0);
        return DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
      case _FilterMode.year:
        if (_selectedYear == null) return null;
        return DateTime(_selectedYear!, 12, 31, 23, 59, 59);
    }
  }

  bool get _hasFilter =>
      _selectedDay != null ||
      (_selectedMonth != null && _selectedMonthYear != null) ||
      _selectedYear != null;

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

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
      List<OrderModel> orders;

      if (_usesSupabase) {
        orders = await _fetchOrdersFromSupabase();
      } else {
        final rows =
            await _db.getAdminOrders(from: _fromDate, to: _toDate);
        orders = rows.map(OrderModel.fromMap).toList();
      }

      if (_statusFilter != null) {
        orders = orders.where((o) => o.status == _statusFilter).toList();
      }
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Lấy đơn hàng trực tiếp từ Supabase (join users để có tên khách hàng)
  Future<List<OrderModel>> _fetchOrdersFromSupabase() async {
    final client = Supabase.instance.client;

    // Build query — filters MUST come before .order()
    var q = client
        .from('orders')
        .select('*');

    if (_fromDate != null) {
      q = q.gte('order_date', _fromDate!.toIso8601String());
    }
    if (_toDate != null) {
      q = q.lte('order_date', _toDate!.toIso8601String());
    }

    final rows =
        await q.order('order_date', ascending: false) as List<dynamic>;

    return rows.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);

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

      final userId = safeInt(row['user_id']);

      return OrderModel(
        id: safeInt(row['id']),
        userId: userId.toString(),
        orderDate: DateTime.tryParse(row['order_date']?.toString() ?? '') ?? DateTime.now(),
        totalAmount: safeDouble(row['total_amount']),
        status: row['status']?.toString() ?? 'pending',
        paymentStatus: row['payment_status']?.toString() ?? 'unpaid',
        shippingAddress: row['shipping_address']?.toString() ?? '',
        paymentMethod: row['payment_method']?.toString(),
        customerName: 'Khách hàng #$userId',
      );
    }).toList();
  }

  void _clearFilter() {
    setState(() {
      _selectedDay = null;
      _selectedMonth = null;
      _selectedMonthYear = null;
      _selectedYear = null;
    });
    _loadOrders();
  }

  double get _totalAmount =>
      _orders.fold(0, (sum, o) => sum + o.totalAmount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFmt = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

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
          // ── Filter panel
          _FilterPanel(
            filterMode: _filterMode,
            selectedDay: _selectedDay,
            selectedMonth: _selectedMonth,
            selectedMonthYear: _selectedMonthYear,
            selectedYear: _selectedYear,
            statusFilter: _statusFilter,
            hasFilter: _hasFilter,
            onModeChanged: (mode) {
              setState(() {
                _filterMode = mode;
                _selectedDay = null;
                _selectedMonth = null;
                _selectedMonthYear = null;
                _selectedYear = null;
              });
            },
            onDaySelected: (day) {
              setState(() => _selectedDay = day);
              _loadOrders();
            },
            onMonthSelected: (month, year) {
              setState(() {
                _selectedMonth = month;
                _selectedMonthYear = year;
              });
              _loadOrders();
            },
            onYearSelected: (year) {
              setState(() => _selectedYear = year);
              _loadOrders();
            },
            onStatusChanged: (s) {
              setState(() => _statusFilter = s);
              _loadOrders();
            },
            onClear: _clearFilter,
          ),

          // ── Summary bar (when has filter result)
          if (!_isLoading && _orders.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color:
                  AppColors.luxuryGold.withValues(alpha: 0.06),
              child: Row(
                children: [
                  Text(
                    '${_orders.length} đơn hàng',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.luxuryGold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tổng: ${currencyFmt.format(_totalAmount)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.luxuryGold,
                    ),
                  ),
                ],
              ),
            ),

          // ── Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.luxuryGold,
                    ),
                  )
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _loadOrders)
                    : _orders.isEmpty
                        ? _EmptyView(
                            hasFilter: _hasFilter,
                            onClear: _clearFilter,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => _OrderCard(
                              order: _orders[index],
                              dateFmt: _dateFmt,
                              currencyFmt: currencyFmt,
                              onTap: () => _openDetail(_orders[index]),
                            ),
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
// Filter panel
// ─────────────────────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filterMode,
    required this.selectedDay,
    required this.selectedMonth,
    required this.selectedMonthYear,
    required this.selectedYear,
    required this.statusFilter,
    required this.hasFilter,
    required this.onModeChanged,
    required this.onDaySelected,
    required this.onMonthSelected,
    required this.onYearSelected,
    required this.onStatusChanged,
    required this.onClear,
  });

  final _FilterMode filterMode;
  final DateTime? selectedDay;
  final int? selectedMonth;
  final int? selectedMonthYear;
  final int? selectedYear;
  final String? statusFilter;
  final bool hasFilter;
  final void Function(_FilterMode) onModeChanged;
  final void Function(DateTime) onDaySelected;
  final void Function(int month, int year) onMonthSelected;
  final void Function(int) onYearSelected;
  final void Function(String?) onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.luxuryGold.withValues(alpha: 0.15),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode tabs
          Row(
            children: [
              _ModeTab(
                label: 'Theo ngày',
                icon: Icons.today_rounded,
                isSelected: filterMode == _FilterMode.day,
                onTap: () => onModeChanged(_FilterMode.day),
              ),
              const SizedBox(width: 8),
              _ModeTab(
                label: 'Theo tháng',
                icon: Icons.calendar_month_rounded,
                isSelected: filterMode == _FilterMode.month,
                onTap: () => onModeChanged(_FilterMode.month),
              ),
              const SizedBox(width: 8),
              _ModeTab(
                label: 'Theo năm',
                icon: Icons.date_range_rounded,
                isSelected: filterMode == _FilterMode.year,
                onTap: () => onModeChanged(_FilterMode.year),
              ),
              if (hasFilter) ...[
                const Spacer(),
                IconButton(
                  tooltip: 'Xóa bộ lọc',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.filter_alt_off_rounded,
                    color: AppColors.danger,
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        AppColors.danger.withValues(alpha: 0.1),
                    minimumSize: const Size(34, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Picker row
          Row(
            children: [
              Expanded(
                child: _buildPicker(context),
              ),
              const SizedBox(width: 10),
              // Status filter
              Expanded(
                child: _buildStatusDropdown(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    switch (filterMode) {
      case _FilterMode.day:
        return _DayPicker(
          selected: selectedDay,
          onSelected: onDaySelected,
        );
      case _FilterMode.month:
        return _MonthPicker(
          selectedMonth: selectedMonth,
          selectedYear: selectedMonthYear,
          onSelected: onMonthSelected,
        );
      case _FilterMode.year:
        return _YearPicker(
          selected: selectedYear,
          onSelected: onYearSelected,
        );
    }
  }

  Widget _buildStatusDropdown(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String?>(
      value: statusFilter,
      isDense: true,
      decoration: InputDecoration(
        labelText: 'Trạng thái',
        labelStyle: theme.textTheme.bodySmall,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.luxuryGold.withValues(alpha: 0.25),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.luxuryGold.withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.luxuryGold),
        ),
      ),
      items: _kOrderStatuses
          .map((entry) => DropdownMenuItem<String?>(
                value: entry.$1,
                child: Text(
                  entry.$2,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onStatusChanged,
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.luxuryGold
              : AppColors.luxuryGold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppColors.luxuryGold,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.luxuryGold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Day picker
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.selected, required this.onSelected});

  final DateTime? selected;
  final void Function(DateTime) onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? DateFormat('dd/MM/yyyy').format(selected!)
        : 'Chọn ngày';

    return _PickerButton(
      label: label,
      icon: Icons.calendar_today_rounded,
      hasValue: selected != null,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          helpText: 'Chọn ngày',
          cancelText: 'Hủy',
          confirmText: 'Chọn',
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppColors.luxuryGold,
                onPrimary: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onSelected(picked);
      },
    );
  }
}

// ── Month picker (dropdown style)
class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.selectedMonth,
    required this.selectedYear,
    required this.onSelected,
  });

  final int? selectedMonth;
  final int? selectedYear;
  final void Function(int month, int year) onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = List.generate(6, (i) => now.year - i);
    final months = List.generate(12, (i) => i + 1);
    final currentYear = selectedYear ?? now.year;
    final currentMonth = selectedMonth ?? now.month;

    return Row(
      children: [
        Expanded(
          child: _CompactDropdown<int>(
            label: 'Tháng',
            value: selectedMonth,
            items: months
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text('Tháng $m'),
                    ))
                .toList(),
            onChanged: (m) {
              if (m != null) onSelected(m, currentYear);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactDropdown<int>(
            label: 'Năm',
            value: selectedYear,
            items: years
                .map((y) => DropdownMenuItem(
                      value: y,
                      child: Text('$y'),
                    ))
                .toList(),
            onChanged: (y) {
              if (y != null) onSelected(currentMonth, y);
            },
          ),
        ),
      ],
    );
  }
}

// ── Year picker
class _YearPicker extends StatelessWidget {
  const _YearPicker({required this.selected, required this.onSelected});

  final int? selected;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = List.generate(6, (i) => now.year - i);

    return _CompactDropdown<int>(
      label: 'Chọn năm',
      value: selected,
      items: years
          .map((y) => DropdownMenuItem(value: y, child: Text('Năm $y')))
          .toList(),
      onChanged: (y) {
        if (y != null) onSelected(y);
      },
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodySmall,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.luxuryGold.withValues(alpha: 0.25),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.luxuryGold.withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.luxuryGold),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.label,
    required this.icon,
    required this.hasValue,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasValue
              ? AppColors.luxuryGold.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          border: Border.all(
            color: hasValue
                ? AppColors.luxuryGold
                : AppColors.luxuryGold.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: AppColors.luxuryGold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hasValue
                      ? AppColors.luxuryGold
                      : AppColors.softGray,
                  fontWeight:
                      hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.luxuryGold,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.dateFmt,
    required this.currencyFmt,
    required this.onTap,
  });

  final OrderModel order;
  final DateFormat dateFmt;
  final NumberFormat currencyFmt;
  final VoidCallback onTap;

  (Color, String) _statusInfo() {
    switch (order.status) {
      case 'delivered':
        return (AppColors.success, 'Đã giao');
      case 'shipped':
        return (const Color(0xFF1A73E8), 'Đang giao');
      case 'processing':
        return (AppColors.luxuryGold, 'Đang xử lý');
      case 'cancelled':
        return (AppColors.danger, 'Đã huỷ');
      default:
        return (AppColors.softGray, 'Chờ xử lý');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusColor, statusLabel) = _statusInfo();

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.luxuryGold.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          AppColors.luxuryGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${order.id}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.luxuryGold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerName ?? 'Khách hàng #${order.userId}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Details
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    text: dateFmt.format(order.orderDate),
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.payments_outlined,
                    text: currencyFmt.format(order.totalAmount),
                    bold: true,
                    color: AppColors.luxuryGold,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _InfoChip(
                icon: Icons.location_on_outlined,
                text: order.shippingAddress,
                maxLines: 1,
              ),
              const SizedBox(height: 10),

              // Arrow
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Xem chi tiết →',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.luxuryGold,
                    fontWeight: FontWeight.w600,
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.text,
    this.bold = false,
    this.color,
    this.maxLines,
  });

  final IconData icon;
  final String text;
  final bool bold;
  final Color? color;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 13,
          color: color ?? AppColors.softGray,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow:
                maxLines != null ? TextOverflow.ellipsis : null,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight:
                  bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty & Error
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
            size: 64,
            color: AppColors.luxuryGold.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter
                ? 'Không có đơn hàng trong khoảng thời gian này'
                : 'Chưa có đơn hàng nào',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.softGray),
            textAlign: TextAlign.center,
          ),
          if (hasFilter) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Xóa bộ lọc'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.luxuryGold,
                side: const BorderSide(color: AppColors.luxuryGold),
              ),
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
            const Icon(Icons.error_outline_rounded,
                size: 56, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              'Có lỗi khi tải đơn hàng',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(error,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.luxuryGold),
            ),
          ],
        ),
      ),
    );
  }
}
