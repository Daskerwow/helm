import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../../data/news/news_api.dart';

final class NewsSearchState {
  const NewsSearchState({
    this.authorId = '',
    this.results = const [],
    this.isSearching = false,
  });

  final String authorId;
  final List<Article> results;
  final bool isSearching;

  NewsSearchState copyWith({
    String? authorId,
    List<Article>? results,
    bool? isSearching,
  }) => NewsSearchState(
    authorId: authorId ?? this.authorId,
    results: results ?? this.results,
    isSearching: isSearching ?? this.isSearching,
  );
}

/// Защита от race condition "из коробки": повторный ввод диспатчит эту же
/// команду заново, `StateStore.dispatch` сам отменяет предыдущий
/// незавершённый вызов того же типа команды — устаревший ответ никогда не
/// перезапишет более новый результат.
final class SearchByAuthorCommand implements IAsyncCommand<NewsSearchState> {
  const SearchByAuthorCommand(this._api, this.authorId);

  final NewsApi _api;
  final int authorId;

  @override
  Future<void> execute(
    IStateReader<NewsSearchState> reader,
    IStateWriter<NewsSearchState> writer,
    CancelToken cancel,
  ) async {
    writer.commit(
      reader.current.copyWith(isSearching: true, authorId: '$authorId'),
    );

    final results = await _api.searchByAuthor(authorId);

    if (cancel.isCancelled) return;

    writer.commit(
      reader.current.copyWith(results: results, isSearching: false),
    );
  }
}

/// Фича намеренно НЕ регистрируется в DI — она нужна только пока открыт
/// экран поиска. Экран создаёт её в `initState` и закрывает в `dispose`,
/// это и есть корректный жизненный цикл, а не глобальный синглтон в
/// `main.dart`, который жил бы вечно без причины.
HelmFeature<NewsSearchState, Never> buildNewsSearchFeature() {
  return HelmFeature<NewsSearchState, Never>(
    () => StoreBuilder<NewsSearchState, Never>(const NewsSearchState()).build(),
    autoDispose: true,
  );
}
