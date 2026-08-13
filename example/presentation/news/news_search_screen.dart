import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../app/router.dart';
import '../../features/news/news_search_feature.dart';

/// Фича поиска — с жизненным циклом самого экрана: создаётся в `initState`
/// из `NewsApi`, полученного через `AppScope`, и закрывается в `dispose`.
/// Открыть поиск ещё раз — значит начать с чистого состояния.
class NewsSearchScreen extends StatefulWidget {
  const NewsSearchScreen({super.key});

  @override
  State<NewsSearchScreen> createState() => _NewsSearchScreenState();
}

class _NewsSearchScreenState extends State<NewsSearchScreen> {
  Timer? _debounce;
  late final searchFeature = buildNewsSearchFeature();

  void _onChanged(String raw) {
    final authorId = int.tryParse(raw);
    _debounce?.cancel();
    if (authorId == null) return;
    final newsApi = AppScope.of(context).newsApi;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      searchFeature.dispatch(SearchByAuthorCommand(newsApi, authorId));
    });
  }

  @override
  void dispose() {
    // Явный dispose() у HelmFeature не нужен: `autoDispose: true` в
    // `buildNewsSearchFeature()` сам закрывает Store, когда последний
    // HelmSelector/HelmBuilder-слушатель размонтируется вместе с этим
    // экраном (тот же механизм, что и в остальных autoDispose-фичах).
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Поиск по автору'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'ID автора (1–10)'),
              keyboardType: TextInputType.number,
              onChanged: _onChanged,
            ),
          ),
          HelmSelector<NewsSearchState, Never, bool>(
            searchFeature,
            selector: (s) => s.isSearching,
            builder: (context, isSearching) => isSearching ? const LinearProgressIndicator() : const SizedBox(height: 4),
          ),
          Expanded(
            child: HelmBuilder<NewsSearchState, Never>(
              searchFeature,
              builder: (context, state) => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: state.results.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(state.results[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => context.push(AppRoute.article(state.results[i].id), extra: state.results[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
