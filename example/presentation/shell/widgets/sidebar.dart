import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';

final class _NavItem {
  const _NavItem(this.icon, this.label, this.path);
  final IconData icon;
  final String label;
  final String path;
}

const _items = [
  _NavItem(Icons.dashboard_rounded, 'Дашборд', AppRoute.dashboard),
  _NavItem(Icons.show_chart_rounded, 'Рынок', AppRoute.market),
  _NavItem(Icons.star_rounded, 'Избранное', AppRoute.watchlist),
  _NavItem(Icons.currency_exchange_rounded, 'Конвертер', AppRoute.converter),
  _NavItem(Icons.article_rounded, 'Новости', AppRoute.news),
  _NavItem(Icons.tune_rounded, 'Алерты', AppRoute.settings),
];

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.currentPath});

  final String currentPath;

  bool _isActive(String path) => path == AppRoute.dashboard
      ? currentPath == path
      : currentPath.startsWith(path);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: _Logo(),
            ),
            for (final item in _items)
              _SidebarTile(
                icon: item.icon,
                label: item.label,
                active: _isActive(item.path),
                onTap: () => context.go(item.path),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: AppColors.accent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Live-данные с Binance',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
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

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.accent, Color(0xFF9B6CFF)],
            ),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.hub_rounded, size: 18, color: Colors.white),
          ),
        ),
        SizedBox(width: 10),
        Text(
          'CryptoDash',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: active ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
