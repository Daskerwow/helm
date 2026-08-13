import 'package:dio/dio.dart';

/// Единая точка настройки Dio — таймауты, базовый URL, интерсептор логов.
/// Не синглтон и не сервис-локатор — экземпляр создаётся один раз в
/// композиционном корне (`app/di.dart`) и передаётся дальше через
/// конструкторы, явной зависимостью. Для тестов вместо реального `Dio`
/// можно передать инстанс с `DioAdapter`/`MockAdapter`.
Dio buildHttpClient({String baseUrl = 'https://jsonplaceholder.typicode.com'}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
}
