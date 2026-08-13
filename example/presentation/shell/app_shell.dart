import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/sidebar.dart';

/// Десктоп-раскладка дашборда: слева узкий сайдбар с навигацией (как в
/// типичной финтех-панели), справа — контент текущей вкладки. `ShellRoute`
/// в `app/router.dart` гарантирует, что этот каркас не пересоздаётся при
/// переключении между Дашбордом/Рынком/Избранным и т.д.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: Row(
        children: [
          Sidebar(currentPath: location),
          Expanded(child: child),
        ],
      ),
    );
  }
}
