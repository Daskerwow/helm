import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../../data/news/news_api.dart';

/// Состояние — целиком `Loadable<List<Article>>`, загрузка сводится к
/// готовой `load()` из пакета `helm`.
HelmFeature<Loadable<List<Article>>, Never> buildNewsFeature() {
  return HelmFeature<Loadable<List<Article>>, Never>(
    () => StoreBuilder<Loadable<List<Article>>, Never>(const Loadable.idle()).build(),
  );
}
