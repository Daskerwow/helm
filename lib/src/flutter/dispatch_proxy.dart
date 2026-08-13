import 'package:flutter/foundation.dart';

import '../../helm.dart';

/// Пробрасывает весь dispatch-API `StateStore` на объект, который знает,
/// как добраться до актуального `StateStore` (через геттер [dispatchTarget]).
///
/// Композиция вместо наследования: и `HelmController`, и `HelmFeature`
/// подмешивают этот миксин, не становясь при этом друг для друга ни
/// родителем, ни потомком — у них просто общий фрагмент поведения.
///
/// [dispatchTarget] помечен [protected]: это внутренний контракт между
/// миксином и его двумя потребителями, а не часть публичного API, которым
/// пользуется код приложения. Обычный `_`-приватный член здесь не подошёл
/// бы: приватные имена в Dart видны только внутри одного файла-библиотеки,
/// а `HelmController` и `HelmFeature` реализуют этот геттер каждый в своём
/// файле.
mixin DispatchProxy<S, E> {
  /// Store, на который пробрасываются вызовы. У [HelmController] это его
  /// собственное поле `store`; у `HelmFeature` — `store` актуального
  /// контроллера (`currentController.store`).
  @protected
  StateStore<S, E> get dispatchTarget;

  Future<DispatchResult<S>> dispatch(IAsyncCommand<S> command) =>
      dispatchTarget.dispatch(command);

  Future<DispatchResult<S>> dispatchWithEffect(
    IAsyncSideEffect<S, E> command,
  ) => dispatchTarget.dispatchWithEffect(command);

  DispatchResult<S> dispatchSync(ISyncCommand<S> command) =>
      dispatchTarget.dispatchSync(command);

  DispatchResult<S> dispatchSyncWithEffect(ISyncSideEffect<S, E> command) =>
      dispatchTarget.dispatchSyncWithEffect(command);

  void dispatchStream(IStreamCommand<S> command) =>
      dispatchTarget.dispatchStream(command);

  void dispatchStreamWithEffect(IStreamSideEffect<S, E> command) =>
      dispatchTarget.dispatchStreamWithEffect(command);

  void cancel<U>() => dispatchTarget.cancel<U>();

  void cancelAll() => dispatchTarget.cancelAll();

  void cancelStream<U>() => dispatchTarget.cancelStream<U>();
}
