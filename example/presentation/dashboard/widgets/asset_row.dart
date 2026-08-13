import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helm/flutter.dart';

import '../../../app/di.dart';
import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/market/curated_symbols.dart';
import '../../../features/watchlist/watchlist_feature.dart';
import '../../widgets/sparkline_chart.dart';

/// Строка таблицы активов — на [HelmWidget]: `feature.select()` даёт
/// точечную подписку прямо в `build()`, без обёртки в `HelmSelector` и без
/// собственного `StatefulWidget`. Каждый экземпляр `AssetRow` — свой
/// `Element` (см. `HelmReactiveElement._bindings` в `helm_reactive.dart`),
/// поэтому одинаковые вызовы `.select()` в разных строках друг другу не
/// мешают — конфликт ключей внутри одного вызова `.select()` на одном и
/// том же токене фичи в одном и том же виджете (см. докстринг
/// `HelmFeatureReactive.select`) тут не возникает: на каждую фичу в этом
/// виджете ровно один `.select()`.
///
/// Перестраивается ТОЛЬКО когда меняются данные СВОЕГО символа — тикер и
/// история приходят одной подпиской на `s.rowOf(symbol)` (см.
/// `MarketState.rowOf` — `Ticker` сравнивается по значению, `List`
/// истории — по ссылке, которая обновляется только для реально
/// изменившегося символа). Обновление любой из остальных 9 монет корзины
/// эту строку не трогает вообще.
class AssetRow extends HelmWidget {
  const AssetRow({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    final row = deps.marketFeature.select((s) => s.rowOf(symbol));
    final isWatched = deps.watchlistFeature.select((s) => s.contains(symbol));

    if (row == null) {
      return const SizedBox(height: 56); // котировка ещё не пришла
    }

    final ticker = row.ticker;
    final color = ticker.isUp ? AppColors.up : AppColors.down;

    return InkWell(
      // push(), а не go(): страница монеты — под-экран со стрелкой
      // "назад", ей нужна запись в стеке навигации, чтобы было куда
      // возвращаться. go() заменяет текущий маршрут без сохранения
      // истории — на кнопке "назад" это падает с "There is nothing to pop".
      onTap: () => context.push(AppRoute.currencyDetail(symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(
                  isWatched ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isWatched ? AppColors.warning : AppColors.textMuted,
                ),
                onPressed: () => deps.watchlistFeature.dispatchSync(
                  ToggleWatchCommand(symbol),
                ),
              ),
            ),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceElevated,
              child: Text(
                symbolTicker(symbol).substring(0, 1),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbolTicker(symbol),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    symbolName(symbol),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: SparklineChart(values: row.history, color: color),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '\$${formatPrice(ticker.price)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    formatPercent(ticker.changePercent24h),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatCompactUsd(ticker.volumeQuote24h),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
