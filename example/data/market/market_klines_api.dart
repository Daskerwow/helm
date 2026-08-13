import 'package:dio/dio.dart';

/// Точка свечи для графика — время + цена закрытия, обе оси нужны
/// `fl_chart` для нормальных подписей по X.
final class ClosePoint {
  const ClosePoint(this.time, this.close);
  final DateTime time;
  final double close;
}

/// Публичный REST-эндпоинт Binance, ключей не требует. Используется и для
/// бэкфилла графика на детальном экране, и для главного графика на
/// дашборде.
final class MarketKlinesApi {
  const MarketKlinesApi(this._dio);

  final Dio _dio;

  Future<List<ClosePoint>> fetchRecentCloses(
    String symbol, {
    String interval = '1h',
    int limit = 100,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      'https://api.binance.com/api/v3/klines',
      queryParameters: {
        'symbol': symbol.toUpperCase(),
        'interval': interval,
        'limit': limit,
      },
    );

    final rows = response.data ?? const [];
    return rows
        .map(
          (row) => ClosePoint(
            DateTime.fromMillisecondsSinceEpoch(
              (row as List<dynamic>)[0] as int,
            ),
            double.tryParse(row[4] as String) ?? 0,
          ),
        )
        .toList();
  }
}
