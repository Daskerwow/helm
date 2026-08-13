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
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoute.dashboard,
            builder: (c, s) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoute.market,
            builder: (c, s) => const MarketScreen(),
          ),
          GoRoute(
            path: AppRoute.watchlist,
            builder: (c, s) => const WatchlistScreen(),
          ),
          GoRoute(
            path: AppRoute.converter,
            builder: (c, s) => const ConverterScreen(),
          ),
          GoRoute(
            path: AppRoute.news,
            builder: (c, s) => const NewsListScreen(),
          ),
          GoRoute(
            path: AppRoute.settings,
            builder: (c, s) => const SettingsScreen(),
          ),
        ],
      ),
      // Экраны вне ShellRoute — открываются поверх (без сайдбара), как
      // полноценные под-страницы.
      GoRoute(
        path: '/market/:symbol',
        builder: (c, s) =>
            CurrencyDetailScreen(symbol: s.pathParameters['symbol']!),
      ),
      GoRoute(
        path: AppRoute.newsSearch,
        builder: (c, s) => const NewsSearchScreen(),
      ),
      GoRoute(
        path: '/news/:id',
        builder: (c, s) => ArticleDetailScreen(article: s.extra! as Article),
      ),
    ],
  );
}
