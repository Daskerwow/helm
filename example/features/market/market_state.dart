import '../../domain/market/curated_symbols.dart';
import '../../domain/market/ticker.dart';

export '../../domain/market/ticker.dart';

enum ConnectionStatus { connecting, live, reconnecting }

/// Строка таблицы активов — тикер + короткая история цены для спарклайна,
/// одной подпиской. Records в Dart сравниваются структурно (`==` по каждому
/// полю) без ручного `operator==` — `Ticker.==` уже переопределён по
/// значению (см. `domain/market/ticker.dart`), `List` сравнивается по
/// ссылке, но это ровно то, что нужно: `history[symbol]` получает новый
/// `List`-инстанс только когда меняется цена ИМЕННО этого символа (см.
/// `WatchMarketCommand._appendHistory`), так что `AssetRow`, подписанный на
/// один конкретный символ, перестраивается ровно тогда, когда его
/// собственные данные реально изменились — а не на любой тик рынка.
typedef AssetRowData = ({Ticker ticker, List<double> history});

final class MarketState {
  const MarketState({
    this.status = ConnectionStatus.connecting,
    this.tickers = const {},
    this.history = const {},
  });

  final ConnectionStatus status;

  /// Ключ — символ в нижнем регистре ('btcusdt'). Ограничен `curatedSymbols`
  /// — сокет и не подписывается на что-то ещё (см. `MarketSocket`).
  final Map<String, Ticker> tickers;

  /// Скользящее окно последних цен на символ (для спарклайнов). Живёт в
  /// Store, а не в `State` виджета — Store в `helm` уже является
  /// единственным источником истины и сам решает, когда что изменилось;
  /// держать копию истории в виджете означало бы два источника истины и
  /// ручную синхронизацию между ними через `initState`/`didUpdateWidget`.
  final Map<String, List<double>> history;

  Ticker? tickerOf(String symbol) => tickers[symbol];
  double? priceOf(String symbol) => tickers[symbol]?.price;
  List<double> historyOf(String symbol) => history[symbol] ?? const [];

  /// Тикер + история одним значением — см. докстринг [AssetRowData].
  AssetRowData? rowOf(String symbol) {
    final ticker = tickers[symbol];
    if (ticker == null) return null;
    return (ticker: ticker, history: historyOf(symbol));
  }

  /// Тикеры в стабильном порядке корзины — важно для UI (карточки/таблица
  /// не должны прыгать местами при каждом обновлении карты).
  List<Ticker> get orderedTickers => [
    for (final s in curatedSymbols)
      if (tickers[s] != null) tickers[s]!,
  ];

  List<Ticker> topGainers({int count = 5}) {
    final list = orderedTickers.toList()
      ..sort((a, b) => b.changePercent24h.compareTo(a.changePercent24h));
    return list.take(count).toList();
  }

  List<Ticker> topLosers({int count = 5}) {
    final list = orderedTickers.toList()
      ..sort((a, b) => a.changePercent24h.compareTo(b.changePercent24h));
    return list.take(count).toList();
  }

  double get totalVolume24h =>
      orderedTickers.fold(0.0, (sum, t) => sum + t.volumeQuote24h);

  MarketState copyWith({
    ConnectionStatus? status,
    Map<String, Ticker>? tickers,
    Map<String, List<double>>? history,
  }) => MarketState(
    status: status ?? this.status,
    tickers: tickers ?? this.tickers,
    history: history ?? this.history,
  );
}
