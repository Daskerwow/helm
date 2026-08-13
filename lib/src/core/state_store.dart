import 'dart:async';

import 'internal/callback_list.dart';
import 'internal/guarded_writer.dart';
import 'internal/tracking_writer.dart';
import 'internal/emitting_writer.dart';
import 'state_storage.dart';
import 'state_access.dart';
import 'cancel_token.dart';
import 'dispatch.dart';
import 'equality.dart';
import 'middleware.dart';
import 'state_command.dart';
import 'state_effect_command.dart';

typedef _AsyncBody<E> = Future<E?> Function(CancelToken token);
typedef _SyncBody<E> = E? Function();

/// Активная stream-подписка вместе с лейблом команды, её породившей.
///
/// Лейбл нужен отдельно от самой подписки: в момент отмены (вытеснение
/// новым [StateStore.dispatchStream]/[StateStore.dispatchStreamWithEffect]
/// той же группы, явный [StateStore.cancelStream] или [StateStore.close])
/// самой команды уже нет под рукой — её видел только `execute()` в момент
/// подписки — а [DispatchEvent] требует `commandLabel`.
final class _ActiveStreamSubscription {
  const _ActiveStreamSubscription(this.subscription, this.label);
  final StreamSubscription<void> subscription;
  final String label;
}

/// Четыре независимых канала синхронной публикации [StateStore]: изменения
/// состояния, side-эффекты, исходы диспатча, необработанные исключения.
///
/// Выделено в отдельный класс, а не как четыре поля прямо в [StateStore],
/// чтобы Store отвечал только за оркестрацию диспатча (создание writer'ов,
/// управление токенами отмены, подписки на Stream-команды), а не совмещал
/// это с хранением/итерацией/компактизацией четырёх списков слушателей —
/// отдельная, самодостаточная забота (Single Responsibility).
///
/// [CallbackList] вместо простого `List<...>`: методы ниже вызываются на
/// **каждый** commit/dispatch/effect — при высокочастотных источниках
/// (тикер котировок, IMU, live-курсор) `for (final l in List.of(listeners))`
/// аллоцировал бы новый список на каждую публикацию. [CallbackList]
/// итерирует по внутреннему массиву без копирования — см. её докстринг.
///
/// ### Изоляция ошибок между слушателями
///
/// `notifyChange`/`notifyEffect`/`notifyDispatch` изолируют исключения
/// каждого отдельного слушателя через `CallbackList.notify(onError: ...)`:
/// упавший аналитический хук или сломанный логгер не должен помешать
/// доставить событие остальным подписчикам (`HelmController`, другим
/// `addOnChanged`-колбэкам и т.д.) — раньше первое же исключение обрывало
/// весь проход `CallbackList.notify`. Перехваченная ошибка репортится в
/// канал [errors] ([addErrorListener] в `StateStore`), что даёт ей ровно
/// одного полноценного адресата вместо молчаливого поглощения.
///
/// `errors`-канал — особый случай: если сам слушатель ошибок бросает
/// исключение, дальнейшая эскалация невозможна (адресовать её больше
/// некуда) — [_reportListenerError] ловит и такой случай, печатая
/// debug-only подсказку тем же способом, что и `GuardedWriter`, вместо
/// падения всего Store.
final class _ListenerHub<S, E> {
  final changes = CallbackList<void Function(S state)>();
  final effects = CallbackList<void Function(E effect)>();
  final dispatches = CallbackList<void Function(DispatchEvent<S> event)>();
  final errors =
      CallbackList<void Function(Object error, StackTrace stackTrace)>();

  /// Реентрантный гард: `true`, пока мы уже внутри [_reportListenerError] —
  /// не даёт исключению из самого error-слушателя запустить рекурсивный
  /// повторный отчёт.
  bool _reportingError = false;

  void notifyChange(S state) =>
      changes.notify((l) => l(state), onError: _reportListenerError);

  void notifyEffect(E effect) =>
      effects.notify((l) => l(effect), onError: _reportListenerError);

