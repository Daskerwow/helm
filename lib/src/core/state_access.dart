import 'state_storage.dart';

/// Право только на чтение состояния — передаётся запросам и наблюдателям.
abstract interface class StateReader<S> {
  S get current;
}

/// Право только на запись состояния — передаётся командам.
///
/// Принцип минимальных привилегий (ISP): команда не может прочитать
/// устаревший снапшот мимо [StateReader], а наблюдатель не может изменить
/// состояние.
abstract interface class StateWriter<S> {
  /// Фиксирует новое состояние. `StateStore` эмитирует обновление
  /// синхронно, в момент вызова.
  void commit(S nextState);
}

/// Полный доступ: чтение и запись.
abstract interface class IStateAccessor<S>
    implements StateReader<S>, StateWriter<S> {}

/// Адаптер [IStateAccessor] → [StateStorage] — без бизнес-логики.
final class const StateAccessor<S>(final StateStorage<S> _storage)
    implements IStateAccessor<S> {
  @override
  S get current => _storage.read();

  @override
  void commit(S nextState) => _storage.write(nextState);
}
