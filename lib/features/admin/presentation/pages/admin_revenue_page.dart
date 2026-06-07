import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/database_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/base_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter mode
// ─────────────────────────────────────────────────────────────────────────────

enum _FilterMode { day, month, year, range }

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _DayRevenue {
  const _DayRevenue({
    required this.day,
    required this.revenue,
    required this.orders,
  });
  final DateTime day;
  final double revenue;
  final int orders;
}

class _TopProduct {
  const _TopProduct({
    required this.name,
    required this.totalRevenue,
    required this.totalQty,
  });
  final String name;
  final double totalRevenue;
  final int totalQty;
}

class _CategoryRevenue {
  const _CategoryRevenue({
    required this.name,
    required this.revenue,
    required this.qty,
  });
  final String name;
  final double revenue;
  final int qty;
}

class _RevenueStats {
  const _RevenueStats({
    required this.totalRevenue,
    required this.totalOrders,
    required this.avgOrderValue,
    required this.deliveredCount,
    required this.processingCount,
    required this.shippedCount,
    required this.pendingCount,
    required this.byDay,
    required this.topProducts,
    required this.byCategory,
  });

  final double totalRevenue;
  final int totalOrders;
  final double avgOrderValue;
  final int deliveredCount;
  final int processingCount;
  final int shippedCount;
  final int pendingCount;
  final List<_DayRevenue> byDay;
  final List<_TopProduct> topProducts;
  final List<_CategoryRevenue> byCategory;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class AdminRevenuePage extends StatefulWidget {
  const AdminRevenuePage({super.key});

  @override
  State<AdminRevenuePage> createState() => _AdminRevenuePageState();
}

class _AdminRevenuePageState extends State<AdminRevenuePage> {
  final _db = GetIt.instance<DatabaseHelper>();
  final _currencyFmt = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _dayFmt = DateFormat('dd/MM');

  bool _loading = true;
  String? _error;
  _RevenueStats? _stats;

  // ── Filter state
  _FilterMode _filterMode = _FilterMode.month;

  // Day
  DateTime? _selectedDay;
  // Month
  int _selectedMonth = DateTime.now().month;
  int _selectedMonthYear = DateTime.now().year;
  // Year
  int _selectedYear = DateTime.now().year;
  // Range
  DateTime _rangeFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _rangeTo = DateTime.now();

  DateTime? get _fromDate {
    switch (_filterMode) {
      case _FilterMode.day:
        if (_selectedDay == null) return null;
        return DateTime(
            _selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      case _FilterMode.month:
        return DateTime(_selectedMonthYear, _selectedMonth, 1);
      case _FilterMode.year:
        return DateTime(_selectedYear, 1, 1);
      case _FilterMode.range:
        return DateTime(_rangeFrom.year, _rangeFrom.month, _rangeFrom.day);
    }
  }

  DateTime? get _toDate {
    switch (_filterMode) {
      case _FilterMode.day:
        if (_selectedDay == null) return null;
        return DateTime(_selectedDay!.year, _selectedDay!.month,
            _selectedDay!.day, 23, 59, 59);
      case _FilterMode.month:
        final lastDay =
            DateTime(_selectedMonthYear, _selectedMonth + 1, 0);
        return DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
      case _FilterMode.year:
        return DateTime(_selectedYear, 12, 31, 23, 59, 59);
      case _FilterMode.range:
        return DateTime(
            _rangeTo.year, _rangeTo.month, _rangeTo.day, 23, 59, 59);
    }
  }

  String get _filterLabel {
    switch (_filterMode) {
      case _FilterMode.day:
        return _selectedDay == null
            ? 'Chưa chọn ngày'
            : _dateFmt.format(_selectedDay!);
      case _FilterMode.month:
        return 'Tháng $_selectedMonth/$_selectedMonthYear';
      case _FilterMode.year:
        return 'Năm $_selectedYear';
      case _FilterMode.range:
        return '${_dateFmt.format(_rangeFrom)} – ${_dateFmt.format(_rangeTo)}';
    }
  }

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_usesSupabase) {
        await _loadFromSupabase();
      } else {
        await _loadFromSqlite();
      }
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFromSqlite() async {
    final from = _fromDate;
      final to = _toDate;

      final summary = await _db.getRevenueSummary(from: from, to: to);
      final byDay = await _db.getRevenueByDay(from: from, to: to);
      final topProds =
          await _db.getTopProductsByRevenue(from: from, to: to, limit: 5);
      final byCategory = await _db.getRevenueByCategory(from: from, to: to);

      final dayList = byDay.map((r) => _DayRevenue(
            day: DateTime.parse(r['day'] as String),
            revenue: (r['revenue'] as num).toDouble(),
            orders: (r['orders'] as num).toInt(),
          )).toList();

      final prodList = topProds.map((r) => _TopProduct(
            name: r['product_name'] as String? ?? '—',
            totalRevenue: (r['total_revenue'] as num).toDouble(),
            totalQty: (r['total_qty'] as num).toInt(),
          )).toList();

      final catList = byCategory.map((r) => _CategoryRevenue(
            name: r['category_name'] as String? ?? '—',
            revenue: (r['total_revenue'] as num).toDouble(),
            qty: (r['total_qty'] as num).toInt(),
          )).toList();

      _stats = _RevenueStats(
        totalRevenue: (summary['total_revenue'] as num? ?? 0).toDouble(),
        totalOrders: (summary['total_orders'] as num? ?? 0).toInt(),
        avgOrderValue: (summary['avg_order_value'] as num? ?? 0).toDouble(),
        deliveredCount: (summary['delivered_count'] as num? ?? 0).toInt(),
        processingCount: (summary['processing_count'] as num? ?? 0).toInt(),
        shippedCount: (summary['shipped_count'] as num? ?? 0).toInt(),
        pendingCount: (summary['pending_count'] as num? ?? 0).toInt(),
        byDay: dayList,
        topProducts: prodList,
        byCategory: catList,
      );
  }