  void notifyDispatch(DispatchEvent<S> event) =>
      dispatches.notify((l) => l(event), onError: _reportListenerError);

  void notifyError(Object error, StackTrace stackTrace) =>
      errors.notify((l) => l(error, stackTrace), onError: _reportListenerError);

  void _reportListenerError(Object error, StackTrace stackTrace) {
    if (_reportingError) {
      assert(() {
        // ignore: avoid_print
        print(
          'Helm: слушатель канала errors сам бросил исключение — '
          'дальнейшая эскалация невозможна: $error',
        );
        return true;
      }());
      return;
    }

    _reportingError = true;
    try {
      errors.notify((l) => l(error, stackTrace));
    } catch (_) {
      // errors.notify() здесь вызван без onError — если он всё же
      // пробросил исключение (например, только один listener и он упал),
      // адресовать его больше некуда; проглатываем осознанно, а не роняем
      // Store из-за диагностики.
    } finally {
      _reportingError = false;
    }
  }

  void clear() {
    changes.clear();
    effects.clear();
    dispatches.clear();
    errors.clear();
  }
}

/// Центральный Store — единственная точка входа для чтения состояния и
/// диспатча команд.
///
/// **Не знает ничего о Flutter или о каком-либо конкретном UI-фреймворке**:
/// весь файл — чистый Dart без единого импорта из `package:flutter`. Это
/// не случайность, а инвариант архитектуры (Dependency Inversion): любой
/// мост к конкретному фреймворку (см. `package:helm/flutter.dart`) зависит
/// от `StateStore`, а не наоборот. Store можно использовать в CLI, на
/// сервере (`dart:io`), в изоляте — где угодно, где есть Dart.
///
/// ### Матрица dispatch-методов
///
/// |        | без эффекта             | с эффектом                  |
/// |--------|--------------------------|-------------------------------|
/// | Stream | [dispatchStream]         | [dispatchStreamWithEffect]   |
/// | Async  | [dispatch]               | [dispatchWithEffect]         |
/// | Sync   | [dispatchSync]           | [dispatchSyncWithEffect]     |
///
/// Каждая пара реализована через общий приватный метод ([_dispatchAsync],
/// [_dispatchStream], [_dispatchSyncInternal]) — единственное отличие
/// внутри пары в том, возвращает ли `execute()` команды ещё и side-эффект.
///
/// ### Реактивность — прямые синхронные слушатели, без `Stream`-накладных
///
/// [addOnChanged]/[addOnEffect]/[addDispatchListener]/[addErrorListener] —
/// тот же паттерн Observer, на котором построен `ChangeNotifier` в самом
/// ядре Flutter: список колбэков, вызываемых синхронно, без буферизации в
/// микрозадаче. Регистрация возвращает функцию отписки — снять слушателя
/// можно без хранения отдельного объекта подписки:
///
/// ```dart
/// final unsubscribe = store.addOnChanged((s) => print(s));
/// // ...
/// unsubscribe();
/// ```
///
/// [states]/[effects] — тонкая надстройка поверх того же механизма как
/// обычный `Stream`, для интеропа с кодом, ожидающим `Stream` (например,
/// `StreamBuilder` вне Flutter-моста, `await for`). [states] дополнительно
/// "seed"-ит каждого нового подписчика текущим состоянием (см. докстринг
/// геттера) — [effects] остаётся чистым потоком событий, без семантики
/// "текущего значения".
///
/// ### Middleware
///
/// [addMiddleware] — именованная альтернатива [addDispatchListener] для
/// кросс-катаных забот (логирование, аналитика, DevTools-мост), которые
/// удобнее оформить отдельным классом [StoreMiddleware], а не анонимным
/// замыканием на месте вызова. Внутри это тонкая обёртка: не даёт новых
/// возможностей сверх [addDispatchListener], только форму.
///
/// ### Согласованность
///
/// [state] (синхронное чтение) и [states]/[addOnChanged] всегда
/// согласованы: любой успешный `IStateWriter.commit` публикуется сразу в
/// момент вызова, независимо от итогового исхода dispatch'а и от того,
/// сколько раз команда коммитит за одно выполнение.
///
/// ### Изоляция ошибок слушателей
///
/// Исключение одного слушателя [addOnChanged]/[addOnEffect]/
/// [addDispatchListener]/[addErrorListener] не мешает доставить событие
/// остальным — см. докстринг `_ListenerHub`. Это касается только
/// *слушателей самого Store*: исключение внутри команды (`execute()`)
/// по-прежнему приводит к [DispatchFailure] обычным путём.
///
/// ### Жизненный цикл
/// 1. Создать через конструктор или `StoreBuilder`.
/// 2. Подписаться через [addOnChanged]/[addOnEffect] или [states]/[effects].
/// 3. Диспатчить команды.
/// 4. Вызвать [close] при уничтожении.
final class StateStore<S, E> {
  /// Создаёт Store с начальным состоянием. Если [storage] не передан —
  /// [StateMemoryStorage].
  ///
  /// [logStreamEvents] — по умолчанию `true`: каждая итерация активной
  /// Stream-команды с изменением состояния порождает [DispatchEvent] в
  /// [addDispatchListener]. На публикацию состояния это не влияет — она
  /// происходит всегда, на каждый реальный коммит.
  ///
  /// [_onDroppedCommit] — см. `GuardedWriter`, раздел "Диагностика
  /// отброшенного коммита": опциональный хук для коммитов, отброшенных
  /// из-за коммита после отмены async-команды, работающий и в release.
  StateStore({
    required S initialState,
    IStateStorage<S>? storage,
    bool Function(S a, S b)? equals,
    this.logStreamEvents = true,
    this._onDroppedCommit,
  }) : _accessor = StateAccessor(storage ?? StateMemoryStorage(initialState)),
       _equals = equals ?? defaultEquals<S>;

