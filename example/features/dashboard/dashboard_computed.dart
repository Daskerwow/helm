import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../../data/news/news_api.dart';
import '../alerts/alert_feature.dart';
import '../market/market_state.dart';
import '../watchlist/watchlist_feature.dart';

final class DashboardSummary {
  const DashboardSummary({
    required this.watchedCount,
    required this.armedAlertsCount,
    required this.newsCount,
    required this.totalVolume24h,
    required this.topGainers,
    required this.topLosers,
  });

  final int watchedCount;
  final int armedAlertsCount;
  final int newsCount;
  final double totalVolume24h;
  final List<Ticker> topGainers;
  final List<Ticker> topLosers;
}

/// Без переопределения `==`/`hashCode` в `DashboardSummary` — намеренно:
/// каждый пересчёт создаёт новый объект, `HelmComputed` со стандартным
/// сравнением по идентичности всегда считает это изменением, и дашборд
/// живьём обновляется на каждый тик рынка без искусственной задержки.
HelmComputed<DashboardSummary> buildDashboardSummary({
  required HelmFeature<MarketState, Never> marketFeature,
  required HelmFeature<WatchlistState, Never> watchlistFeature,
  required HelmFeature<AlertState, AlertEffect> alertFeature,
  required HelmFeature<Loadable<List<Article>>, Never> newsFeature,
}) {
  return helmCompute(() {
    final market = marketFeature.value;
    final watchlist = watchlistFeature.value;
    final alerts = alertFeature.value;
    final news = newsFeature.value;

    final armedCount = alerts.armed.values.where((isArmed) => isArmed).length;

    return DashboardSummary(
      watchedCount: watchlist.symbols.length,
      armedAlertsCount: armedCount,
      newsCount: news.valueOrNull?.length ?? 0,
      totalVolume24h: market.totalVolume24h,
      topGainers: market.topGainers(count: 5),
      topLosers: market.topLosers(count: 5),
    );
  });
}
