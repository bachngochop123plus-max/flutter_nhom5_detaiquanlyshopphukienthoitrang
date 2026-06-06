import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/database_helper.dart';
import '../../../../core/widgets/base_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _DayRevenue {
  const _DayRevenue({required this.day, required this.revenue, required this.orders});
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

  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();

  _RevenueStats? _stats;

  // ── Quick range presets
  static const _presets = [
    ('7 ngày', 6),
    ('30 ngày', 29),
    ('90 ngày', 89),
    ('365 ngày', 364),
  ];
  int? _activePreset = 1; // default 30 ngày

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
      final summary = await _db.getRevenueSummary(from: _from, to: _to);
      final byDay = await _db.getRevenueByDay(from: _from, to: _to);
      final topProds = await _db.getTopProductsByRevenue(from: _from, to: _to, limit: 5);
      final byCategory = await _db.getRevenueByCategory(from: _from, to: _to);

      final dayList = byDay.map((r) {
        return _DayRevenue(
          day: DateTime.parse(r['day'] as String),
          revenue: (r['revenue'] as num).toDouble(),
          orders: (r['orders'] as num).toInt(),
        );
      }).toList();

      final prodList = topProds.map((r) {
        return _TopProduct(
          name: r['product_name'] as String? ?? '—',
          totalRevenue: (r['total_revenue'] as num).toDouble(),
          totalQty: (r['total_qty'] as num).toInt(),
        );
      }).toList();

      final catList = byCategory.map((r) {
        return _CategoryRevenue(
          name: r['category_name'] as String? ?? '—',
          revenue: (r['total_revenue'] as num).toDouble(),
          qty: (r['total_qty'] as num).toInt(),
        );
      }).toList();

      setState(() {
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
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Chọn khoảng thời gian',
      cancelText: 'Huỷ',
      confirmText: 'Xác nhận',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: const Color(0xFFC6A15B),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
        _activePreset = null;
      });
      _load();
    }
  }

  void _applyPreset(int days, int index) {
    setState(() {
      _to = DateTime.now();
      _from = _to.subtract(Duration(days: days));
      _activePreset = index;
    });
    _load();
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
          _buildControlBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFC6A15B)),
                  )
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ── Control bar (date picker + presets)
  Widget _buildControlBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range button
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFC6A15B)),
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFC6A15B).withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: Color(0xFFC6A15B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_dateFmt.format(_from)}  →  ${_dateFmt.format(_to)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFB9852E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Color(0xFFC6A15B),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Quick preset chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _presets.asMap().entries.map((entry) {
              final i = entry.key;
              final (label, days) = entry.value;
              final active = _activePreset == i;
              return GestureDetector(
                onTap: () => _applyPreset(days, i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFC6A15B)
                        : const Color(0xFFC6A15B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : const Color(0xFFB9852E),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Main scrollable content
  Widget _buildContent() {
    final s = _stats!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildKpiRow(s),
        const SizedBox(height: 16),
        _buildOrderStatusRow(s),
        const SizedBox(height: 20),
        _buildSectionTitle('Doanh thu theo ngày'),
        const SizedBox(height: 12),
        _buildLineChart(s.byDay),
        const SizedBox(height: 20),
        if (s.topProducts.isNotEmpty) ...[
          _buildSectionTitle('Top 5 sản phẩm bán chạy'),
          const SizedBox(height: 12),
          _buildTopProductsTable(s.topProducts, s.totalRevenue),
          const SizedBox(height: 20),
        ],
        if (s.byCategory.isNotEmpty) ...[
          _buildSectionTitle('Doanh thu theo danh mục'),
          const SizedBox(height: 12),
          _buildCategoryBreakdown(s.byCategory, s.totalRevenue),
          const SizedBox(height: 20),
        ],
        if (s.totalOrders == 0)
          _buildEmptyHint(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF222222),
      ),
    );
  }

  // ── KPI cards row
  Widget _buildKpiRow(_RevenueStats s) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _KpiCard(
            icon: Icons.payments_rounded,
            label: 'Tổng doanh thu',
            value: _currencyFmt.format(s.totalRevenue),
            color: const Color(0xFFC6A15B),
            highlight: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _KpiCard(
            icon: Icons.receipt_long_rounded,
            label: 'Đơn hàng',
            value: '${s.totalOrders}',
            color: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _KpiCard(
            icon: Icons.trending_up_rounded,
            label: 'Trung bình/đơn',
            value: _currencyFmt.format(s.avgOrderValue),
            color: const Color(0xFF2A8A5A),
          ),
        ),
      ],
    );
  }

  // ── Order status breakdown
  Widget _buildOrderStatusRow(_RevenueStats s) {
    return Row(
      children: [
        Expanded(
          child: _StatusChip(
            label: 'Chờ xử lý',
            count: s.pendingCount,
            color: const Color(0xFF8C8C8C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusChip(
            label: 'Đang xử lý',
            count: s.processingCount,
            color: const Color(0xFFB9852E),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusChip(
            label: 'Đang giao',
            count: s.shippedCount,
            color: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusChip(
            label: 'Đã giao',
            count: s.deliveredCount,
            color: const Color(0xFF2D8F6F),
          ),
        ),
      ],
    );
  }

  // ── Line chart
  Widget _buildLineChart(List<_DayRevenue> days) {
    if (days.isEmpty) {
      return _buildChartCard(
        child: const SizedBox(
          height: 180,
          child: Center(
            child: Text(
              'Chưa có dữ liệu trong khoảng thời gian này',
              style: TextStyle(color: Color(0xFF8C8C8C)),
            ),
          ),
        ),
      );
    }

    return _buildChartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: _RevenueLineChart(
              data: days,
              currencyFmt: _currencyFmt,
              dayFmt: _dayFmt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC6A15B).withValues(alpha: 0.15),
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

  // ── Top products table
  Widget _buildTopProductsTable(List<_TopProduct> products, double total) {
    return _buildChartCard(
      child: Column(
        children: products.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final pct = total > 0 ? p.totalRevenue / total : 0.0;
          final colors = [
            const Color(0xFFC6A15B),
            const Color(0xFF1A73E8),
            const Color(0xFF2A8A5A),
            const Color(0xFFB23A48),
            const Color(0xFF7B5EA7),
          ];
          final color = colors[i % colors.length];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
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
                    const SizedBox(width: 10),
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
                    const SizedBox(width: 8),
                    Text(
                      _currencyFmt.format(p.totalRevenue),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 34),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor:
                              color.withValues(alpha: 0.12),
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
                    const SizedBox(width: 8),
                    Text(
                      '(${p.totalQty} sp)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C8C8C),
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

  // ── Category breakdown
  Widget _buildCategoryBreakdown(List<_CategoryRevenue> cats, double total) {
    final palette = [
      const Color(0xFFC6A15B),
      const Color(0xFF1A73E8),
      const Color(0xFF2A8A5A),
      const Color(0xFFB23A48),
      const Color(0xFF7B5EA7),
      const Color(0xFFE67E22),
      const Color(0xFF16A085),
    ];

    return _buildChartCard(
      child: Column(
        children: cats.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final pct = total > 0 ? c.revenue / total : 0.0;
          final color = palette[i % palette.length];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
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
                  width: 44,
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

  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 72,
            color: const Color(0xFFC6A15B).withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          const Text(
            'Chưa có đơn hàng trong khoảng thời gian này',
            style: TextStyle(color: Color(0xFF8C8C8C)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Card
// ─────────────────────────────────────────────────────────────────────────────

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: highlight
            ? LinearGradient(
                colors: [
                  color.withValues(alpha: 0.9),
                  color.withValues(alpha: 0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: highlight ? null : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: highlight ? 0 : 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: highlight ? 0.3 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 22,
            color: highlight ? Colors.white : color,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: highlight ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: highlight
                  ? Colors.white.withValues(alpha: 0.85)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status chip
// ─────────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue line chart (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueLineChart extends StatelessWidget {
  const _RevenueLineChart({
    required this.data,
    required this.currencyFmt,
    required this.dayFmt,
  });

  final List<_DayRevenue> data;
  final NumberFormat currencyFmt;
  final DateFormat dayFmt;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LineChartPainter(
            data: data,
            currencyFmt: currencyFmt,
            dayFmt: dayFmt,
            lineColor: const Color(0xFFC6A15B),
            fillColor: const Color(0xFFC6A15B).withValues(alpha: 0.12),
            textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF8C8C8C),
              fontSize: 10,
            ),
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.data,
    required this.currencyFmt,
    required this.dayFmt,
    required this.lineColor,
    required this.fillColor,
    this.textStyle,
  });

  final List<_DayRevenue> data;
  final NumberFormat currencyFmt;
  final DateFormat dayFmt;
  final Color lineColor;
  final Color fillColor;
  final TextStyle? textStyle;

  static const _padL = 56.0;
  static const _padR = 12.0;
  static const _padT = 16.0;
  static const _padB = 32.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final chartW = size.width - _padL - _padR;
    final chartH = size.height - _padT - _padB;

    final maxRevenue = data.map((d) => d.revenue).reduce(math.max);
    final safeMax = maxRevenue == 0 ? 1.0 : maxRevenue;

    // ── Grid lines + Y labels
    final gridPaint = Paint()
      ..color = const Color(0xFFC6A15B).withValues(alpha: 0.12)
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

      // Y label
      final value = safeMax * i / gridCount;
      final label = _formatShort(value);
      labelPainter
        ..text = TextSpan(text: label, style: textStyle)
        ..layout();
      labelPainter.paint(
        canvas,
        Offset(_padL - labelPainter.width - 4, y - labelPainter.height / 2),
      );
    }

    // ── X labels (show at most ~6)
    final step = math.max(1, (data.length / 6).ceil());
    for (var i = 0; i < data.length; i += step) {
      final x = _padL + (chartW * i / (data.length - 1).clamp(1, 9999));
      final label = dayFmt.format(data[i].day);
      labelPainter
        ..text = TextSpan(text: label, style: textStyle)
        ..layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, _padT + chartH + 6),
      );
    }

    // ── Compute points
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = _padL +
          (data.length == 1
              ? chartW / 2
              : chartW * i / (data.length - 1));
      final y = _padT + chartH - (chartH * data[i].revenue / safeMax);
      points.add(Offset(x, y));
    }

    // ── Fill area
    final fillPath = Path()..moveTo(points.first.dx, _padT + chartH);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, _padT + chartH)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // ── Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // Smooth bezier
      final prev = points[i - 1];
      final curr = points[i];
      final ctrlX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(ctrlX, prev.dy, ctrlX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(linePath, linePaint);

    // ── Dots
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final dotBgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final p in points) {
      canvas.drawCircle(p, 5, dotBgPaint);
      canvas.drawCircle(p, 3.5, dotPaint);
    }
  }

  String _formatShort(double value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}tỷ';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(0)}tr';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(0)}k';
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data || old.lineColor != lineColor;
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
            const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFB23A48)),
            const SizedBox(height: 16),
            Text('Có lỗi xảy ra', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC6A15B)),
            ),
          ],
        ),
      ),
    );
  }
}
