# Что изменено в Helm

## 1. Исправления надёжности ядра (`lib/src/state_store.dart`)

### a) `states` больше не "теряет" промежуточные коммиты
Раньше при отмене (`CancelReason`) или исключении внутри async-команды
`StateStore` **не** эмитировал состояние в `states`, даже если команда
успела сделать `commit` до отмены/ошибки (например, `isLoading: true`).
`state` (синхронное чтение) при этом уже был обновлён — получалось
рассинхронизированное поведение: одни части UI (читающие `state` напрямую)
видели изменение, другие (подписанные на `states`, то есть весь Provider/
Riverpod/Bloc-мир) — нет.

Теперь `_emitState(before)` вызывается при **любом** исходе: успех, ошибка,
отмена. `state` и `states` гарантированно согласованы всегда — это
критично для интеграции с любым внешним state-менеджером, который слушает
именно `Stream`.

### b) Реальная защита от диспатча после `close()`, а не только `assert`
`assert(!_closed, ...)` пропадает в release-сборках Flutter. Раньше в
release после `close()` можно было продолжать диспатчить команды. Теперь
все `dispatch*`-методы дополнительно делают явную проверку и возвращают
`DispatchCancelled(CancelReason.storeClosed)` (а `dispatchStream*` — просто
no-op), причём это работает **и в debug, и в release**. Это важно
для сценария "Store живёт вместе с виджетом": можно закрывать Store
в `dispose()`, не боясь гонок с уже запущенными dispatch-вызовами.

### c) `DispatchKind.stream` наконец используется
В `dispatch_event.dart` тип `stream` был объявлен, но `dispatchStream` /
`dispatchStreamWithEffect` никогда не создавали `DispatchEvent` — хук
`onDispatch` (логирование, DevTools, аналитика) просто не видел
Stream-команды. Теперь каждая итерация Stream-команды, в которой реально
произошёл `commit`, порождает `DispatchEvent(kind: DispatchKind.stream)`,
как и у sync/async команд, включая ошибки потока.

### d) Stream-команды больше не эмитят "пустые" обновления
Раньше `dispatchStream`/`dispatchStreamWithEffect` эмитили новое состояние
в `states` на **каждое** событие потока, даже если команда не вызывала
`commit`. При частых потоках (GPS, сокеты) это means лишние перестроения
UI. Добавлен `TrackingWriter` (`lib/src/tracking_writer.dart`) —
он фиксирует, был ли вызван `commit` в текущей итерации, и что было
"before"-состоянием, так что `states` эмитит ровно то, что реально
изменилось.

### e) Сравнение состояний по `==`, а не по `identical`
Раньше эмиссия в `states` определялась через `identical(before, after)`.
Для классов с value-равенством (`Equatable`, `freezed`, ручной `==`,
которые как раз массово используются вместе с Bloc/Riverpod) это давало
лишние срабатывания при `copyWith` с логически теми же полями. Теперь
сравнение идёт по `!=`, что соответствует ожиданиям `buildWhen`/`select`-
подобной оптимизации в экосистеме.

Все остальные файлы ядра (`cancel_token.dart`, `dispatch_event.dart`,
`state_storage.dart`, `state_accessor.dart`, `guarded_writer.dart`,
`i_side_effect.dart`, `i_state_command.dart`, `store_config.dart`,
`store_factory.dart`) не содержали проблем и оставлены без изменений.
Ядро по-прежнему **не зависит от Flutter** — чистый Dart.

## 2. Новый файл: `lib/helm_flutter.dart`

Опциональный адаптер (импортируется отдельно от `helm.dart`, чтобы не
тянуть Flutter в чисто-дартовые проекты/тесты на VM):

- **`HelmController<S, E>`** — одновременно `ChangeNotifier` и
  `ValueListenable<S>`. Подходит и для `ChangeNotifierProvider` (Provider,
  а также Riverpod — `ChangeNotifierProvider` там тоже есть), и для
  голого `ValueListenableBuilder`/GetX. Сам закрывает обёрнутый `StateStore`
  в `dispose()`.
- **`HelmEffectListener<E>`** — декларативный виджет-аналог `BlocListener`:
  подписывается на `store.effects` на время жизни виджета, корректно
  отписывается, не вызывает лишних перерисовок.
- В dartdoc `HelmController` — готовые примеры подключения к Riverpod
  (`StreamProvider`/`ChangeNotifierProvider`) и к `flutter_bloc`
  (мост `Cubit`, транслирующий `store.states` через `emit`) — без
  добавления riverpod/bloc в зависимости самого Helm.

## 3. Новый пример: `lib/helm_flutter_example.dart`

Небольшой `CounterPage`, показывающий `HelmController` +
`HelmEffectListener` + `ValueListenableBuilder` вместе, на основе тех же
`CounterState`/`IncrementCommand` из `helm_example.dart`.
