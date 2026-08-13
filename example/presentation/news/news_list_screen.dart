import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/news/news_api.dart';

class NewsListScreen extends StatelessWidget {
  const NewsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Новости',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => context.push(AppRoute.newsSearch),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Поиск по автору'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: HelmLoadableBuilder<List<Article>, Never>(
                deps.newsFeature,
                idle: (context) =>
                    const Center(child: Text('Ничего не загружено')),
                loading: (context, previous) => previous == null
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          _ArticleList(previous),
                          const Align(
                            alignment: Alignment.topCenter,
                            child: LinearProgressIndicator(),
                          ),
                        ],
                      ),
                data: (context, articles) => _ArticleList(articles),
                error: (context, e, st, previous) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ошибка: $e'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () =>
                            deps.newsFeature.load(deps.newsApi.fetchAll),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleList extends StatelessWidget {
  const _ArticleList(this.articles);
  final List<Article> articles;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    return RefreshIndicator(
      onRefresh: () => deps.newsFeature.load(deps.newsApi.fetchAll),
      child: ListView.separated(
        itemCount: articles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final article = articles[i];
          return Card(
            child: ListTile(
              title: Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                article.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () =>
                  context.push(AppRoute.article(article.id), extra: article),
            ),
          );
        },
      ),
    );
  }
}