  Future<void> _loadFromSupabase() async {
    final client = Supabase.instance.client;

    var q = client
        .from('orders')
        .select(
          'id, total_amount, status, order_date, '
          'order_items(quantity, price_at_purchase, '
          'product_variants(products(name, categories(name))))',
        )
        .neq('status', 'cancelled');

    if (_fromDate != null) {
      q = q.gte('order_date', _fromDate!.toIso8601String());
    }
    if (_toDate != null) {
      q = q.lte('order_date', _toDate!.toIso8601String());
    }

    final List<dynamic> rows = await q;

    double totalRevenue = 0;
    int totalOrders = rows.length;
    int delivered = 0, processing = 0, shipped = 0, pending = 0;

    final Map<String, _DayRevenue> byDayMap = {};
    final Map<String, _TopProduct> topProductsMap = {};
    final Map<String, _CategoryRevenue> byCategoryMap = {};

    int safeInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    double safeDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    for (var raw in rows) {
      final o = Map<String, dynamic>.from(raw as Map);

      final dateStr = (o['order_date'] as String?) ?? '';
      final dt = DateTime.tryParse(dateStr) ?? DateTime.now();
      final dayKey = DateFormat('yyyy-MM-dd').format(dt);

      final status = o['status']?.toString() ?? 'pending';
      final totalAmt = safeDouble(o['total_amount']);

      totalRevenue += totalAmt;

      if (status == 'delivered') delivered++;
      else if (status == 'processing') processing++;
      else if (status == 'shipped') shipped++;
      else if (status == 'pending') pending++;

      if (!byDayMap.containsKey(dayKey)) {
        byDayMap[dayKey] = _DayRevenue(
            day: DateTime.parse(dayKey), revenue: 0, orders: 0);
      }
      final curDay = byDayMap[dayKey]!;
      byDayMap[dayKey] = _DayRevenue(
        day: curDay.day,
        revenue: curDay.revenue + totalAmt,
        orders: curDay.orders + 1,
      );

      final items = o['order_items'] as List<dynamic>? ?? [];
      for (var rawItem in items) {
        final i = Map<String, dynamic>.from(rawItem as Map);
        final qty = safeInt(i['quantity']);
        final price = safeDouble(i['price_at_purchase']);
        final itemRev = qty * price;

        final pv = i['product_variants'] != null
            ? Map<String, dynamic>.from(i['product_variants'] as Map)
            : null;
        final p = pv?['products'] != null
            ? Map<String, dynamic>.from(pv!['products'] as Map)
            : null;
        final c = p?['categories'] != null
            ? Map<String, dynamic>.from(p!['categories'] as Map)
            : null;

        final prodName = p?['name']?.toString() ?? '—';
        final catName = c?['name']?.toString() ?? '—';

        if (!topProductsMap.containsKey(prodName)) {
          topProductsMap[prodName] = _TopProduct(
              name: prodName, totalRevenue: 0, totalQty: 0);
        }
        final curP = topProductsMap[prodName]!;
        topProductsMap[prodName] = _TopProduct(
          name: prodName,
          totalRevenue: curP.totalRevenue + itemRev,
          totalQty: curP.totalQty + qty,
        );

        if (!byCategoryMap.containsKey(catName)) {
          byCategoryMap[catName] = _CategoryRevenue(
              name: catName, revenue: 0, qty: 0);
        }
        final curC = byCategoryMap[catName]!;
        byCategoryMap[catName] = _CategoryRevenue(
          name: catName,
          revenue: curC.revenue + itemRev,
          qty: curC.qty + qty,
        );
      }
    }

    final dayList = byDayMap.values.toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    final prodList = topProductsMap.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    final catList = byCategoryMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    _stats = _RevenueStats(
      totalRevenue: totalRevenue,
      totalOrders: totalOrders,
      avgOrderValue: totalOrders > 0 ? totalRevenue / totalOrders : 0,
      deliveredCount: delivered,
      processingCount: processing,
      shippedCount: shipped,
      pendingCount: pending,
      byDay: dayList,
      topProducts: prodList.take(5).toList(),
      byCategory: catList,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Thống kê doanh thu',
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.luxuryGold,
                    ),
                  )
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ── Filter bar
  Widget _buildFilterBar() {
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ModeTab(
                  label: 'Theo ngày',
                  icon: Icons.today_rounded,
                  isSelected: _filterMode == _FilterMode.day,
                  onTap: () {
                    setState(() => _filterMode = _FilterMode.day);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'Theo tháng',
                  icon: Icons.calendar_month_rounded,
                  isSelected: _filterMode == _FilterMode.month,
                  onTap: () {
                    setState(() => _filterMode = _FilterMode.month);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'Theo năm',
                  icon: Icons.date_range_rounded,
                  isSelected: _filterMode == _FilterMode.year,
                  onTap: () {
                    setState(() => _filterMode = _FilterMode.year);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'Khoảng thời gian',
                  icon: Icons.tune_rounded,
                  isSelected: _filterMode == _FilterMode.range,
                  onTap: () {
                    setState(() => _filterMode = _FilterMode.range);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Picker
          _buildPicker(theme),

          // Current filter label
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 14,
                color: AppColors.luxuryGold,
              ),
              const SizedBox(width: 4),
              Text(
                'Đang xem: $_filterLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.luxuryGold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(ThemeData theme) {
    switch (_filterMode) {
      case _FilterMode.day:
        return _buildDayPicker(theme);
      case _FilterMode.month:
        return _buildMonthPicker(theme);
      case _FilterMode.year:
        return _buildYearPicker(theme);
      case _FilterMode.range:
        return _buildRangePicker(theme);
    }
  }

  Widget _buildDayPicker(ThemeData theme) {
    final label = _selectedDay != null
        ? _dateFmt.format(_selectedDay!)
        : 'Chọn ngày...';
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDay ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          helpText: 'Chọn ngày xem doanh thu',
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
        if (picked != null && mounted) {
          setState(() => _selectedDay = picked);
          _load();
        }
      },
      child: _PickerContainer(
        label: label,
        hasValue: _selectedDay != null,
        icon: Icons.calendar_today_rounded,
      ),
    );
  }

  Widget _buildMonthPicker(ThemeData theme) {
    final now = DateTime.now();
    final years = List.generate(6, (i) => now.year - i);
    final months = List.generate(12, (i) => i + 1);

    return Row(
      children: [
        Expanded(
          child: _RevDropdown<int>(
            label: 'Tháng',
            value: _selectedMonth,
            items: months.map((m) => DropdownMenuItem(
              value: m,
              child: Text('Tháng $m'),
            )).toList(),
            onChanged: (m) {
              if (m != null) {
                setState(() => _selectedMonth = m);
                _load();
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RevDropdown<int>(
            label: 'Năm',
            value: _selectedMonthYear,
            items: years.map((y) => DropdownMenuItem(
              value: y,
              child: Text('$y'),
            )).toList(),
            onChanged: (y) {
              if (y != null) {
                setState(() => _selectedMonthYear = y);
                _load();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYearPicker(ThemeData theme) {
    final now = DateTime.now();
    final years = List.generate(6, (i) => now.year - i);

    return _RevDropdown<int>(
      label: 'Chọn năm',
      value: _selectedYear,
      items: years.map((y) => DropdownMenuItem(
        value: y,
        child: Text('Năm $y'),
      )).toList(),
      onChanged: (y) {
        if (y != null) {
          setState(() => _selectedYear = y);
          _load();
        }
      },
    );
  }

  Widget _buildRangePicker(ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          initialDateRange: DateTimeRange(start: _rangeFrom, end: _rangeTo),
          helpText: 'Chọn khoảng thời gian',
          cancelText: 'Hủy',
          confirmText: 'Xác nhận',
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
        if (picked != null && mounted) {
          setState(() {
            _rangeFrom = picked.start;
            _rangeTo = picked.end;
          });
          _load();
        }
      },
      child: _PickerContainer(
        label:
            '${_dateFmt.format(_rangeFrom)}  →  ${_dateFmt.format(_rangeTo)}',
        hasValue: true,
        icon: Icons.date_range_rounded,
      ),
    );
  }

  // ── Content
  Widget _buildContent() {
    final s = _stats!;

    if (s.totalOrders == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 72,
              color: AppColors.luxuryGold.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'Không có dữ liệu trong khoảng thời gian này',
              style: TextStyle(color: AppColors.softGray),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI cards
        _buildKpiRow(s),
        const SizedBox(height: 14),
        // Status breakdown
        _buildStatusRow(s),
        const SizedBox(height: 20),
        // Chart
        _buildSectionHeader('Doanh thu theo ngày'),
        const SizedBox(height: 10),
        _buildChartCard(s.byDay),
        const SizedBox(height: 20),
        // Top products
        if (s.topProducts.isNotEmpty) ...[
          _buildSectionHeader('Top 5 sản phẩm bán chạy'),
          const SizedBox(height: 10),
          _buildTopProducts(s.topProducts, s.totalRevenue),
          const SizedBox(height: 20),
        ],
        // Categories
        if (s.byCategory.isNotEmpty) ...[
          _buildSectionHeader('Doanh thu theo danh mục'),
          const SizedBox(height: 10),
          _buildCategoryBreakdown(s.byCategory, s.totalRevenue),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.luxuryGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiRow(_RevenueStats s) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _KpiCard(
            icon: Icons.payments_rounded,
            label: 'Tổng doanh thu',
            value: _currencyFmt.format(s.totalRevenue),
            color: AppColors.luxuryGold,
            highlight: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _KpiCard(
            icon: Icons.receipt_long_rounded,
            label: 'Số đơn',
            value: '${s.totalOrders}',
            color: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _KpiCard(
            icon: Icons.trending_up_rounded,
            label: 'TB/đơn',
            value: _currencyFmt.format(s.avgOrderValue),
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(_RevenueStats s) {
    return Row(
      children: [
        Expanded(
          child: _StatusMini(
            label: 'Chờ xử lý',
            count: s.pendingCount,
            color: AppColors.softGray,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusMini(
            label: 'Xử lý',
            count: s.processingCount,
            color: AppColors.luxuryGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusMini(
            label: 'Đang giao',
            count: s.shippedCount,
            color: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusMini(
            label: 'Đã giao',
            count: s.deliveredCount,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(List<_DayRevenue> days) {
    return _Card(
      child: days.isEmpty
          ? const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'Chưa có dữ liệu',
                  style: TextStyle(color: AppColors.softGray),
                ),
              ),
            )
          : SizedBox(
              height: 200,
              child: _LineChart(data: days, dayFmt: _dayFmt),
            ),
    );
  }

  Widget _buildTopProducts(List<_TopProduct> products, double total) {
    final colors = [
      AppColors.luxuryGold,
      const Color(0xFF1A73E8),
      AppColors.success,
      AppColors.danger,
      const Color(0xFF7B5EA7),
    ];

    return _Card(
      child: Column(
        children: products.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final pct = total > 0 ? p.totalRevenue / total : 0.0;
          final color = colors[i % colors.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _currencyFmt.format(p.totalRevenue),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const SizedBox(width: 30),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: color.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryBreakdown(
      List<_CategoryRevenue> cats, double total) {
    final palette = [
      AppColors.luxuryGold,
      const Color(0xFF1A73E8),
      AppColors.success,
      AppColors.danger,
      const Color(0xFF7B5EA7),
      const Color(0xFFE67E22),
    ];

    return _Card(
      child: Column(
        children: cats.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final pct = total > 0 ? c.revenue / total : 0.0;
          final color = palette[i % palette.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(pct * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI components
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

class _PickerContainer extends StatelessWidget {
  const _PickerContainer({
    required this.label,
    required this.hasValue,
    required this.icon,
  });

  final String label;
  final bool hasValue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
          Icon(icon, size: 16, color: AppColors.luxuryGold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasValue ? AppColors.luxuryGold : AppColors.softGray,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            color: AppColors.luxuryGold,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _RevDropdown<T> extends StatelessWidget {
  const _RevDropdown({
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
          borderSide:
              const BorderSide(color: AppColors.luxuryGold),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: highlight
            ? LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: highlight ? null : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: highlight ? 0 : 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: highlight ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: highlight ? Colors.white : color),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: highlight ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: highlight
                  ? Colors.white.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMini extends StatelessWidget {
  const _StatusMini({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.luxuryGold.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Line chart
// ─────────────────────────────────────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  const _LineChart({required this.data, required this.dayFmt});

  final List<_DayRevenue> data;
  final DateFormat dayFmt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _LineChartPainter(
          data: data,
          dayFmt: dayFmt,
          lineColor: AppColors.luxuryGold,
          fillColor: AppColors.luxuryGold.withValues(alpha: 0.1),
          textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: AppColors.softGray,
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.data,
    required this.dayFmt,
    required this.lineColor,
    required this.fillColor,
    this.textStyle,
  });

  final List<_DayRevenue> data;
  final DateFormat dayFmt;
  final Color lineColor;
  final Color fillColor;
  final TextStyle? textStyle;

  static const _padL = 60.0;
  static const _padR = 12.0;
  static const _padT = 16.0;
  static const _padB = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final chartW = size.width - _padL - _padR;
    final chartH = size.height - _padT - _padB;
    final maxRevenue = data.map((d) => d.revenue).reduce(math.max);
    final safeMax = maxRevenue == 0 ? 1.0 : maxRevenue;

    final gridPaint = Paint()
      ..color = AppColors.luxuryGold.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    final labelPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    const gridCount = 4;
    for (var i = 0; i <= gridCount; i++) {
      final y = _padT + chartH - (chartH * i / gridCount);
      canvas.drawLine(
        Offset(_padL, y),
        Offset(_padL + chartW, y),
        gridPaint,
      );
      final value = safeMax * i / gridCount;
      labelPainter
        ..text = TextSpan(text: _shortNum(value), style: textStyle)
        ..layout();
      labelPainter.paint(
        canvas,
        Offset(_padL - labelPainter.width - 4, y - labelPainter.height / 2),
      );
    }

    // X labels
    final step = math.max(1, (data.length / 6).ceil());
    for (var i = 0; i < data.length; i += step) {
      final x =
          _padL + (chartW * i / (data.length - 1).clamp(1, 9999));
      final label = dayFmt.format(data[i].day);
      labelPainter
        ..text = TextSpan(text: label, style: textStyle)
        ..layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, _padT + chartH + 4),
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = _padL +
          (data.length == 1 ? chartW / 2 : chartW * i / (data.length - 1));
      final y = _padT + chartH - (chartH * data[i].revenue / safeMax);
      points.add(Offset(x, y));
    }

    // Fill
    final fillPath = Path()..moveTo(points.first.dx, _padT + chartH);
    for (final p in points) fillPath.lineTo(p.dx, p.dy);
    fillPath
      ..lineTo(points.last.dx, _padT + chartH)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final linePath = Path()
      ..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cx = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cx, prev.dy, cx, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Dots
    for (final p in points) {
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.5, Paint()..color = lineColor);
    }
  }

  String _shortNum(double value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}tỷ';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(0)}tr';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(0)}k';
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.data != data;
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
            const Icon(Icons.error_outline_rounded,
                size: 56, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              'Có lỗi khi tải dữ liệu',
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