  /// Создаёт Store из готового хранилища — начальное состояние берётся из
  /// `storage.read()`.
  StateStore.fromStorage(
    IStateStorage<S> storage, {
    this.logStreamEvents = true,
    bool Function(S a, S b)? equals,
    this._onDroppedCommit,
  }) : _accessor = StateAccessor(storage),
       _equals = equals ?? defaultEquals<S>;

  final StateAccessor<S> _accessor;

  /// Компаратор "состояние не изменилось" — по умолчанию структурное `==`.
  /// Передай свой в конструктор, если `S` — мутируемая коллекция или тип с
  /// дорогим/неверным `==` (см. `listEquals`/`setEquals`/`mapEquals`/
  /// `deepEquals` в `equality.dart`).
  final bool Function(S a, S b) _equals;

  /// См. докстринг конструктора, параметр `onDroppedCommit`.
  final void Function(String commandLabel, S nextState)? _onDroppedCommit;

  final _listeners = _ListenerHub<S, E>();

  /// Кэш [states] — создаётся лениво один раз, `Stream.multi` сам заново
  /// прогоняет свой колбэк на каждого нового подписчика (см. геттер).
  Stream<S>? _states;

  /// Активные per-listener контроллеры [states] — нужны, чтобы [close]
  /// мог явно завершить (`.close()`) каждый из них; без этого подписчики
  /// [states] не получили бы `done`-событие при закрытии Store.
  final _stateStreamControllers = <MultiStreamController<S>>{};

  StreamController<E>? _effectsController;

  final _streamSubs = <Object, _ActiveStreamSubscription>{};
  final _cancelTokens = <Object, CancelToken>{};

  bool _closed = false;

  /// См. докстринг конструктора.
  final bool logStreamEvents;

  // ── Реактивность ─────────────────────────────────────────────────────────

  /// Регистрирует слушателя каждого реального изменения состояния —
  /// сравнение по компаратору из конструктора. Возвращает функцию отписки.
  void Function() addOnChanged(void Function(S state) listener) {
    _listeners.changes.add(listener);
    return () => _listeners.changes.remove(listener);
  }

