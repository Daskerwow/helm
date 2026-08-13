import 'package:flutter/material.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/market/curated_symbols.dart';
import '../../features/alerts/alert_feature.dart';
import '../../features/market/market_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _addController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _addAlert(AppDependencies deps) {
    final raw = _addController.text.trim().toLowerCase();
    if (raw.isEmpty) return;
    final symbol = raw.endsWith('usdt') ? raw : '${raw}usdt';
    if (!curatedSymbols.contains(symbol)) {
      setState(
        () => _error =
            'Монета "${symbol.toUpperCase()}" не входит в корзину дашборда',
      );
      return;
    }
    final price = deps.marketFeature.value.priceOf(symbol);
    if (price == null) {
      setState(
        () => _error = 'Котировка для "${symbol.toUpperCase()}" ещё не пришла',
      );
      return;
    }
    deps.alertFeature.dispatchSync(SetThresholdCommand(symbol, price));
    _addController.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Алерты',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: InputDecoration(
                      labelText: 'Тикер, например BTC',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _addAlert(deps),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _addAlert(deps),
                  child: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: HelmSelector<AlertState, AlertEffect, List<String>>(
                    deps.alertFeature,
                    selector: (s) => s.thresholds.keys.toList()..sort(),
                    builder: (context, symbols) {
                      if (symbols.isEmpty) {
                        return const Center(
                          child: Text(
                            'Алерты не настроены',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: symbols.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _AlertRow(symbol: symbols[i]),
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

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);

    // БЫЛО: `max` считался от самого threshold — при драге слайдер менял
    // threshold, тот менял max, max менял позицию — слайдер "не слушался"
    // (визуально дёргался/не реагировал на перетаскивание). ИСПРАВЛЕНО:
    // anchor берётся от ТЕКУЩЕЙ РЫНОЧНОЙ ЦЕНЫ (priceOf) — она не зависит от
    // положения слайдера, поэтому max стабилен на всё время драга.
    return HelmSelector<MarketState, Never, double?>(
      deps.marketFeature,
      key: ValueKey(symbol),
      selector: (s) => s.priceOf(symbol),
      builder: (context, currentPrice) =>
          HelmSelector<AlertState, AlertEffect, double?>(
            deps.alertFeature,
            selector: (s) => s.thresholdOf(symbol),
            builder: (context, threshold) {
              final anchor = currentPrice ?? threshold ?? 1;
              final max = anchor <= 0 ? 1.0 : anchor * 2;
              return ListTile(
                title: Text(symbolLabel(symbol)),
                subtitle: Slider(
                  min: 0,
                  max: max,
                  value: (threshold ?? 0).clamp(0, max),
                  label: formatPrice(threshold ?? 0),
                  onChanged: (v) => deps.alertFeature.dispatchSync(
                    SetThresholdCommand(symbol, v),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => deps.alertFeature.dispatchSync(
                    ClearThresholdCommand(symbol),
                  ),
                ),
              );
            },
          ),
    );
  }
}
