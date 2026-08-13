/// Helm — лёгкая, предсказуемая библиотека управления состоянием для Dart.
///
/// Этот файл — **ядро**: чистый Dart, ни одного импорта из `package:flutter`.
/// Store не знает о существовании какого-либо UI-фреймворка или state
/// manager'а — он умеет только одно: принимать команды и синхронно
/// публиковать изменения состояния. Мост во Flutter — отдельный файл,
/// `package:helm/flutter.dart` (см. его докстринг про выбор нужного API).
///
/// ### Три принципа
/// - **Явность** — каждый исход диспатча типизирован через [DispatchResult].
/// - **Разделение прав** — команды получают ровно то, что им нужно:
///   [IStateReader] или [IStateWriter], редко оба сразу.
/// - **Отменяемость** — асинхронные команды прерываются через [CancelToken],
///   исключая race condition при повторных запросах.
///
/// ### Быстрый старт
///
/// ```dart
/// import 'package:helm/helm.dart';
///
/// final store = StoreBuilder<MyState, MyEffect>(MyState.initial())
///     .onChanged((s) => print(s))
///     .onEffect((e) => router.handle(e))
///     .onDispatch((event) => logger.debug(event.toLogString()))
///     .build();
///
/// await store.dispatch(FetchDataCommand(_api));
/// store.close();
/// ```
///
/// ### Ключевые типы
/// - [StateStore] — центральный Store.
/// - [StoreBuilder] — fluent-построитель Store.
/// - [DispatchResult] — [DispatchSuccess] / [DispatchFailure] / [DispatchCancelled].
/// - [CancelToken] — токен отмены асинхронных команд.
/// - [Loadable] — готовое состояние одного асинхронного ресурса + команды
///   [LoadCommand]/[WatchCommand], закрывающие типовой `loading/data/error`.
/// - [StoreMiddleware] — именованная альтернатива `addDispatchListener` для
///   кросс-катаных забот (логирование, аналитика, DevTools-мост).
///
/// ### Сравнение состояний для мутируемых коллекций
///
/// Если `S` (или срез, с которым работает `equals`/`selector`) — `List`/
/// `Set`/`Map`, готовые компараторы `listEquals`/`setEquals`/`mapEquals`/
/// `deepEquals` из `equality.dart` избавляют от ручной реализации
/// содержательного сравнения — см. их докстринги.
library;

export 'src/core/cancel_token.dart';
export 'src/core/dispatch.dart';
export 'src/core/equality.dart';
export 'src/core/loadable.dart';
export 'src/core/loadable_command.dart';
export 'src/core/middleware.dart';
export 'src/core/state_access.dart';
export 'src/core/state_command.dart';
export 'src/core/state_effect_command.dart';
export 'src/core/state_storage.dart';
export 'src/core/state_store.dart';
export 'src/core/store_builder.dart';
export 'src/core/store_config.dart';
