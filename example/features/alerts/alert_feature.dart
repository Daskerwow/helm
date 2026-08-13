import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../market/market_state.dart';

final class AlertState {
  const AlertState({
    this.thresholds = const {'btcusdt': 70000},
    this.armed = const {},
  });

  final Map<String, double> thresholds;
  final Map<String, bool> armed;

  double? thresholdOf(String symbol) => thresholds[symbol];

  AlertState copyWith({
    Map<String, double>? thresholds,
    Map<String, bool>? armed,
  }) => AlertState(
    thresholds: thresholds ?? this.thresholds,
    armed: armed ?? this.armed,
  );
}

sealed class AlertEffect {}

final class PriceCrossedThreshold extends AlertEffect {
  PriceCrossedThreshold(this.symbol, this.price, this.threshold);
  final String symbol;
  final double price;
  final double threshold;
}

/// Несколько валют могут пересечь порог в один и тот же тик — эмитим все
/// сразу, а не теряем часть из них.
final class MultiplePricesCrossedThreshold extends AlertEffect {
  MultiplePricesCrossedThreshold(this.crossings);
  final List<PriceCrossedThreshold> crossings;
}

final class SetThresholdCommand implements ISyncCommand<AlertState> {
  const SetThresholdCommand(this.symbol, this.threshold);
  final String symbol;
  final double threshold;

  @override
  AlertState execute(AlertState current) {
    final next = Map<String, double>.of(current.thresholds)
      ..[symbol] = threshold;
    return current.copyWith(thresholds: next);
  }
}

final class ClearThresholdCommand implements ISyncCommand<AlertState> {
  const ClearThresholdCommand(this.symbol);
  final String symbol;

  @override
  AlertState execute(AlertState current) {
    final thresholds = Map<String, double>.of(current.thresholds)
      ..remove(symbol);
    final armed = Map<String, bool>.of(current.armed)..remove(symbol);
    return AlertState(thresholds: thresholds, armed: armed);
  }
}

final class _CheckPricesCommand
    implements ISyncSideEffect<AlertState, AlertEffect> {
  const _CheckPricesCommand(this.prices);
  final Map<String, double> prices;

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
