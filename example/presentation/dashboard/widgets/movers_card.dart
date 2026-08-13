import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/market/curated_symbols.dart';
import '../../../domain/market/ticker.dart';

class MoversCard extends StatefulWidget {
  const MoversCard({super.key, required this.gainers, required this.losers});

  final List<Ticker> gainers;
  final List<Ticker> losers;

  @override
  State<MoversCard> createState() => _MoversCardState();
}

class _MoversCardState extends State<MoversCard> {
  bool _showGainers = true;

  @override
  Widget build(BuildContext context) {
    final list = _showGainers ? widget.gainers : widget.losers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Движения рынка',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                _ToggleChip(
                  label: 'Рост',
                  selected: _showGainers,
                  onTap: () => setState(() => _showGainers = true),
                ),
                const SizedBox(width: 6),
                _ToggleChip(
                  label: 'Падение',
                  selected: !_showGainers,
                  onTap: () => setState(() => _showGainers = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Загрузка…',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              for (final t in list)
                InkWell(
                  // push(), а не go() — см. asset_row.dart.
                  onTap: () => context.push(AppRoute.currencyDetail(t.symbol)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.surfaceElevated,
                          child: Text(
                            symbolTicker(t.symbol).substring(0, 1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            symbolTicker(t.symbol),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          formatPrice(t.price),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatPercent(t.changePercent24h),
                          style: TextStyle(
                            color: t.isUp ? AppColors.up : AppColors.down,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
