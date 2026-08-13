import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/market/market_klines_api.dart';
import '../../domain/market/curated_symbols.dart';
import '../../features/alerts/alert_feature.dart';
import '../../features/market/market_state.dart';
import '../../features/watchlist/watchlist_feature.dart';

class CurrencyDetailScreen extends StatefulWidget {
  const CurrencyDetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  State<CurrencyDetailScreen> createState() => _CurrencyDetailScreenState();
}

class _CurrencyDetailScreenState extends State<CurrencyDetailScreen> {
  List<ClosePoint> _history = [];
  bool _loading = true;

  bool _initialized = false;

  // См. price_chart_card.dart — _load() читает AppScope.of(context),
  // поэтому первый вызов должен быть в didChangeDependencies(), не в
  // initState().
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    final klinesApi = AppScope.of(context).marketKlinesApi;
    try {
      final closes = await klinesApi.fetchRecentCloses(
        widget.symbol,
        limit: 48,
      );
      if (!mounted) return;
      setState(() {
        _history = closes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(symbolLabel(widget.symbol)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              HelmSelector<MarketState, Never, Ticker?>(
                deps.marketFeature,
                selector: (s) => s.tickerOf(widget.symbol),
                builder: (context, ticker) {
                  final color = (ticker?.isUp ?? true)
                      ? AppColors.up
                      : AppColors.down;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ticker == null ? '—' : '\$${formatPrice(ticker.price)}',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (ticker != null) ...[
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              formatPercent(ticker.changePercent24h),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 220,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _history.length < 2
                        ? const Center(
                            child: Text(
                              'Собираем котировки…',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        : _DetailChart(points: _history),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              HelmSelector<MarketState, Never, Ticker?>(
                deps.marketFeature,
                selector: (s) => s.tickerOf(widget.symbol),
                builder: (context, ticker) => ticker == null
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'Хай 24ч',
                              value: '\$${formatPrice(ticker.high24h)}',
                            ),
                          ),
                          Expanded(
                            child: _StatTile(
                              label: 'Лоу 24ч',
                              value: '\$${formatPrice(ticker.low24h)}',
                            ),
                          ),
                          Expanded(
                            child: _StatTile(
                              label: 'Объём 24ч',
                              value: formatCompactUsd(ticker.volumeQuote24h),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Card(
                child: HelmSelector<WatchlistState, Never, bool>(
                  deps.watchlistFeature,
                  selector: (s) => s.contains(widget.symbol),
                  builder: (context, isWatched) => SwitchListTile(
                    title: const Text('В избранном'),
                    value: isWatched,
                    onChanged: (_) => deps.watchlistFeature.dispatchSync(
                      ToggleWatchCommand(widget.symbol),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Порог алерта',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      HelmSelector<MarketState, Never, double?>(
                        deps.marketFeature,
                        selector: (s) => s.priceOf(widget.symbol),
                        builder: (context, currentPrice) =>
                            HelmSelector<AlertState, AlertEffect, double?>(
                              deps.alertFeature,
                              selector: (s) => s.thresholdOf(widget.symbol),
                              builder: (context, threshold) {
                                // ВАЖНО: anchor берётся от ТЕКУЩЕЙ РЫНОЧНОЙ ЦЕНЫ, а не
                                // от threshold. Раньше было наоборот — и слайдер сам
                                // менял свой же диапазон при каждом драге (порог
                                // меняется → max пересчитывается от нового порога →
                                // позиция скачет), из-за чего казалось, что он не
                                // реагирует на перетаскивание. currentPrice в момент
                                // драга не меняется, поэтому max стабилен.
                                final anchor = currentPrice ?? threshold ?? 1;
                                final max = anchor <= 0 ? 1.0 : anchor * 2;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatPrice(threshold ?? 0),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Slider(
                                      min: 0,
                                      max: max,
                                      value: (threshold ?? 0).clamp(0, max),
                                      onChanged: (v) =>
                                          deps.alertFeature.dispatchSync(
                                            SetThresholdCommand(
                                              widget.symbol,
                                              v,
                                            ),
                                          ),
                                    ),
                                  ],
                                );
                              },
                            ),
                      ),
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

class _DetailChart extends StatelessWidget {
  const _DetailChart({required this.points});
  final List<ClosePoint> points;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.close).toList();
    final isUp = values.last >= values.first;
    final color = isUp ? AppColors.up : AppColors.down;
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1e-9
        ? (maxY.abs() * 0.05 + 1)
        : (maxY - minY) * 0.12;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
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
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.28),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}
