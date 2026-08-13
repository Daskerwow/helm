import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

final class _CounterState {
  const _CounterState(this.count);
  final int count;
}

final class _Increment implements ISyncCommand<_CounterState> {
  const _Increment();
  @override
  _CounterState execute(_CounterState current) =>
      _CounterState(current.count + 1);
}

final class _Fail implements IAsyncCommand<_CounterState> {
  const _Fail();
  @override
  Future<void> execute(reader, writer, cancel) async {
    throw StateError('boom');
  }
}

/// Generic-команда — используется, чтобы проверить, что разные
/// инстанциации `_Load<T>` не отменяют друг друга (реифицированные дженерики).
final class _Load<T> implements IAsyncCommand<Loadable<T>> {
  const _Load(this.value, {this.delay = Duration.zero});
  final T value;
  final Duration delay;

  @override
  Future<void> execute(reader, writer, cancel) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (cancel.isCancelled) return;
    writer.commit(Loadable.data(value));
  }
}

/// Команда с явным dispatchKey — параллельные запуски с разным userId не
/// должны вытеснять друг друга.
final class _FetchUser implements IAsyncCommand<String>, DispatchKeyed {
  const _FetchUser(this.userId, this.delay);
  final String userId;
  final Duration delay;

  @override
  Object get dispatchKey => (_FetchUser, userId);

  @override
  Future<void> execute(reader, writer, cancel) async {
    await Future<void>.delayed(delay);
    if (cancel.isCancelled) return;
    writer.commit(userId);
  }
}

void main() {
  group('dispatchSync', () {
    test('коммитит и публикует изменение', () {
      final store = StateStore<_CounterState, Never>(
        initialState: const _CounterState(0),
      );
      final seen = <int>[];
      store.addOnChanged((s) => seen.add(s.count));

      store.dispatchSync(const _Increment());

      expect(store.state.count, 1);
      expect(seen, [1]);
      store.close();
    });

    test('не публикует, если состояние не изменилось (equals)', () {
      final store = StateStore<int, Never>(initialState: 0);
      final seen = <int>[];
      store.addOnChanged(seen.add);

      store.dispatchSync(const SetStateCommand(0));

      expect(seen, isEmpty);
      store.close();
    });
  });

  group('dispatch (async)', () {
    test('DispatchFailure при исключении, error-слушатель вызван', () async {
      final store = StateStore<_CounterState, Never>(
        initialState: const _CounterState(0),
      );
      Object? capturedError;
      store.addErrorListener((e, st) => capturedError = e);

      final result = await store.dispatch(const _Fail());

      expect(result, isA<DispatchFailure<_CounterState>>());
      expect(capturedError, isA<StateError>());
      store.close();
    });

    test('повторный dispatch того же типа отменяет предыдущий', () async {
      final store = StateStore<Loadable<int>, Never>(
        initialState: const Loadable.idle(),
      );

      final first = store.dispatch(
        _Load(1, delay: const Duration(milliseconds: 50)),
      );
      final second = store.dispatch(_Load(2, delay: Duration.zero));

      final firstResult = await first;
      final secondResult = await second;

      expect(firstResult, isA<DispatchCancelled<Loadable<int>>>());
      expect(
        (firstResult as DispatchCancelled).reason,
        CancelReason.superseded,
      );
      expect(secondResult, isA<DispatchSuccess<Loadable<int>>>());
      expect(store.state.valueOrNull, 2);
      store.close();
    });

    test(
      'реификация дженериков: сторы с разными T друг другу не мешают',
      () async {
        final intStore = StateStore<Loadable<int>, Never>(
          initialState: const Loadable.idle(),
        );
        final stringStore = StateStore<Loadable<String>, Never>(
          initialState: const Loadable.idle(),
        );

        final r1 = await intStore.dispatch(_Load<int>(42));
        final r2 = await stringStore.dispatch(_Load<String>('42'));

        expect(r1, isA<DispatchSuccess<Loadable<int>>>());
        expect(r2, isA<DispatchSuccess<Loadable<String>>>());
        expect(intStore.state.valueOrNull, 42);
        expect(stringStore.state.valueOrNull, '42');

        intStore.close();
        stringStore.close();
      },
    );

    test(
      'DispatchKeyed: параллельные запросы с разным ключом не вытесняют друг друга',
      () async {
        final store = StateStore<String, Never>(initialState: '');

        final a = store.dispatch(
          _FetchUser('alice', const Duration(milliseconds: 30)),
        );
        final b = store.dispatch(
          _FetchUser('bob', const Duration(milliseconds: 10)),
        );

        final resultA = await a;
        final resultB = await b;

        expect(resultA, isA<DispatchSuccess<String>>());
        expect(resultB, isA<DispatchSuccess<String>>());
        store.close();
      },
    );
  });

  group('close', () {
    test(
      'после close все dispatch* методы отдают storeClosed, без исключений',
      () async {
        final store = StateStore<_CounterState, Never>(
          initialState: const _CounterState(0),
        );
        store.close();

        final syncResult = store.dispatchSync(const _Increment());
        final asyncResult = await store.dispatch(const _Fail());

        expect(
          (syncResult as DispatchCancelled).reason,
          CancelReason.storeClosed,
        );
        expect(
          (asyncResult as DispatchCancelled).reason,
          CancelReason.storeClosed,
        );
      },
    );

    test('повторный close — no-op', () {
      final store = StateStore<int, Never>(initialState: 0);
      store.close();
      expect(store.close, returnsNormally);
    });
  });

  group('addOnChanged/addDispatchListener', () {
    test('поддерживает несколько независимых слушателей одновременно', () {
      final store = StateStore<_CounterState, Never>(
        initialState: const _CounterState(0),
      );
      final a = <int>[];
      final b = <int>[];
      store.addOnChanged((s) => a.add(s.count));
      store.addOnChanged((s) => b.add(s.count));

      store.dispatchSync(const _Increment());

      expect(a, [1]);
      expect(b, [1]);
      store.close();
    });

    test('отписка через возвращённую функцию работает', () {
      final store = StateStore<_CounterState, Never>(
        initialState: const _CounterState(0),
      );
      final seen = <int>[];
      final unsubscribe = store.addOnChanged((s) => seen.add(s.count));

      store.dispatchSync(const _Increment());
      unsubscribe();
      store.dispatchSync(const _Increment());

      expect(seen, [1]);
      store.close();
    });
  });
}
