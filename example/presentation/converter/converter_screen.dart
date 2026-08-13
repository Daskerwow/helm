import 'package:flutter/material.dart';
import 'package:helm/flutter.dart';

import '../../app/di.dart';
import '../../domain/market/curated_symbols.dart';
import '../../features/market/market_state.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  String _from = curatedSymbols[0];
  String _to = curatedSymbols[1];
  final _amountController = TextEditingController(text: '1');

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
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
              'Конвертер',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: HelmSelector<MarketState, Never, List<Ticker>>(
                      deps.marketFeature,
                      selector: (s) => s.orderedTickers,
                      builder: (context, tickers) {
                        if (tickers.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: Text('Загрузка котировок…')),
                          );
                        }
                        final priceFrom = tickers
                            .firstWhere((t) => t.symbol == _from)
                            .price;
                        final priceTo = tickers
                            .firstWhere((t) => t.symbol == _to)
                            .price;
                        final amount =
                            double.tryParse(
                              _amountController.text.replaceAll(',', '.'),
                            ) ??
                            0;
                        final result = (priceFrom == 0 || priceTo == 0)
                            ? 0.0
                            : amount * priceFrom / priceTo;

                        return Column(
                          children: [
                            TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Количество',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _from,
                                    decoration: const InputDecoration(
                                      labelText: 'Из',
                                    ),
                                    items: [
                                      for (final s in curatedSymbols)
                                        DropdownMenuItem(
                                          value: s,
                                          child: Text(symbolTicker(s)),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _from = v!),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  onPressed: () => setState(() {
                                    final tmp = _from;
                                    _from = _to;
                                    _to = tmp;
                                  }),
                                ),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _to,
                                    decoration: const InputDecoration(
                                      labelText: 'В',
                                    ),
                                    items: [
                                      for (final s in curatedSymbols)
                                        DropdownMenuItem(
                                          value: s,
                                          child: Text(symbolTicker(s)),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() => _to = v!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '${amount.toStringAsFixed(4)} ${symbolTicker(_from)}\n≈ ${result.toStringAsFixed(6)} ${symbolTicker(_to)}',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
                    ),
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