  /// Регистрирует слушателя каждого эмитированного side-эффекта. Возвращает
  /// функцию отписки.
  void Function() addOnEffect(void Function(E effect) listener) {
    _listeners.effects.add(listener);
    return () => _listeners.effects.remove(listener);
  }

  /// Регистрирует слушателя каждого dispatch — при успехе, ошибке и отмене.
  /// Несколько независимых слушателей (логи + аналитика + Sentry) не
  /// конфликтуют друг с другом. Возвращает функцию отписки.
  ///
  /// Видит отмену/вытеснение и async-, и Stream-команд — оба пути эмитируют
  /// [DispatchEvent] с `cancelReason` через один и тот же механизм.
  void Function() addDispatchListener(
    void Function(DispatchEvent<S> event) listener,
  ) {
    _listeners.dispatches.add(listener);
    return () => _listeners.dispatches.remove(listener);
  }

  /// Именованная альтернатива [addDispatchListener] — см. докстринг класса,
  /// раздел "Middleware", и [StoreMiddleware]. Возвращает функцию отписки.
  void Function() addMiddleware(StoreMiddleware<S> middleware) =>
      addDispatchListener(middleware.onDispatch);

  /// Регистрирует слушателя необработанных исключений внутри dispatch —
  /// вызывается дополнительно к возврату [DispatchFailure]. Возвращает
  /// функцию отписки.
  void Function() addErrorListener(
    void Function(Object error, StackTrace stackTrace) listener,
  ) {
    _listeners.errors.add(listener);
    return () => _listeners.errors.remove(listener);
  }

  /// Broadcast-`Stream` состояний — интероп-слой поверх [addOnChanged] для
  /// кода, ожидающего `Stream` (`StreamBuilder`, `await for`).
  ///
  /// В отличие от [effects], каждый новый подписчик сразу получает текущее
  /// [state] первым событием потока, а дальше — каждое изменение, как и
  /// [addOnChanged]. Без этого поздний подписчик (обычный сценарий:
  /// `StreamBuilder` создаётся уже после первых изменений Store) не увидел
  /// бы уже актуальное состояние вплоть до следующего коммита — типичный
  /// источник "пустого экрана до первого чужого действия" в UI поверх
  /// `Stream`. Реализовано через `Stream.multi`: колбэк выполняется заново
  /// для каждого отдельного подписчика, поэтому "seed" не смешивается
  /// между разными слушателями брошенного broadcast-потока.
  Stream<S> get states => _states ??= Stream<S>.multi((controller) {
    if (_closed) {
      controller.close();
      return;
    }

    controller.add(_accessor.current);
    _stateStreamControllers.add(controller);

    final unsubscribe = addOnChanged(controller.add);
    controller.onCancel = () {
      unsubscribe();
      _stateStreamControllers.remove(controller);
    };
  }, isBroadcast: true);

  /// Broadcast-`Stream` side-эффектов — интероп-слой поверх [addOnEffect].
  /// Чистый поток событий: в отличие от [states], не несёт "текущего
  /// значения" и ничего не отправляет новому подписчику при подписке.
  Stream<E> get effects {
    final controller = _effectsController ??= StreamController<E>.broadcast(
      sync: true,
    );
    return controller.stream;
  }

  /// Текущее состояние — синхронное чтение без подписки.
  S get state => _accessor.current;

  /// Store закрыт и больше не принимает команды.
  bool get isClosed => _closed;

  /// Принудительно заменяет состояние, минуя обычный dispatch-цикл (без
  /// [DispatchEvent], без проверки [isClosed]) — **только для тестов**.
  /// Публикует изменение, если значение реально отличается.
  ///
  /// Префикс `debug` — как `debugPrint`/`debugDumpApp` в самом Flutter SDK:
  /// сигнализирует "не для продакшен-кода", делая случайное использование
  /// в обычной команде/сервисе заметным при code review и легко находимым
  /// поиском по имени.
  ///
  /// ```dart
  /// store.debugResetForTesting(Loadable.data(fakeTodos));
  /// expect(store.state.valueOrNull, fakeTodos);
  /// ```
  void debugResetForTesting(S state) {
    final before = _accessor.current;
    _accessor.commit(state);
    _publishIfChanged(before);
  }

