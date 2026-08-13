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

@immutable
class _BindingKey {
  const _BindingKey(this.feature, this.kind, this.explicitKey);

  /// Сам токен [HelmFeature] — сравнивается по идентичности, не по `==`.
  final Object feature;
  final _BindingKind kind;

  /// Различает несколько биндингов одного вида на одной фиче в одном
  /// виджете — см. [HelmFeatureReactive.select].
  final Object? explicitKey;

  @override
  bool operator ==(Object other) =>
      other is _BindingKey &&
      identical(other.feature, feature) &&
      other.kind == kind &&
      other.explicitKey == explicitKey;

  @override
  int get hashCode => Object.hash(identityHashCode(feature), kind, explicitKey);
}

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
/// проблемы нет: у каждого биндинга уже есть стабильный между билдами ключ
/// — сам объект [HelmFeature] (обычно `top-level final`). Биндинги хранятся
/// в `Map`, поэтому `feature.watch()` можно звать условно, в цикле, где
/// угодно; единственное, что нужно проговорить явно — [Object] key при
/// нескольких разных биндингах одного вида на одной фиче в одном виджете
/// (см. [HelmFeatureReactive.select]).
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
  /// [key] нужен, только если на одной фиче зовётся несколько независимых
  /// `watch()` в одном виджете — на практике почти никогда.
  S watch({Object? key}) {
    final element = _requireElement();
    final bindingKey = _BindingKey(this, _BindingKind.watch, key);
    return element
        ._bindingFor(
          bindingKey,
          () => _WatchBinding<S, E>(this, element.markNeedsBuild),
        )
        .value;
  }

  /// Точечная подписка по срезу состояния (`==`) — аналог [HelmSelector].
  ///
  /// [key] обязателен, если на одной фиче вызывается несколько разных
  /// `select()` в одном виджете — иначе они делят биндинг и видят только
  /// последний вызванный `selector`:
  ///
  /// ```dart
  /// final title = documentFeature.select((s) => s.title, key: #title);
  /// final words = documentFeature.select((s) => s.body.length, key: #words);
  /// ```
  R select<R>(R Function(S state) selector, {Object? key}) {
    final element = _requireElement();
    final bindingKey = _BindingKey(this, _BindingKind.select, key);
    final binding = element._bindingFor(
      bindingKey,
      () => _SelectBinding<S, E, R>(this, selector, element.markNeedsBuild),
    );
    binding.selector = selector;
    // Пересчитываем немедленно: если selector изменился между билдами
    // (захватил новую переменную), значение не должно оставаться
    // устаревшим до следующего изменения состояния фичи.
    binding.resync();
    return binding.value;
  }

  /// Побочный эффект на каждое изменение состояния — аналог [HelmListener],
  /// но по состоянию, а не по эффектам; не вызывает ребилд. Первый вызов —
  /// сразу после текущего кадра, последующие — на каждое изменение.
  void effect(void Function(S state) callback, {Object? key}) {
    final element = _requireElement();
    final bindingKey = _BindingKey(this, _BindingKind.effect, key);
    final binding = element._bindingFor(
      bindingKey,
      () => _EffectBinding<S, E>(this, callback),
    );
    binding.effect = callback;
  }

  /// Синхронное чтение без подписки — алиас [value], для симметрии с [watch].
  /// Можно вызывать откуда угодно, не только из `build()`.
  S read() => value;
}
