import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../market/market_state.dart';

final class const AlertState({
  final Map<String, double> thresholds = const {'btcusdt': 70000},
  final Map<String, bool> armed = const {},
}) {
  double? thresholdOf(String symbol) => thresholds[symbol];

  AlertState copyWith({
    Map<String, double>? thresholds,
    Map<String, bool>? armed,
  }) => AlertState(
    thresholds: thresholds ?? this.thresholds,
    armed: armed ?? this.armed,
  );
}

sealed class const AlertEffect();

final class const PriceCrossedThreshold(
  final String symbol,
  final double price,
  final double threshold,
) extends AlertEffect;

/// Несколько валют могут пересечь порог в один и тот же тик — эмитим все
/// сразу, а не теряем часть из них.
final class const MultiplePricesCrossedThreshold(
  final List<PriceCrossedThreshold> crossings,
) extends AlertEffect;

final class const SetThresholdCommand(
  final String symbol,
  final double threshold,
) implements SyncCommand<AlertState> {
  @override
  AlertState execute(AlertState current) {
    final next = Map<String, double>.of(current.thresholds)
      ..[symbol] = threshold;
    return current.copyWith(thresholds: next);
  }
}

final class const ClearThresholdCommand(final String symbol)
    implements SyncCommand<AlertState> {
  @override
  AlertState execute(AlertState current) {
    final thresholds = Map<String, double>.of(current.thresholds)
      ..remove(symbol);
    final armed = Map<String, bool>.of(current.armed)..remove(symbol);
    return AlertState(thresholds: thresholds, armed: armed);
  }
}

final class const _CheckPricesCommand(final Map<String, double> prices)
    implements SyncSideEffect<AlertState, AlertEffect> {
  @override
  SyncSideEffectResult<AlertState, AlertEffect> execute(AlertState current) {
    final nextArmed = Map<String, bool>.of(current.armed);
    final crossings = <PriceCrossedThreshold>[];

    for (final entry in current.thresholds.entries) {
      final price = prices[entry.key];
      if (price == null) continue;

      final isAbove = price >= entry.value;
      final wasAbove = current.armed[entry.key] ?? false;
      nextArmed[entry.key] = isAbove;

      if (isAbove && !wasAbove) {
        crossings.add(PriceCrossedThreshold(entry.key, price, entry.value));
      }
    }

    final AlertEffect? effect = switch (crossings.length) {
      0 => null,
      1 => crossings.first,
      _ => MultiplePricesCrossedThreshold(crossings),
    };

    return (current.copyWith(armed: nextArmed), effect);
  }
}

HelmFeature<AlertState, AlertEffect> buildAlertFeature() =>
    HelmFeature<AlertState, AlertEffect>(
      () => StoreBuilder<AlertState, AlertEffect>(const AlertState()).build(),
    );

void Function() wireAlertsToMarket(
  HelmFeature<MarketState, Never> marketFeature,
  HelmFeature<AlertState, AlertEffect> alertFeature,
) {
  return marketFeature.listen((state) {
    if (state.tickers.isEmpty) return;
    final prices = {for (final t in state.tickers.values) t.symbol: t.price};
    alertFeature.dispatchSyncWithEffect(_CheckPricesCommand(prices));
  });
}
