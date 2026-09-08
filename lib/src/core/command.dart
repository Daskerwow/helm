import 'internal/cancel_token.dart';
import 'internal/state_access.dart';
import 'side_effect_command.dart';

/// Мгновенная синхронная мутация состояния — без IO и side-эффектов.
///
/// Должен быть чистой функцией. Гарантированно выполняется атомарно, без
/// `await`, без токена отмены.
///
/// ```dart
/// final class ToggleThemeCommand implements SyncCommand<AppState> {
///   const ToggleThemeCommand();
///   @override
///   AppState execute(AppState current) => current.copyWith(isDark: !current.isDark);
/// }
/// ```
abstract interface class SyncCommand<S> {
  S execute(S current);
}

/// Единичное асинхронное действие без side-эффекта.
///
/// Проверяй `CancelToken.isCancelled` перед каждым `StateWriter.commit` —
/// см. докстринг `CancelToken`.
///
/// ```dart
/// final class FetchUserCommand implements AsyncCommand<UserState> {
///   const FetchUserCommand(this._api);
///   final UserApi _api;
///
///   @override
///   Future<void> execute(reader, writer, cancel) async {
///     final user = await _api.fetchUser();
///     if (cancel.isCancelled) return;
///     writer.commit(reader.current.copyWith(user: user));
///   }
/// }
/// ```
abstract interface class AsyncCommand<S> {
  Future<void> execute(
    StateReader<S> reader,
    StateWriter<S> writer,
    CancelToken cancel,
  );
}

/// Подписка на внешний `Stream`, коммитящая каждое входящее значение.
///
/// Store управляет жизненным циклом подписки: отписывается при
/// `StateStore.close` или при повторном `StateStore.dispatchStream` с той
/// же группой отмены (см. `DispatchKeyed`).
///
/// ```dart
/// final class LocationStreamCommand implements StreamCommand<MapState> {
///   const LocationStreamCommand(this._gps);
///   final GpsService _gps;
///
///   @override
///   Stream<void> execute(reader, writer) =>
///       _gps.positions.map((pos) => writer.commit(reader.current.copyWith(position: pos)));
/// }
///
/// store.dispatchStream(LocationStreamCommand(_gps));
/// store.cancelStream<LocationStreamCommand>();
/// ```
abstract interface class StreamCommand<S> {
  Stream<void> execute(StateReader<S> reader, StateWriter<S> writer);
}

/// Заменяет состояние на заранее известное значение — без отдельного класса
/// команды на каждую тривиальную мутацию.
///
/// ```dart
/// store.dispatchSync(SetStateCommand(FilterZone.all));
/// ```
final class const SetStateCommand<S>(final S next) implements SyncCommand<S> {
  @override
  S execute(S current) => next;
}

/// Вычисляет новое состояние из текущего чистой функцией — `copyWith`-подобные
/// обновления без отдельного класса команды.
///
/// ```dart
/// store.dispatchSync(UpdateStateCommand((s) => s.copyWith(isOpen: !s.isOpen)));
/// ```
final class const UpdateStateCommand<S>(final S Function(S current) update)
    implements SyncCommand<S> {
  @override
  S execute(S current) => update(current);
}

/// Как [SetStateCommand], но дополнительно эмитирует side-эффект.
final class const SetStateWithEffectCommand<S, E>(
  final S next, {
  final E? effect,
}) implements SyncSideEffect<S, E> {
  @override
  SyncSideEffectResult<S, E> execute(S current) => (next, effect);
}

/// Как [UpdateStateCommand], но функция сразу возвращает и состояние, и
/// опциональный эффект — для случаев, когда эффект зависит от результата.
final class const UpdateStateWithEffectCommand<S, E>(
  final SyncSideEffectResult<S, E> Function(S current) update,
) implements SyncSideEffect<S, E> {
  @override
  SyncSideEffectResult<S, E> execute(S current) => update(current);
}

/// Загружает состояние через переданную функцию и коммитит результат целиком.
/// Проверяет отмену после `await`, перед коммитом.
///
/// ```dart
/// store.dispatch(LoadStateCommand(() => repository.fetchFilterZones()));
/// ```
final class const LoadStateCommand<S>(final Future<S> Function() load)
    implements AsyncCommand<S> {
  @override
  Future<void> execute(
    StateReader<S> reader,
    StateWriter<S> writer,
    CancelToken cancel,
  ) async {
    final next = await load();
    if (cancel.isCancelled) return;
    writer.commit(next);
  }
}

/// Эмитирует side-эффект, не трогая состояние — навигация, диалог,
/// аналитическое событие.
final class const EmitEffectCommand<S, E>(final E effect)
    implements SyncSideEffect<S, E> {
  @override
  SyncSideEffectResult<S, E> execute(S current) => (current, effect);
}
