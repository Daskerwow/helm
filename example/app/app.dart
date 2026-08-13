import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'di.dart';
import 'router.dart';

class App extends StatefulWidget {
  const App({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      deps: widget.dependencies,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Crypto Dashboard',
        theme: AppTheme.dark(),
        routerConfig: router,
      ),
    );
  }
}
