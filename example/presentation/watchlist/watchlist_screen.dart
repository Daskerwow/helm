import 'package:flutter/material.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/widgets/asset_row.dart';

/// Никакого локального состояния (поиска/сортировки/контроллеров) нет —
/// поэтому [HelmWidget] (не Stateful-вариант): чистая функция от состояния
/// фичи, без единого `StatefulWidget`.
class WatchlistScreen extends HelmWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    // Набор символов избранного меняется только по клику на звезду — не
    // на каждый тик рынка, поэтому подписка на весь Set тут не проблема.
    final symbols = deps.watchlistFeature.select((s) => s.symbols);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Избранное',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: symbols.isEmpty
                      ? const Center(
                          child: Text(
                            'Пока пусто. Добавьте валюты в избранное на странице «Рынок».',
                            style: TextStyle(color: AppColors.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final sorted = symbols.toList()..sort();
                            return ListView.separated(
                              itemCount: sorted.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) => AssetRow(
                                key: ValueKey(sorted[i]),
                                symbol: sorted[i],
                              ),
                            );
                          },
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
