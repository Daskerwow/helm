import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

StackTrace _trace() {
  try {
    throw Exception();
  } catch (_, st) {
    return st;
  }
}

void main() {
  test('LoadableError с разным stackTrace — не равны', () {
    final st1 = _trace();
    final st2 = _trace();

    final a = Loadable<int>.error('same message', st1);
    final b = Loadable<int>.error('same message', st2);

    expect(a == b, isFalse);
  });

  test('LoadableError с одинаковым stackTrace и error — равны', () {
    final st = _trace();
    final a = Loadable<int>.error('x', st);
    final b = Loadable<int>.error('x', st);

    expect(a == b, isTrue);
  });

  test('Loadable.loading протягивает previous', () {
    const loading = Loadable<int>.loading(7);
    expect(loading.valueOrNull, 7);
    expect(loading.isLoading, isTrue);
  });
}
