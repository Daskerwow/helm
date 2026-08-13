import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

void main() {
  test('overrideWith: повторный вызов restore — no-op', () {
    final feature = HelmFeature<int, Never>(() => StateStore(initialState: 0));
    feature.value; // создаёт исходный Store

    var bumpCount = 0;
    feature.lifecycle.addListener(() => bumpCount++);

    final restore = feature.overrideWith(() => StateStore(initialState: 99));
    expect(feature.value, 99);
    expect(bumpCount, 1);

    restore();
    expect(bumpCount, 2);

    // Повторный вызов restore — не должен ещё раз пересоздавать Store и
    // бампать lifecycle (регрессия на баг "двойной restore").
    restore();
    expect(bumpCount, 2);
  });

  test('autoDispose закрывает Store, когда refCount уходит в ноль', () {
    final feature = HelmFeature<int, Never>(
      () => StateStore(initialState: 0),
      autoDispose: true,
    );

    final unsubscribe = feature.listen((_) {});
    expect(feature.isActive, isTrue);

    unsubscribe();
    expect(feature.isActive, isFalse);
  });

  test('listen(): вызов disposer дважды безопасен (idempotent)', () {
    final feature = HelmFeature<int, Never>(() => StateStore(initialState: 0));
    final unsubscribe = feature.listen((_) {});

    expect(unsubscribe, returnsNormally);
    expect(unsubscribe, returnsNormally);

    feature.dispose();
  });
}
