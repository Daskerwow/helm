import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/market/market_klines_api.dart';
import '../../../domain/market/curated_symbols.dart';
import '../../../domain/market/ticker.dart';

final class _RangeOption {
  const _RangeOption(this.label, this.interval, this.limit);
  final String label;
  final String interval;
  final int limit;
}

const _ranges = [
  _RangeOption('24ч', '1h', 24),
  _RangeOption('7д', '4h', 42),
  _RangeOption('30д', '1d', 30),
];

/// Центральная карточка дашборда — крупный график цены выбранного актива
/// с реальной историей из REST (`MarketKlinesApi`), а не просто "рыбой".
/// Живая цена сверху донастраивается из тикера через `HelmSelector` в
/// родителе (см. `DashboardScreen`), сюда прилетает уже готовый `Ticker`.
class PriceChartCard extends StatefulWidget {
  const PriceChartCard({
    super.key,
    required this.symbol,
    required this.ticker,
    required this.onSymbolChanged,
  });

  final String symbol;
  final Ticker? ticker;
  final ValueChanged<String> onSymbolChanged;

  @override
  State<PriceChartCard> createState() => _PriceChartCardState();
}

class _PriceChartCardState extends State<PriceChartCard> {
  int _rangeIndex = 0;
  List<ClosePoint> _points = [];
  bool _loading = true;

  bool _initialized = false;

  // _load() читает AppScope.of(context) — это нельзя делать из initState()
  // напрямую (InheritedWidget ещё не готов к чтению в этой фазе жизненного
  // цикла). didChangeDependencies() — правильное место для первого запроса
  // данных, зависящих от context; флаг ниже гарантирует, что грузим только
  // один раз при первом появлении карточки, а не при каждом пересчёте
  // зависимостей.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  @override
  void didUpdateWidget(covariant PriceChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final klinesApi = AppScope.of(context).marketKlinesApi;
    final range = _ranges[_rangeIndex];
    try {
      final points = await klinesApi.fetchRecentCloses(
        widget.symbol,
        interval: range.interval,
        limit: range.limit,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticker = widget.ticker;
    final color = (ticker?.isUp ?? true) ? AppColors.up : AppColors.down;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SymbolPicker(
                        selected: widget.symbol,
                        onChanged: widget.onSymbolChanged,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        ticker == null ? '—' : '\$${formatPrice(ticker.price)}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (ticker != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${formatPercent(ticker.changePercent24h)} за 24ч',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _ranges.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _RangeChip(
                          label: _ranges[i].label,
                          selected: i == _rangeIndex,
                          onTap: () {
                            setState(() => _rangeIndex = i);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _points.length < 2
                  ? const Center(
                      child: Text(
                        'Нет данных',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : _Chart(points: _points, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points, required this.color});
  final List<ClosePoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.close).toList();
    final minY = values.reduce(min);
    final maxY = values.reduce(max);
    final pad = (maxY - minY).abs() < 1e-9
        ? (maxY.abs() * 0.05 + 1)
        : (maxY - minY) * 0.12;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) <= 0 ? 1 : (maxY - minY) / 3,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                formatCompactUsd(value).replaceFirst('\$', ''),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (points.length / 4)
                  .clamp(1, points.length)
                  .floorToDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final t = points[i].time;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceElevated,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '\$${formatPrice(s.y)}',
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.24),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolPicker extends StatelessWidget {
  const _SymbolPicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected,
        dropdownColor: AppColors.surfaceElevated,
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        items: [
          for (final s in curatedSymbols)
            DropdownMenuItem(
              value: s,
              child: Text('${symbolName(s)} · ${symbolTicker(s)}'),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
