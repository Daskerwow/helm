import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../../domain/market/curated_symbols.dart';

final class WatchlistState {
  const WatchlistState({this.symbols = const {}});

  final Set<String> symbols;

  bool contains(String symbol) => symbols.contains(symbol);

  WatchlistState _toggled(String symbol) {
    final next = Set<String>.of(symbols);
    if (!next.remove(symbol)) next.add(symbol);
    return WatchlistState(symbols: next);
  }
}

final class ToggleWatchCommand implements ISyncCommand<WatchlistState> {
  const ToggleWatchCommand(this.symbol);
  final String symbol;

  @override
  WatchlistState execute(WatchlistState current) => current._toggled(symbol);
}

/// Дефолт — первые 3 монеты корзины, чтобы при первом запуске в избранном
/// уже что-то было.
HelmFeature<WatchlistState, Never> buildWatchlistFeature() {
  return HelmFeature<WatchlistState, Never>(
    () => StoreBuilder<WatchlistState, Never>(
      WatchlistState(symbols: curatedSymbols.take(3).toSet()),
    ).build(),
  );
}
