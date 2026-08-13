import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';

/// `main()` больше не место, где живёт весь граф зависимостей — только
/// точка входа: собрать зависимости и передать их приложению.
void main() {
  final dependencies = AppDependencies.create();
  runApp(App(dependencies: dependencies));
}
