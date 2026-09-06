import 'package:flutter/widgets.dart';

import 'binding_utils.dart';
import 'helm_controller.dart';
import 'helm_feature.dart';

/// [StatelessWidget], умеющий `feature.watch()`/`.select()`/`.effect()`
/// прямо в `build()` — без явного `HelmBuilder`/`HelmSelector`/`HelmListener`
/// вокруг.
///
/// Похоже на `HookWidget` из `flutter_hooks`, но без внешней зависимости и
/// без индексации по порядку вызова: биндинги ключуются по идентичности
/// самого [HelmFeature]-токена (см. [HelmReactiveElement]), поэтому
/// `feature.watch()` можно звать из `if`/цикла без риска "съехавшего"
/// состояния.
abstract class HelmWidget extends StatelessWidget {
  const HelmWidget({super.key});

  @override
  StatelessElement createElement() => _StatelessHelmElement(this);
}

class _StatelessHelmElement extends StatelessElement with HelmReactiveElement {
  _StatelessHelmElement(super.widget);
}

/// Как [HelmWidget], но со `State` — когда, помимо `feature.watch()`, нужен
/// собственный `setState`/`initState`/контроллеры анимации.
abstract class StatefulHelmWidget extends StatefulWidget {
  const StatefulHelmWidget({super.key});

  @override
  StatefulElement createElement() => _StatefulHelmElement(this);
}

class _StatefulHelmElement extends StatefulElement with HelmReactiveElement {
  _StatefulHelmElement(super.widget);
}

// ── Внутреннее: биндинги и их хранилище ─────────────────────────────────

enum _BindingKind { watch, select, effect }

typedef _BindingKey = (Object feature, _BindingKind kind);

abstract class _Binding {
  void dispose();
}

/// Общий скелет для [_WatchBinding]/[_SelectBinding]/[_EffectBinding]:
/// acquire фичи, подписка на конкретный вид слушателя (решает подкласс через
/// [attachListener]/[detachListener]), переподключение к новому контроллеру
/// после `overrideWith`/принудительного `dispose` фичи ([_onLifecycle], тот
/// же паттерн [swapController], что и в биндингах `State`), release в
/// [dispose]. Устраняет тройное дублирование этого скелета между тремя
/// видами биндингов — они отличаются только тем, что именно вешают на
/// контроллер и что делают при его смене ([onControllerSwapped]).
abstract class _FeatureBinding<S, E> implements _Binding {
  _FeatureBinding(this.feature) : controller = feature.acquire();

  final HelmFeature<S, E> feature;
  HelmController<S, E> controller;

  /// Вешает специфичный для подкласса слушатель на [controller].
  void attachListener(HelmController<S, E> controller);

  /// Снимает слушатель, навешенный [attachListener].
  void detachListener(HelmController<S, E> controller);

  /// Вызывается сразу после переподключения к новому контроллеру — по
  /// умолчанию ничего не делает; [_WatchBinding]/[_SelectBinding] дёргают
  /// им перерасчёт/колбэк ребилда, [_EffectBinding] — сам эффект.
  void onControllerSwapped() {}

  /// Довершает инициализацию — вешает слушатель и подписывается на
  /// [HelmFeature.lifecycle]. Вызывается конструктором подкласса ПОСЛЕ
  /// того, как он проинициализировал собственные поля (например,
  /// закэшированное значение selector'а): иначе виртуальный вызов
  /// [attachListener] из тела конструктора базового класса сработал бы
  /// раньше, чем эти поля готовы.
  void start() {
    attachListener(controller);
    feature.lifecycle.addListener(_onLifecycle);
  }

  void _onLifecycle() {
    final fresh = swapController<S, E>(
      feature: feature,
      current: controller,
      removeListener: detachListener,
      addListener: attachListener,
    );
    if (fresh == null) return;
    controller = fresh;
    onControllerSwapped();
  }

  @override
  void dispose() {
    detachListener(controller);
    feature.lifecycle.removeListener(_onLifecycle);
    feature.release();
  }
}

class _WatchBinding<S, E> extends _FeatureBinding<S, E> {
  _WatchBinding(super.feature, this._onChanged) {
    start();
  }

  final VoidCallback _onChanged;

  S get value => controller.state;

  @override
  void attachListener(HelmController<S, E> controller) =>
      controller.addListener(_onChanged);

  @override
  void detachListener(HelmController<S, E> controller) =>
      controller.removeListener(_onChanged);

  @override
  void onControllerSwapped() => _onChanged();
}

class _SelectBinding<S, E, R> extends _FeatureBinding<S, E> {
  _SelectBinding(super.feature, this.selector, this._onChanged) {
    _value = selector(controller.state);
    start();
  }

  /// Переприсваивается на каждый вызов [HelmFeatureReactive.select], чтобы
  /// замыкание всегда было свежим.
  R Function(S state) selector;
  final VoidCallback _onChanged;
  late R _value;

