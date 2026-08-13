import 'state_storage.dart';

/// Право только на чтение состояния — передаётся запросам и наблюдателям.
abstract interface class IStateReader<S> {
  S get current;
}

/// Право только на запись состояния — передаётся командам.
///
/// Принцип минимальных привилегий (ISP): команда не может прочитать
/// устаревший снапшот мимо [IStateReader], а наблюдатель не может изменить
/// состояние.
abstract interface class IStateWriter<S> {
  /// Фиксирует новое состояние. `StateStore` эмитирует обновление
  /// синхронно, в момент вызова.
  void commit(S nextState);
}

/// Полный доступ: чтение и запись.
abstract interface class IStateAccessor<S>
    implements IStateReader<S>, IStateWriter<S> {}

/// Адаптер [IStateAccessor] → [IStateStorage] — без бизнес-логики.
final class StateAccessor<S> implements IStateAccessor<S> {
  const StateAccessor(this._storage);

  final IStateStorage<S> _storage;

  @override
  S get current => _storage.read();

  @override
  void commit(S nextState) => _storage.write(nextState);
}