  // ── Stream dispatch ─────────────────────────────────────────────────────

  /// Подписывается на Stream-команду без side-эффектов. Если команда с той
  /// же группой отмены (см. `DispatchKeyed`) уже активна — предыдущая
  /// подписка отменяется первой (см. [_cancelStreamSubscription]). После
  /// [close] — no-op.
  void dispatchStream(IStreamCommand<S> command) =>
      _dispatchStream(command, (writer) => command.execute(_accessor, writer));

  /// Подписывается на Stream-команду с side-эффектами. Та же семантика
  /// отмены предыдущей подписки, что и у [dispatchStream].
  void dispatchStreamWithEffect(IStreamSideEffect<S, E> command) =>
      _dispatchStream(
        command,
        (writer) => command.execute(_accessor, writer).map((effect) {
          if (effect != null) _listeners.notifyEffect(effect);
        }),
      );

  /// Общее ядро [dispatchStream]/[dispatchStreamWithEffect]: отменяет
  /// предыдущую подписку той же группы, заводит общий [TrackingWriter] и
  /// подписывается на поток, который [execute] строит поверх него. Разница
  /// между двумя публичными методами — только в том, публикует ли [execute]
  /// side-эффект на каждый элемент потока.
  void _dispatchStream(
    Object command,
    Stream<void> Function(TrackingWriter<S> writer) execute,
  ) {
    if (_closed) return;

    final key = _keyOf(command);
    _cancelStreamSubscription(key, CancelReason.superseded);

    final writer = TrackingWriter<S>(_emittingWriter(), _accessor);

    _subscribeStream(key, _labelOf(command), execute(writer), writer);
  }

  // ── Async dispatch ──────────────────────────────────────────────────────

  /// Отправляет асинхронную команду. Если команда с той же группой отмены
  /// уже выполняется — предыдущая отменяется с [CancelReason.superseded].
  /// После [close] немедленно возвращает
  /// `DispatchCancelled(CancelReason.storeClosed)`, не запуская команду.
  Future<DispatchResult<S>> dispatch(IAsyncCommand<S> command) =>
      _dispatchAsync(command, (writer, token) async {
        await command.execute(_accessor, writer, token);
        return null;
      });

  /// Как [dispatch], но с side-эффектом.
  Future<DispatchResult<S>> dispatchWithEffect(
    IAsyncSideEffect<S, E> command,
  ) => _dispatchAsync(
    command,
    (writer, token) => command.execute(_accessor, writer, token),
  );

  /// Общее ядро [dispatch]/[dispatchWithEffect]: строит защищённый от
  /// коммитов-после-отмены writer ([GuardedWriter] поверх [EmittingWriter])
  /// и прогоняет его через [_runAsync]. Разница между двумя публичными
  /// методами — только в том, возвращает ли `execute()` команды ещё и
  /// side-эффект.
  Future<DispatchResult<S>> _dispatchAsync(
    Object command,
    Future<E?> Function(IStateWriter<S> writer, CancelToken token) execute,
  ) {
    if (_closed) {
      return Future.value(DispatchCancelled<S>(CancelReason.storeClosed));
    }

    final label = _labelOf(command);

    return _runAsync(
      _keyOf(command),
      label,
      (token) => execute(_guardedWriter(token, label), token),
    );
  }

  // ── Sync dispatch ───────────────────────────────────────────────────────

  /// Отправляет синхронную команду. Выполняется мгновенно, не может быть
  /// отменена. После [close] немедленно возвращает
  /// `DispatchCancelled(CancelReason.storeClosed)`.
  DispatchResult<S> dispatchSync(ISyncCommand<S> command) =>
      _dispatchSyncInternal(
        command,
        () => (command.execute(_accessor.current), null),
      );

