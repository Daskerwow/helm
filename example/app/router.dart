import 'package:go_router/go_router.dart';

import '../data/news/news_api.dart';
import '../presentation/converter/converter_screen.dart';
import '../presentation/dashboard/dashboard_screen.dart';
import '../presentation/market/currency_detail_screen.dart';
import '../presentation/market/market_screen.dart';
import '../presentation/news/article_detail_screen.dart';
import '../presentation/news/news_list_screen.dart';
import '../presentation/news/news_search_screen.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/shell/app_shell.dart';
import '../presentation/watchlist/watchlist_screen.dart';

abstract final class AppRoute {
  static const dashboard = '/';
  static const market = '/market';
  static const watchlist = '/watchlist';
  static const converter = '/converter';
  static const news = '/news';
  static const newsSearch = '/news/search';
  static const settings = '/settings';

  static String currencyDetail(String symbol) => '/market/$symbol';
  static String article(int id) => '/news/$id';
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoute.dashboard,
    routes: [
      // ShellRoute держит сайдбар/шапку общими для всех вкладок нижнего
      // уровня — переключение между ними не пересоздаёт AppShell.
      ShellRoute(
        pageBuilder: (context, state, child) =>
            NoTransitionPage(child: AppShell(child: child)),
        routes: [
          GoRoute(
            path: AppRoute.dashboard,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: AppRoute.market,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: MarketScreen()),
          ),
          GoRoute(
            path: AppRoute.watchlist,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: WatchlistScreen()),
          ),
          GoRoute(
            path: AppRoute.converter,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: ConverterScreen()),
          ),
          GoRoute(
            path: AppRoute.news,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: NewsListScreen()),
          ),
          GoRoute(
            path: AppRoute.settings,
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      // Экраны вне ShellRoute — открываются поверх (без сайдбара), как
      // полноценные под-страницы.
      GoRoute(
        path: '/market/:symbol',
        pageBuilder: (c, s) => NoTransitionPage(
          child: CurrencyDetailScreen(symbol: s.pathParameters['symbol']!),
        ),
      ),
      GoRoute(
        path: AppRoute.newsSearch,
        pageBuilder: (c, s) =>
            const NoTransitionPage(child: NewsSearchScreen()),
      ),
      GoRoute(
        path: '/news/:id',
        pageBuilder: (c, s) => NoTransitionPage(
          child: ArticleDetailScreen(article: s.extra as Article),
        ),
      ),
    ],
  );
}
