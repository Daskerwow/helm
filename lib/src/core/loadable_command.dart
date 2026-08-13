import 'cancel_token.dart';
import 'loadable.dart';
import 'state_access.dart';
import 'state_effect_command.dart';
import 'state_command.dart';

/// Общее ядро "loading → data / error" для [LoadCommand] и
/// [LoadWithEffectCommand] — обе команды делают ровно один и тот же цикл
/// запросов к [load], отличаясь только тем, что происходит с результатом
/// (проброс исключения дальше vs. превращение в side-эффект). Раньше это
/// был один и тот же try/catch, дословно продублированный в двух классах.
///
/// [onData]/[onError] вызываются уже ПОСЛЕ соответствующего коммита — им
/// остаётся только решить, что делать с результатом на уровне конкретной
/// команды (ничего, rethrow, side-эффект).
Future<void> _runLoadable<T>({
  required IStateReader<Loadable<T>> reader,
  required IStateWriter<Loadable<T>> writer,
  required CancelToken cancel,
  required Future<T> Function() load,
  required void Function(T value) onData,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  final previous = reader.current.valueOrNull;
  writer.commit(Loadable.loading(previous));

  try {
    final value = await load();
    if (cancel.isCancelled) return;

    writer.commit(Loadable.data(value));
    onData(value);
  } catch (e, st) {
    if (cancel.isCancelled) return;

    writer.commit(Loadable.error(e, st, previous));
    onError(e, st);
  }
}

/// Запускает загрузку и проводит [Loadable] через `loading → data / error`.
/// Предыдущее успешное значение переносится в [Loadable.loading] и, при
/// неудаче, в [Loadable.error] — старые данные остаются видимыми на время
/// повторной загрузки.
///
/// Исключение из [load] перебрасывается дальше *после* обновления состояния
/// на [Loadable.error] — `onError`/`DispatchFailure` продолжают работать как
/// для любой другой async-команды.
///
/// ```dart
/// store.dispatch(LoadCommand(() => api.fetchTodos()));
/// ```
final class LoadCommand<T> implements IAsyncCommand<Loadable<T>> {
  const LoadCommand(this.load);
  final Future<T> Function() load;

  @override
  Future<void> execute(
    IStateReader<Loadable<T>> reader,
    IStateWriter<Loadable<T>> writer,
    CancelToken cancel,
  ) => _runLoadable<T>(
    reader: reader,
    writer: writer,
    cancel: cancel,
    load: load,
    onData: (_) {},
    // Сохраняем оригинальный stack trace, хотя rethrow здесь синтаксически
    // невозможен (мы уже не в блоке catch самой команды, а в колбэке).
    onError: (e, st) => Error.throwWithStackTrace(e, st),
  );
}

/// Как [LoadCommand], но ошибка превращается в side-эффект (например,
/// показ SnackBar) вместо переброса исключения.
final class LoadWithEffectCommand<T, E>
    implements IAsyncSideEffect<Loadable<T>, E> {
  const LoadWithEffectCommand(this.load, {this.onSuccess, this.onError});

  final Future<T> Function() load;
  final E? Function(T value)? onSuccess;
  final E? Function(Object error, StackTrace stackTrace)? onError;

  @override
  Future<E?> execute(
    IStateReader<Loadable<T>> reader,
    IStateWriter<Loadable<T>> writer,
    CancelToken cancel,
  ) async {
    E? effect;

    await _runLoadable<T>(
      reader: reader,
      writer: writer,
      cancel: cancel,
      load: load,
      onData: (value) => effect = onSuccess?.call(value),
      onError: (e, st) => effect = onError?.call(e, st),
    );

    return effect;
  }
}

/// Подписывается на внешний `Stream<T>` и отражает его в [Loadable]: каждое
/// значение — [Loadable.data], ошибка потока — [Loadable.error] (подписка
/// не завершается, поток продолжает слушаться — самовосстанавливающееся
/// соединение).
///
/// В отличие от [LoadCommand], `loading` коммитится только при первой
/// подписке без данных (см. [execute]) — поток шлёт значения часто, и
/// мигать в `loading` перед каждым было бы UI-шумом.
///
/// Если фабрика [source] бросает исключение синхронно (например, невалидные
/// параметры URL при построении WebSocket) — оно перехватывается: состояние
/// переходит в [Loadable.error], а наружу возвращается `Stream.error(...)`,
/// который `StateStore` обработает обычным путём вместо необработанного
/// исключения из `StateStore.dispatchStream`.
///
/// ```dart
/// store.dispatchStream(WatchCommand(() => socket.messages));
/// ```
final class WatchCommand<T> implements IStreamCommand<Loadable<T>> {
  const WatchCommand(this.source);

  /// Строит `Stream` при каждой подписке, а не готовый `Stream`, чтобы
  /// повторный `StateStore.dispatchStream` пересоздавал подписку с нуля.
  final Stream<T> Function() source;

  @override
  Stream<void> execute(
    IStateReader<Loadable<T>> reader,
    IStateWriter<Loadable<T>> writer,
  ) {
    if (reader.current is! LoadableData<T>) {
      writer.commit(Loadable.loading(reader.current.valueOrNull));
    }

    final Stream<T> stream;

    try {
      stream = source();
    } catch (e, st) {
      writer.commit(Loadable.error(e, st, reader.current.valueOrNull));
      return Stream<void>.error(e, st);
    }

    return stream
        .map((value) => writer.commit(Loadable.data(value)))
        .handleError(
          (Object e, StackTrace st) =>
              writer.commit(Loadable.error(e, st, reader.current.valueOrNull)),
        );
  }
}