  /// Как [dispatchSync], но с side-эффектом.
  DispatchResult<S> dispatchSyncWithEffect(ISyncSideEffect<S, E> command) =>
      _dispatchSyncInternal(command, () => command.execute(_accessor.current));

  /// Общее ядро [dispatchSync]/[dispatchSyncWithEffect].
  DispatchResult<S> _dispatchSyncInternal(
    Object command,
    SyncSideEffectResult<S, E> Function() run,
  ) {
    if (_closed) return DispatchCancelled<S>(CancelReason.storeClosed);

    return _runSync(_labelOf(command), () {
      final (next, effect) = run();
      _accessor.commit(next);
      return effect;
    });
  }

  // ── Управление жизненным циклом ─────────────────────────────────────────

  /// Отменяет активную async-команду по типу `U` — работает для команд без
  /// собственного `DispatchKeyed.dispatchKey` (обычный случай, когда группа
  /// отмены — это `runtimeType`). Для кастомного ключа используй [cancelKey].
  void cancel<U>() => cancelKey(U);

  /// Отменяет активную async-команду по явному ключу — см. `DispatchKeyed`.
  void cancelKey(Object key) =>
      _cancelTokens[key]?.cancel(CancelReason.userRequested);

  /// Отменяет все активные async-команды. Уже завершённые не затрагиваются.
  void cancelAll() {
    for (final token in _cancelTokens.values) {
      token.cancel(CancelReason.userRequested);
    }
  }

  /// Отменяет активную stream-подписку по типу `U` — см. [cancel]. Как и
  /// отмена async-команды, эмитирует [DispatchEvent] с
  /// `cancelReason: CancelReason.userRequested` в [addDispatchListener].
  void cancelStream<U>() => cancelStreamKey(U);

  /// Отменяет активную stream-подписку по явному ключу — см. [cancelKey].
  void cancelStreamKey(Object key) =>
      _cancelStreamSubscription(key, CancelReason.userRequested);

  /// Освобождает все ресурсы: отменяет активные async-команды и
  /// stream-подписки, снимает всех слушателей, закрывает [states]/[effects].
  ///
  /// Повторный вызов — no-op. После вызова все `dispatch*`-методы
  /// возвращают `DispatchCancelled(CancelReason.storeClosed)` (или ничего не
  /// делают для Stream-варианта), не бросая исключений — это позволяет
  /// безопасно вызывать [close] из владельца жизненного цикла даже если
  /// где-то ещё "в полёте" остался вызов dispatch.
  void close() {
    if (_closed) return;
    _closed = true;

    for (final token in _cancelTokens.values) {
      token.cancel(CancelReason.storeClosed);
    }

    for (final key in _streamSubs.keys.toList(growable: false)) {
      _cancelStreamSubscription(key, CancelReason.storeClosed);
    }

    _cancelTokens.clear();
    _listeners.clear();

    for (final controller in _stateStreamControllers) {
      controller.close();
    }
    _stateStreamControllers.clear();

    _effectsController?.close();
  }

  // ── Приватное ядро ──────────────────────────────────────────────────────

  /// Собирает стандартный писатель "закоммитил → опубликовал" — общая
  /// точка входа для [_dispatchAsync] (обёрнутый в [GuardedWriter]) и
  /// [_dispatchStream] (обёрнутый в [TrackingWriter]).
  EmittingWriter<S> _emittingWriter() =>
      EmittingWriter<S>(_accessor, _listeners.notifyChange, _equals);

  /// [EmittingWriter], защищённый от коммитов после отмены токена — то, что
  /// нужно любой async-команде (см. [_dispatchAsync]).
  GuardedWriter<S> _guardedWriter(CancelToken token, String label) =>
      GuardedWriter<S>(
        _emittingWriter(),
        token,
        label,
        onDroppedCommit: _onDroppedCommit,
      );

