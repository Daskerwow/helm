/// Мост `StateStore` (ядро Helm, `package:helm/helm.dart`) → «голый»
/// Flutter — без сторонних пакетов управления состоянием и без
/// **BuildContext-поиска**: состояние адресуется напрямую через
/// [HelmFeature]-токен, из любого места кода.
///
/// Реактивность построена на тех же примитивах, что и само ядро Flutter —
/// [Listenable]/[ChangeNotifier]/[ValueListenable] — а не поверх `Stream`
/// или стороннего рантайма: [HelmController] реализует [ValueListenable],
/// [HelmBuilder] рендерится через штатный [ValueListenableBuilder],
/// [HelmComputed] — обычный [ChangeNotifier]. Ничего лишнего сверх того,
/// чем и так пользуется каждое Flutter-приложение.
///
/// ### Состав
/// - [HelmFeature] — ленивый глобально адресуемый токен фичи: создаёт и
///   владеет [StateStore], диспатчит команды, читает состояние синхронно
///   (`feature.value`), подписывается (`feature.listen`) — всё без
///   `context`. Поддерживает `autoDispose` для состояния, живущего не
///   дольше экрана, и [HelmFeature.debugActiveFeatures] для поиска забытых
///   `acquire()`/`release()` в тестах.
/// - [HelmController] — внутренний тонкий мост `StateStore` → `ValueListenable`.
/// - `DispatchProxy` — общий миксин, дающий `dispatch*`/`cancel*` методы и
///   [HelmController], и [HelmFeature] без дублирования их тел.
/// - [HelmBuilder] / [HelmSelector] — подписка в дереве виджетов (полная /
///   точечная).
/// - [HelmListener] / [HelmConsumer] — реакция на side-эффекты.
/// - [HelmLoadableBuilder] + `HelmFeatureLoadable.load`/`.watchStream` —
///   готовый `.when()`-стиль и сахар для фич на `Loadable<T>`.
/// - [HelmComputed] / `helmCompute` — производное значение сразу из
///   нескольких фич.
/// - [HelmWidget] / [StatefulHelmWidget] + `feature.watch()`/`.select()`/
///   `.effect()`/`.read()` — короткий синтаксис в духе hooks, без внешней
///   зависимости на `flutter_hooks`.
///
/// ### Какой API выбрать
/// - весь ребилд по всему состоянию → [HelmBuilder] / `feature.watch()`;
/// - ребилд по срезу → [HelmSelector] / `feature.select()`;
/// - из нескольких фич сразу → [HelmComputed];
/// - вне `build()` → `feature.value` / `.listen()`.
///
/// Все четыре виджет-обёртки ([HelmBuilder]/[HelmSelector]/[HelmListener]/
/// [HelmConsumer]) и три reactive-метода (`watch`/`select`/`effect`) — это
/// **один и тот же** внутренний механизм подписки в двух разных
/// синтаксисах (явный `StatefulWidget` вокруг дерева vs. вызов прямо в
/// `build()`), а не два независимых способа решить одну задачу: выбирай по
/// тому, что удобнее в конкретном месте (виджет-обёртка — когда состояние
/// нужно только листу дерева и хочется явной границы; `watch()`/`select()`
/// — когда не хочется заводить лишний уровень вложенности виджетов).
///
/// ### Диспатч из `onPressed`/`Shortcuts`
/// Диспатч — обычный вызов метода токена:
///
/// ```dart
/// ElevatedButton(
///   onPressed: () => counterFeature.dispatchSyncWithEffect(const IncrementCommand(limit: 5)),
///   child: const Text('+1'),
/// )
/// ```
library;

export 'src/flutter/helm_builder.dart';
export 'src/flutter/helm_computed.dart';
export 'src/flutter/helm_controller.dart';
export 'src/flutter/helm_feature.dart';
export 'src/flutter/helm_loadable.dart';
export 'src/flutter/helm_reactive.dart';