  R get value => _value;

  void _listener() {
    final next = selector(controller.state);
    if (next != _value) {
      _value = next;
      _onChanged();
    }
  }

  /// Синхронно пересчитывает значение по актуальному [selector] — вызывается
  /// сразу после переприсваивания `selector` в [HelmFeatureReactive.select],
  /// **до** возврата значения вызывающей стороне. Без этого, если `selector`
  /// поменялся между билдами (замкнул новую переменную из внешнего build),
  /// [_value] оставался бы устаревшим до следующего изменения состояния
  /// фичи. Не вызывает [_onChanged] — мы уже внутри текущего `build()`,
  /// повторный `markNeedsBuild()` здесь не нужен.
  void resync() {
    final next = selector(controller.state);
    if (next != _value) _value = next;
  }

  @override
  void attachListener(HelmController<S, E> controller) =>
      controller.addListener(_listener);

  @override
  void detachListener(HelmController<S, E> controller) =>
      controller.removeListener(_listener);

  @override
  void onControllerSwapped() => _listener();
}

class _EffectBinding<S, E> extends _FeatureBinding<S, E> {
  _EffectBinding(super.feature, this.effect) {
    start();

    // Первый вызов — после текущего кадра, а не синхронно во время build(),
    // как и эффекты в hooks-библиотеках. [_disposed] защищает от вызова на
    // уже отвязанном биндинге, если виджет размонтирован до конца кадра
    // (например, навигация pop сразу после push) — без этой проверки
    // callback всё равно выполнился бы поверх уже освобождённых ресурсов.
    //
    // [_initialCallDone] защищает от ДВОЙНОГО вызова: если lifecycle фичи
    // сработал (overrideWith/принудительный dispose) раньше, чем успел
    // выполниться этот post-frame callback, [onControllerSwapped] уже
    // вызвал [effect] с актуальным состоянием нового контроллера — сам
    // post-frame callback в этом случае должен стать no-op, а не позвать
    // effect() второй раз тем же кадром с тем же (или уже следующим)
    // состоянием.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _initialCallDone) return;
      _initialCallDone = true;
      effect(controller.state);
    });
  }

  /// Переприсваивается на каждый вызов [HelmFeatureReactive.effect].
  void Function(S state) effect;

  bool _disposed = false;

  /// `true`, если начальный вызов [effect] уже случился — либо из
  /// post-frame callback конструктора, либо (раньше него) из
  /// [onControllerSwapped].
  bool _initialCallDone = false;

  void _listener() => effect(controller.state);

  @override
  void attachListener(HelmController<S, E> controller) =>
      controller.addListener(_listener);

  @override
  void detachListener(HelmController<S, E> controller) =>
      controller.removeListener(_listener);

  @override
  void onControllerSwapped() {
    _initialCallDone = true;
    effect(controller.state);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// [Element]-миксин, резолвящий `feature.watch()`/`.select()`/`.effect()`.
///
/// ### Почему без "порядка вызовов", в отличие от классических хуков
///
/// Классические хуки индексируют состояние по порядковому номеру вызова
/// внутри `build()` — `useState` внутри `if`/цикла ломает всё. Здесь этой
/// проблемы нет вообще, а не только частично: ключ биндинга — пара (сам
/// объект [HelmFeature], вид биндинга: watch/select/effect), она не
/// зависит ни от места вызова, ни от их количества за билд. Поэтому
/// `feature.watch()`/`.select()`/`.effect()` можно звать условно, в цикле,
/// в любом порядке между перестройками — без ключа и без индексации.
///
/// Если из ОДНОЙ фичи в одном виджете нужно несколько независимых срезов —
/// это не про порядок вызовов, а про то, что `select()` — один вызов на
/// (фича × вид биндинга): несколько срезов собираются в один селектор,
/// возвращающий `record` (структурное `==` по полям встроено в Dart 3) —
/// см. докстринг [HelmFeatureReactive.select].
///
/// Биндинги, не вызванные в очередном `build()`, автоматически
/// освобождаются сразу после него — без утечек и ручного управления.
mixin HelmReactiveElement on ComponentElement {
  static HelmReactiveElement? _current;

  final Map<_BindingKey, _Binding> _bindings = {};

  /// Стек наборов "увиденных в текущем build()" ключей — один элемент на
  /// каждый вложенный/повторный вызов [build] (устойчивость к
  /// `reassemble()`/hot reload, который может вызвать `build()` того же
  /// `Element` не строго последовательно).
  final List<Set<_BindingKey>> _seenStack = [];

  /// Пул уже использованных (очищенных) `Set`-ов для [_seenStack] — без
  /// него каждый [build] аллоцировал бы новый `<_BindingKey>{}`. Для
  /// виджета, перестраивающегося внутри анимации (60 раз в секунду), это
  /// 60 лишних аллокаций в секунду на виджет. Сет из пула переиспользуется
  /// между билдами; новый выделяется только при глубокой реентрантности
  /// (вложенный/повторный [build], например из hot reload), когда пул
  /// пуст.
  final List<Set<_BindingKey>> _setPool = [];

  B _bindingFor<B extends _Binding>(_BindingKey key, B Function() create) {
    assert(
      _seenStack.isNotEmpty,
      'feature.watch()/.select()/.effect() вызваны вне build()',
    );
    _seenStack.last.add(key);
    final existing = _bindings[key];
    if (existing != null) return existing as B;
    final created = create();
    _bindings[key] = created;
    return created;
  }

  @override
  Widget build() {
    final previousCurrent = _current;
    _current = this;
    final seen = _setPool.isNotEmpty ? _setPool.removeLast() : <_BindingKey>{};
    _seenStack.add(seen);
    try {
      return super.build();
    } finally {
      final finished = _seenStack.removeLast();
      _current = previousCurrent;
      _disposeUnseenBindings(finished);
      finished.clear();
      _setPool.add(finished);
    }
  }

  void _disposeUnseenBindings(Set<_BindingKey> seen) {
    _bindings.removeWhere((key, binding) {
      final stale = !seen.contains(key);
      if (stale) binding.dispose();
      return stale;
    });
  }

  @override
  void unmount() {
    for (final binding in _bindings.values) {
      binding.dispose();
    }
    _bindings.clear();
    super.unmount();
  }
}

HelmReactiveElement _requireElement() {
  final element = HelmReactiveElement._current;
  assert(element != null, '''
feature.watch()/.select()/.effect() можно вызывать только внутри build()
виджета, унаследованного от HelmWidget или StatefulHelmWidget. Вне build()
используй feature.value/.read()/.listen() напрямую.
''');
  return element!;
}

/// Короткий реактивный синтаксис прямо на токене фичи — `feature.watch()`
/// вместо ручного `HelmBuilder`. Работает только внутри `build()`
/// [HelmWidget]/[StatefulHelmWidget].
///
/// ```dart
/// class Example extends HelmWidget {
///   const Example({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final state = counterFeature.watch();
///     final isEven = counterFeature.select((s) => s.count.isEven);
///     counterFeature.effect((s) => debugPrint('count: ${s.count}'));
///
///     return Scaffold(
///       body: Center(child: Text('Count: ${state.count}')),
///       floatingActionButton: FloatingActionButton(
///         onPressed: () => counterFeature.dispatchSync(const IncrementCommand()),
///         child: const Icon(Icons.add),
///       ),
///     );
///   }
/// }
/// ```
extension HelmFeatureReactive<S, E> on HelmFeature<S, E> {
  /// Подписка на весь `S` + ребилд при каждом изменении — аналог [HelmBuilder].
  S watch() {
    final element = _requireElement();
    final key = (this, _BindingKind.watch);
    return element
        ._bindingFor(
          key,
          () => _WatchBinding<S, E>(this, element.markNeedsBuild),
        )
        .value;
  }

  /// Точечная подписка по срезу состояния — аналог [HelmSelector].
  ///
  /// Если из ОДНОЙ фичи в одном виджете нужно несколько независимых срезов —
  /// не зови `select()` повторно, а верни из одного селектора `record`:
  /// сравнение "не изменилось" у `record` в Dart 3 уже структурное
  /// (`(a, b) == (a, b)`), поэтому это работает без какого-либо
  /// дополнительного API и без ключа:
  ///
  /// ```dart
  /// final (status, ticker) = marketFeature.select(
  ///   (s) => (s.status, s.tickerOf(selectedSymbol)),
  /// );
  /// ```
  R select<R>(R Function(S state) selector) {
    final element = _requireElement();
    final key = (this, _BindingKind.select);
    final binding = element._bindingFor(
      key,
      () => _SelectBinding<S, E, R>(this, selector, element.markNeedsBuild),
    );
    binding.selector = selector;
    // Пересчитываем немедленно: если selector изменился между билдами
    // (захватил новую переменную), значение не должно оставаться
    // устаревшим до следующего изменения состояния фичи.
    binding.resync();
    return binding.value;
  }

  /// Побочный эффект на каждое изменение состояния — аналог [HelmListener].
  /// Несколько независимых реакций на одну фичу — не отдельные вызовы,
  /// а ветвления внутри одного колбэка:
  ///
  /// ```dart
  /// marketFeature.effect((s) {
  ///   _logStatusChange(s.status);
  ///   _syncTitle(s.title);
  /// });
  /// ```
  void effect(void Function(S state) callback) {
    final element = _requireElement();
    final key = (this, _BindingKind.effect);
    final binding = element._bindingFor(
      key,
      () => _EffectBinding<S, E>(this, callback),
    );
    binding.effect = callback;
  }

  /// Синхронное чтение без подписки.
  S read() => value;
}