  /// Ключ группировки dispatch/cancel — по умолчанию `runtimeType` (в Dart
  /// дженерики реифицированы, коллизий между разными инстанциациями
  /// generic-класса нет). См. `DispatchKeyed` для кастомного ключа.
  Object _keyOf(Object command) =>
      command is DispatchKeyed ? command.dispatchKey : command.runtimeType;

  /// Имя команды для [DispatchEvent]/диагностики — см. `DispatchLabeled`.
  String _labelOf(Object command) => command is DispatchLabeled
      ? command.dispatchLabel
      : command.runtimeType.toString();

  DispatchEvent<S> _buildEvent({
    required String label,
    required S before,
    required DispatchKind kind,
    Duration? elapsed,
    Object? error,
    CancelReason? cancelReason,
  }) => DispatchEvent<S>(
    commandLabel: label,
    before: before,
    after: _accessor.current,
    kind: kind,
    elapsed: elapsed,
    error: error,
    cancelReason: cancelReason,
  );

  /// Единое ядро для всех async-диспатчей: управляет токеном, замеряет
  /// время (только если есть кому его показать), публикует эффект и
  /// уведомляет [addDispatchListener] при любом исходе.
  Future<DispatchResult<S>> _runAsync(
    Object key,
    String label,
    _AsyncBody<E> body,
  ) async {
    final token = _acquireToken(key);
    final before = _accessor.current;
    final watch = _listeners.dispatches.isEmpty ? null : (Stopwatch()..start());

    try {
      final effect = await body(token);
      watch?.stop();

      // Публикация уже произошла синхронно внутри EmittingWriter на каждый
      // commit — здесь дополнительная эмиссия не нужна ни при каком исходе.
      if (token.isCancelled) {
        _listeners.notifyDispatch(
          _buildEvent(
            label: label,
            before: before,
            kind: DispatchKind.async,
            elapsed: watch?.elapsed,
            cancelReason: token.reason,
          ),
        );

        return DispatchCancelled(token.reason!);
      }

      if (effect != null) _listeners.notifyEffect(effect);

      _listeners.notifyDispatch(
        _buildEvent(
          label: label,
          before: before,
          kind: DispatchKind.async,
          elapsed: watch?.elapsed,
        ),
      );

      return DispatchSuccess(_accessor.current);
    } catch (e, st) {
      watch?.stop();

      _listeners.notifyError(e, st);

      _listeners.notifyDispatch(
        _buildEvent(
          label: label,
          before: before,
          kind: DispatchKind.async,
          elapsed: watch?.elapsed,
          error: e,
        ),
      );

      return DispatchFailure(e, st);
    } finally {
      _releaseToken(key, token);
    }
  }

  /// Единое ядро для sync-диспатчей. Sync-команды атомарны (чистая функция →
  /// один коммит), поэтому исключение внутри [body] гарантированно
  /// происходит до коммита.
  DispatchResult<S> _runSync(String label, _SyncBody<E> body) {
    final before = _accessor.current;

    try {
      final effect = body();

      _publishIfChanged(before);

      if (effect != null) _listeners.notifyEffect(effect);
      _listeners.notifyDispatch(
        _buildEvent(label: label, before: before, kind: DispatchKind.sync),
      );

      return DispatchSuccess(_accessor.current);
    } catch (e, st) {
      _listeners.notifyError(e, st);

      _listeners.notifyDispatch(
        _buildEvent(
          label: label,
          before: before,
          kind: DispatchKind.sync,
          error: e,
        ),
      );

      return DispatchFailure(e, st);
    }
  }

