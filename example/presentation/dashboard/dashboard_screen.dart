import 'package:flutter/material.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/market/curated_symbols.dart';
import '../widgets/connection_badge.dart';
import 'widgets/asset_row.dart';
import 'widgets/movers_card.dart';
import 'widgets/price_chart_card.dart';
import 'widgets/stat_card.dart';

/// `StatefulHelmWidget` вместо ручной обёртки `HelmSelector` вокруг каждого
/// куска экрана — `feature.select()` читается прямо в `build()`. Нужен
/// именно Stateful-вариант (не [HelmWidget]), потому что помимо реактивных
/// данных фичи здесь есть и обычное локальное состояние экрана —
/// `_selectedSymbol` (какая монета выбрана в большом графике) — то есть
/// ровно тот случай, для которого в докстринге `StatefulHelmWidget` и
/// сделан: "нужен собственный setState/initState/контроллеры анимации".
class DashboardScreen extends StatefulHelmWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedSymbol = curatedSymbols.first;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    // Два разных .select() на ОДНОМ токене (marketFeature) в одном
    // виджете — по докстрингу `HelmFeatureReactive.select` в этом случае
    // обязателен разный `key`, иначе оба вызова делят один биндинг и
    // видят только последний вызванный selector.
    final status = deps.marketFeature.select((s) => s.status, key: #connectionStatus);
    final selectedTicker = deps.marketFeature.select(
      (s) => s.tickerOf(_selectedSymbol),
      key: #selectedTicker,
    );

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Дашборд', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ConnectionBadge(status: status),
                ],
              ),
              const SizedBox(height: 24),
              // HelmComputed — это обычный ChangeNotifier, штатно
              // потребляется через ListenableBuilder (см. докстринг и
              // пример использования в helm_computed.dart), а не через
              // .select() — тот работает только для HelmFeature<S,E>.
              ListenableBuilder(
                listenable: deps.dashboardSummary,
                builder: (context, _) {
                  final summary = deps.dashboardSummary.value;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 760;
                      final cards = [
                        StatCard(
                          icon: Icons.pie_chart_rounded,
                          label: 'Объём торгов 24ч (корзина)',
                          value: formatCompactUsd(summary.totalVolume24h),
                          accent: AppColors.accent,
                        ),
                        StatCard(
                          icon: Icons.star_rounded,
                          label: 'В избранном',
                          value: '${summary.watchedCount} из ${curatedSymbols.length}',
                          accent: AppColors.warning,
                        ),
                        StatCard(
                          icon: Icons.notifications_active_rounded,
                          label: 'Взведено алертов',
                          value: '${summary.armedAlertsCount}',
                          accent: AppColors.down,
                        ),
                        StatCard(
                          icon: Icons.article_rounded,
                          label: 'Новостей загружено',
                          value: '${summary.newsCount}',
                          accent: AppColors.up,
                        ),
                      ];
                      return isWide
                          ? Row(children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c))])
                          : Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [for (final c in cards) SizedBox(width: (constraints.maxWidth - 12) / 2, child: c)],
                            );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  final chart = PriceChartCard(
                    symbol: _selectedSymbol,
                    ticker: selectedTicker,
                    onSymbolChanged: (s) => setState(() => _selectedSymbol = s),
                  );
                  final movers = ListenableBuilder(
                    listenable: deps.dashboardSummary,
                    builder: (context, _) => MoversCard(
                      gainers: deps.dashboardSummary.value.topGainers,
                      losers: deps.dashboardSummary.value.topLosers,
                    ),
                  );

                  if (!isWide) {
                    return Column(children: [chart, const SizedBox(height: 20), movers]);
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 2, child: chart),
                        const SizedBox(width: 20),
                        Expanded(child: movers),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Активы', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 14),
                      // Порядок строк — статический список корзины. Экран
                      // НЕ подписан на рыночные данные ради таблицы вообще
                      // — каждая AssetRow сама решает, когда ей
                      // перерисоваться (см. её докстринг).
                      Column(
                        children: [
                          for (var i = 0; i < curatedSymbols.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            AssetRow(key: ValueKey(curatedSymbols[i]), symbol: curatedSymbols[i]),
                          ],
                        ],
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
