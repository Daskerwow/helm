import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:helm/flutter.dart';
import 'package:helm/helm.dart';

import '../core/network/http_client.dart';
import '../data/market/market_klines_api.dart';
import '../data/market/market_socket.dart';
import '../data/news/news_api.dart';
import '../features/alerts/alert_feature.dart';
import '../features/dashboard/dashboard_computed.dart';
import '../features/market/market_feature.dart';
import '../features/news/news_feature.dart';
import '../features/watchlist/watchlist_feature.dart';

/// Композиционный корень приложения. Раньше всё это — Dio, API-клиенты,
/// все `HelmFeature` — жило прямо в виде `late final` глобалов в
/// `main.dart`, вперемешку с вызовом `runApp`. Это работает, но не
/// масштабируется и не тестируется: нельзя подменить зависимости для
/// теста виджета, нельзя увидеть весь граф зависимостей одним взглядом.
///
/// `AppDependencies` — обычный класс с явным конструктором зависимостей
/// (собирается один раз в [AppDependencies.create]), который прокидывается
/// в дерево виджетов через [AppScope] (`InheritedWidget`) — тот же принцип
/// явной передачи зависимости, что и раньше (`NewsApi(dio)` в
/// конструкторе), просто на уровне всего приложения, а не одного класса.
final class AppDependencies {
  AppDependencies._({
    required this.dio,
    required this.newsApi,
    required this.marketSocket,
    required this.marketKlinesApi,
    required this.marketFeature,
    required this.watchlistFeature,
    required this.alertFeature,
    required this.newsFeature,
    required this.dashboardSummary,
  });

  final Dio dio;
  final NewsApi newsApi;
  final MarketSocket marketSocket;
  final MarketKlinesApi marketKlinesApi;

  final HelmFeature<MarketState, Never> marketFeature;
  final HelmFeature<WatchlistState, Never> watchlistFeature;
  final HelmFeature<AlertState, AlertEffect> alertFeature;
  final HelmFeature<Loadable<List<Article>>, Never> newsFeature;
  final HelmComputed<DashboardSummary> dashboardSummary;

  factory AppDependencies.create() {
    final dio = buildHttpClient();
    final newsApi = NewsApi(dio);
    final marketSocket = const MarketSocket();
    final marketKlinesApi = MarketKlinesApi(dio);

    final marketFeature = buildMarketFeature(marketSocket);
    final watchlistFeature = buildWatchlistFeature();
    final alertFeature = buildAlertFeature();
    wireAlertsToMarket(marketFeature, alertFeature);

    final newsFeature = buildNewsFeature()..load(newsApi.fetchAll);

    final dashboardSummary = buildDashboardSummary(
      marketFeature: marketFeature,
      watchlistFeature: watchlistFeature,
      alertFeature: alertFeature,
      newsFeature: newsFeature,
    );

    return AppDependencies._(
      dio: dio,
      newsApi: newsApi,
      marketSocket: marketSocket,
      marketKlinesApi: marketKlinesApi,
      marketFeature: marketFeature,
      watchlistFeature: watchlistFeature,
      alertFeature: alertFeature,
      newsFeature: newsFeature,
      dashboardSummary: dashboardSummary,
    );
  }
}

/// Даёт экранам доступ к зависимостям через `AppScope.of(context)` —
/// без единого глобального `late final` в файле экрана.
final class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.deps, required super.child});

  final AppDependencies deps;

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден выше по дереву виджетов');
    return scope!.deps;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false; // deps — синглтон на весь app-lifecycle
}
