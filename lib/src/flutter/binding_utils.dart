import 'helm_controller.dart';
import 'helm_feature.dart';

/// Общий паттерн "переподключиться к новому контроллеру фичи после
/// `overrideWith`/принудительного `dispose`" — используется всеми
/// биндингами моста ([HelmBuilder]/[HelmSelector]/[HelmListener],
/// `feature.watch()`/`.select()`/`.effect()`, [HelmComputed]).
///
/// Спрашивает [HelmFeature.currentController], сравнивает `identical` со
/// старым и, если он реально сменился, снимает слушателя со старого и
/// вешает на новый. Что именно делать с "значением" после смены
/// (setState/пересчитать selector/дёрнуть effect) — решает вызывающий код.
HelmController<S, E>? swapController<S, E>({
  required HelmFeature<S, E> feature,
  required HelmController<S, E> current,
  required void Function(HelmController<S, E> controller) removeListener,
  required void Function(HelmController<S, E> controller) addListener,
}) {
  final fresh = feature.currentController;
  if (identical(fresh, current)) return null;

  removeListener(current);
  addListener(fresh);

  return fresh;
}
