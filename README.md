# Helm

Лёгкая, предсказуемая библиотека управления состоянием для Dart и Flutter —
без кодогенерации и без поиска состояния через `BuildContext`.

## Структура пакета

```
lib/
  helm.dart              — публичное ядро (чистый Dart, без Flutter)
  flutter.dart            — публичный мост к Flutter
  src/
    core/                 — StateStore и всё, что вокруг него
      internal/            — writer-декораторы и CallbackList (не публичный API)
    flutter/               — HelmFeature, HelmController, виджет-биндинги
```

Ядро (`src/core`) не содержит ни одного импорта `package:flutter` — это
инвариант архитектуры, а не случайность (Dependency Inversion): `StateStore`
можно использовать в CLI, на сервере или в изоляте. Мост (`src/flutter`)
зависит от ядра, а не наоборот.

## Три принципа

- **Явность** — каждый исход диспатча типизирован через `DispatchResult`
  (`DispatchSuccess` / `DispatchFailure` / `DispatchCancelled`).
- **Разделение прав** — команды получают ровно то, что им нужно:
  `IStateReader` или `IStateWriter`, редко оба сразу.
- **Отменяемость** — асинхронные команды прерываются через `CancelToken`,
  исключая race condition при повторных запросах.

## Быстрый старт (чистый Dart)

```dart
import 'package:helm/helm.dart';

final store = StoreBuilder<MyState, MyEffect>(MyState.initial())
    .onChanged((s) => print(s))
    .onEffect((e) => router.handle(e))
    .onDispatch((event) => logger.debug(event.toLogString()))
    .build();

await store.dispatch(FetchDataCommand(api));
store.close();
```

## Быстрый старт (Flutter)

```dart
final counterFeature = HelmFeature<CounterState, CounterEffect>(
  () => StateStore(initialState: const CounterState.initial()),
);

class CounterScreen extends HelmWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = counterFeature.watch();
    return Scaffold(
      body: Center(child: Text('Count: ${state.count}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => counterFeature.dispatchSync(const IncrementCommand()),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

## Какой API выбрать

Все виджет-обёртки (`HelmBuilder`/`HelmSelector`/`HelmListener`/
`HelmConsumer`) и reactive-методы (`feature.watch()`/`.select()`/
`.effect()`) — это один и тот же механизм подписки в двух синтаксисах, а не
два независимых решения одной задачи:

| Задача                                   | API                              |
|-------------------------------------------|-----------------------------------|
| Ребилд по всему состоянию                  | `HelmBuilder` / `feature.watch()` |
| Ребилд по срезу состояния                  | `HelmSelector` / `feature.select()` |
| Реакция на side-эффект, без ребилда        | `HelmListener` / `feature.effect()`* |
| Состояние сразу из нескольких фич          | `HelmComputed` / `helmCompute()`  |
| `S == Loadable<T>` целиком                 | `HelmLoadableBuilder`             |
| Вне `build()`                              | `feature.value` / `feature.listen()` |

\* `feature.effect()` реагирует на изменение **состояния**, а не на
side-эффект `E` — для side-эффектов вне widget-дерева используй
`HelmFeature.onEffect` или `HelmListener`.

Выбирай виджет-обёртку, когда состояние нужно только листу дерева и хочется
явной границы; `watch()`/`select()`/`effect()` — когда лишний уровень
вложенности виджетов не нужен.

## Сравнение состояний для мутируемых коллекций

Если `S` (или срез, с которым работает `equals`/`selector`) — `List`/`Set`/
`Map` без содержательного `==`, используй готовые компараторы из
`equality.dart` вместо самодельных:

```dart
StateStore<List<Todo>, Never>(
  initialState: const [],
  equals: listEquals, // либо setEquals / mapEquals / deepEquals
);
```

## Middleware

`StoreMiddleware<S>` — именованная альтернатива `addDispatchListener` для
кросс-катаных забот (логирование, аналитика, DevTools-мост), которые
удобнее оформить классом, а не анонимным замыканием:

```dart
final class AnalyticsMiddleware implements StoreMiddleware<AppState> {
  const AnalyticsMiddleware(this._analytics);
  final Analytics _analytics;

  @override
  void onDispatch(DispatchEvent<AppState> event) {
    if (event.isSuccess) _analytics.track(event.commandLabel);
  }
}

StoreBuilder<AppState, AppEffect>(AppState.initial())
    .withMiddleware(AnalyticsMiddleware(analytics))
    .build();
```

Middleware работает поверх уже случившихся диспатчей (наблюдатель, а не
перехватчик) — это сознательное ограничение: `StateStore` не даёт ничему
подменить команду или её результат *до* выполнения, иначе терялась бы
гарантия синхронной публикации любого `commit` (см. докстринг `StateStore`,
раздел "Согласованность").

## Изоляция ошибок слушателей

Исключение одного `addOnChanged`/`addOnEffect`/`addDispatchListener`-
слушателя не мешает доставить событие остальным подписчикам — упавший
слушатель перехватывается и репортится через `addErrorListener` (см.
докстринг `_ListenerHub` в `state_store.dart`). Это касается только
слушателей самого `StateStore`; исключение внутри команды (`execute()`)
по-прежнему приводит к `DispatchFailure` обычным путём.

## Внедрение зависимостей и тесты

`HelmFeature.overrideWith` — единственный официальный способ подмены
реализации, оформленный как настоящий стек: вложенные подмены
восстанавливаются в порядке LIFO (обычный случай — `addTearDown` сразу
после каждого `overrideWith`).

```dart
test('shows loaded todos', () {
  final restore = todosFeature.overrideWith(
    () => StateStore(initialState: Loadable.data(fakeTodos)),
  );
  addTearDown(restore);
  expect(todosFeature.value.valueOrNull, fakeTodos);
});
```

`HelmFeature.debugActiveFeatures` — снимок всех фич с активным Store,
доступный только в debug-режиме (сборка не платит за это в release).
Полезен, чтобы ловить забытый `acquire()`/`listen()` без парного снятия:

```dart
tearDown(() {
  expect(HelmFeature.debugActiveFeatures, isEmpty,
      reason: 'Фича осталась активной между тестами — забыт release()');
});
```

`StateStore.debugResetForTesting` — прямая замена состояния в обход
dispatch-цикла, только для тестов; префикс `debug` (как `debugPrint` в
самом Flutter SDK) делает случайное использование в продакшен-коде
заметным при code review.

## Диагностика отброшенных коммитов

`GuardedWriter` отбрасывает коммит, если команда закоммитила после отмены
своего `CancelToken` (нарушение контракта — команда должна была сама
проверить `isCancelled`). Помимо debug-only подсказки в консоль, можно
передать `onDroppedCommit` в `StateStore`/`StoreBuilder`, чтобы отправлять
такие случаи в мониторинг и из релизной сборки:

```dart
StoreBuilder<AppState, AppEffect>(AppState.initial())
    .withDroppedCommitHandler(
      (label, next) => Sentry.captureMessage('dropped commit: $label'),
    )
    .build();
```
