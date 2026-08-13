import 'package:flutter/material.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/market/ticker.dart';
import '../dashboard/widgets/asset_row.dart';
import '../widgets/connection_badge.dart';

enum _SortMode { volumeDesc, changeDesc, changeAsc, priceDesc, name }

const _sortLabels = {
  _SortMode.volumeDesc: 'Объём',
  _SortMode.changeDesc: 'Рост',
  _SortMode.changeAsc: 'Падение',
  _SortMode.priceDesc: 'Цена',
  _SortMode.name: 'A-Я',
};

class MarketScreen extends StatefulHelmWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _searchController = TextEditingController();
  _SortMode _sort = _SortMode.volumeDesc;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Ticker> _apply(List<Ticker> tickers) {
    final filtered = _query.isEmpty
        ? tickers
        : tickers
              .where((t) => t.symbol.contains(_query.toLowerCase()))
              .toList();

    final list = [...filtered];
    switch (_sort) {
      case _SortMode.volumeDesc:
        list.sort((a, b) => b.volumeQuote24h.compareTo(a.volumeQuote24h));
      case _SortMode.changeDesc:
        list.sort((a, b) => b.changePercent24h.compareTo(a.changePercent24h));
      case _SortMode.changeAsc:
        list.sort((a, b) => a.changePercent24h.compareTo(b.changePercent24h));
      case _SortMode.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _SortMode.name:
        list.sort((a, b) => a.symbol.compareTo(b.symbol));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    // Порядок/фильтр по цене-объёму-росту зависят от текущих котировок —
    // эта часть намеренно подписана на marketFeature целиком (иначе
    // сортировку по цене/росту нечем было бы держать актуальной). Но
    // КАЖДАЯ строка внутри (AssetRow) сама решает, перерисовывать ли себя
    // — см. её докстринг, — поэтому лишнего рендера графиков тут нет.
    final status = deps.marketFeature.select(
      (s) => s.status,
      key: #connectionStatus,
    );
    final tickers = deps.marketFeature.select(
      (s) => s.orderedTickers,
      key: #orderedTickers,
    );

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Рынок',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                ConnectionBadge(status: status),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по тикеру, например BTC',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in _sortLabels.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _sort == entry.key,
                          onSelected: (_) => setState(() => _sort = entry.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: tickers.isEmpty
                      ? const Center(
                          child: Text(
                            'Загрузка котировок…',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final sorted = _apply(tickers);
                            if (sorted.isEmpty) {
                              return const Center(
                                child: Text('Ничего не найдено'),
                              );
                            }
                            return ListView.separated(
                              itemCount: sorted.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) => AssetRow(
                                key: ValueKey(sorted[i].symbol),
                                symbol: sorted[i].symbol,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