  /// Общая логика подписки на stream-команды. Эмитирует [DispatchEvent]
  /// только на итерациях, где команда реально закоммитила ЧТО-ТО ОТЛИЧНОЕ
  /// от состояния на начало итерации (см. [_equals] ниже) — публикация
  /// состояния в [addOnChanged] от этого не зависит, она уже сделана
  /// [EmittingWriter] на каждый отдельный коммит по тому же компаратору.
  ///
  /// `writer.hasChanged` сам по себе фиксирует лишь факт вызова
  /// `IStateWriter.commit` хоть раз за итерацию — не то же самое, что
  /// "состояние реально другое": [EmittingWriter] может не опубликовать
  /// коммит, если `_equals(next, last)`, а [TrackingWriter] всё равно
  /// отметит `hasChanged = true`. Без явной проверки `!_equals(...)` здесь
  /// в лог утекали бы "пустые" stream-события, где `before == after` по
  /// собственному компаратору Store.
  void _subscribeStream(
    Object key,
    String label,
    Stream<void> stream,
    TrackingWriter<S> writer,
  ) {
    // Команда могла синхронно закоммитить до подписки на поток (например,
    // начальный Loadable.loading в WatchCommand). Публикация уже
    // произошла — здесь лишь логируем этот "нулевой" цикл отдельно от
    // первого элемента потока.
    if (writer.hasChanged) {
      _logStreamCycle(label, writer);
    }

    final subscription = stream.listen(
      (_) {
        if (writer.hasChanged) _logStreamCycle(label, writer);
      },
      onError: (Object e, StackTrace st) {
        _listeners.notifyError(e, st);

        _listeners.notifyDispatch(
          _buildEvent(
            label: label,
            before: _accessor.current,
            kind: DispatchKind.stream,
            error: e,
          ),
        );

        // `effects` намеренно не получает ошибки stream-команд: это только
        // канал side-эффектов. Ошибка сообщается через [addErrorListener]
        // (см. `_listeners.notifyError` выше) и [addDispatchListener], как
        // и ошибка любой другой команды.
      },
      cancelOnError: false,
    );

    _streamSubs[key] = _ActiveStreamSubscription(subscription, label);
  }

  /// Закрывает один цикл "before → after" Stream-команды: сбрасывает
  /// [writer] и, если [logStreamEvents] включён и состояние реально
  /// изменилось, публикует [DispatchEvent].
  void _logStreamCycle(String label, TrackingWriter<S> writer) {
    final before = writer.before;
    writer.reset();

    if (!logStreamEvents || _equals(_accessor.current, before)) return;

    _listeners.notifyDispatch(
      _buildEvent(label: label, before: before, kind: DispatchKind.stream),
    );
  }

  /// Отменяет активную stream-подписку по ключу и эмитирует [DispatchEvent]
  /// с соответствующим [CancelReason] — тот же контракт, что и у отмены
  /// async-команд в [_runAsync]. Без этого [addDispatchListener] вообще не
  /// видел бы отмену/вытеснение stream-команд — асимметрия с async-путём,
  /// где `DispatchCancelled` виден и через возврат [dispatch], и через
  /// [addDispatchListener].
  ///
  /// No-op, если по [key] нет активной подписки (например, повторный
  /// [cancelStreamKey] или отмена уже завершившегося потока).
  void _cancelStreamSubscription(Object key, CancelReason reason) {
    final entry = _streamSubs.remove(key);
    if (entry == null) return;

    entry.subscription.cancel();

    _listeners.notifyDispatch(
      _buildEvent(
        label: entry.label,
        before: _accessor.current,
        kind: DispatchKind.stream,
        cancelReason: reason,
      ),
    );
  }

  /// Публикует состояние, если оно реально изменилось относительно [before]
  /// — используется [_runSync] и [debugResetForTesting], которые делают
  /// ровно один коммит. Async/Stream-диспатчи публикуют на каждый отдельный
  /// коммит через [EmittingWriter] напрямую.
  void _publishIfChanged(S before) {
    if (_closed) return;
    if (_equals(_accessor.current, before)) return;

    _listeners.notifyChange(_accessor.current);
  }

  /// Отменяет предыдущий токен той же группы и создаёт новый.
  CancelToken _acquireToken(Object key) {
    _cancelTokens[key]?.cancel(CancelReason.superseded);

    return _cancelTokens[key] = CancelToken();
  }

  /// Удаляет токен из реестра, если он не был заменён новым.
  void _releaseToken(Object key, CancelToken token) {
    if (_cancelTokens[key] == token) _cancelTokens.remove(key);
  }
}
