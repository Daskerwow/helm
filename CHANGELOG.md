# Changelog

Пакет ещё не публиковался — версия `0.1.0` фиксирует первую точку отсчёта
для публичного API. До `1.0.0` следуем практике SemVer для 0.x
(https://semver.org/#spec-item-4): любой `0.x.0` может содержать breaking
changes, `0.x.y` — только багфиксы и документация.

## [0.1.0] — 2026-09-06

Первая версия с формальным версионированием. Ядро и Flutter-мост
существовали и развивались до этого без версий — здесь фиксируется база
для последующих изменений.

### Изменения API, вошедшие в эту версию относительно предыдущей

(незафиксированной) итерации:

- **`HelmFeatureReactive.select()`** — финальная сигнатура без параметра
  `key`. Несколько независимых срезов одной фичи в одном виджете собираются
  в один вызов через `record`-селектор:

```dart
  final (status, ticker) = feature.select((s) => (s.status, s.ticker));
```

Промежуточные варианты (`key: Symbol`, авто-нумерация вызовов) в релиз не
попали.

- **`HelmFeature.release()`** — двойной вызов без парного `acquire()`
  теперь бросает `StateError` во всех сборках, включая release (было:
  тихий no-op в release, падение только в debug через `assert`).
  **Поведенческое изменение**: код, который раньше "проглатывал" эту
  ошибку в проде, теперь будет падать явно и сразу.

- **`HelmFeature.overrideWith()`** — восстановление не в LIFO-порядке
  теперь бросает `StateError` во всех сборках (было: предупреждение только
  в debug, в release — тихое и потенциально некорректное восстановление).

### Известные ограничения на момент релиза

- Test suite отсутствует.
- API может продолжить меняться до `1.0.0` — см. раздел "Стабильность" в
  README.

## [Unreleased]

- (следующие изменения — сюда)
# 0.2.0

Breaking change: `StreamCommand.execute` and `StreamSideEffect.execute` now
receive `CancelToken`. Check it before expensive work and before every
commit; Helm additionally rejects commits after cancellation.

- Fixed the `StateStore.effects` stream: it now forwards every side-effect.
- Completed stream subscriptions are removed from the dispatch registry.
- `HelmFeature.overrideWith` now replaces active Stores correctly.
- Internal implementation types are no longer exported from the public API.
