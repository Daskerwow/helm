import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/market/curated_symbols.dart';
import '../../domain/market/ticker.dart';

/// События потока — статус соединения отделён от данных, чтобы фича могла
/// обновлять индикатор Live/Reconnecting независимо от прихода тикера.
sealed class MarketSocketEvent {}

final class MarketSocketConnected extends MarketSocketEvent {}

final class MarketSocketReconnecting extends MarketSocketEvent {}

final class MarketTickerUpdated extends MarketSocketEvent {
  MarketTickerUpdated(this.ticker);
  final Ticker ticker;
}

/// Обёртка над комбинированным (multiplexed) стримом Binance:
/// `wss://stream.binance.com:9443/stream?streams=btcusdt@ticker/ethusdt@ticker/...`
/// — одно соединение, по одному сообщению на каждое обновление конкретной
/// пары (~раз в секунду на пару). Подписка только на 10 нужных пар вместо
/// полного `!ticker@arr` (сотни пар) — меньше трафика и разбора JSON,
/// дашборду не нужна вся биржа целиком.
///
/// Никогда не завершается ошибкой наружу — при обрыве уходит в цикл
/// переподключения с экспоненциальной задержкой (1s → 2s → ... → 30s),
/// сообщая об этом через [MarketSocketReconnecting].
final class MarketSocket {
  const MarketSocket({this.symbols = curatedSymbols});

  final List<String> symbols;

  static const _backoffSeconds = [1, 2, 4, 8, 16, 30];

  Uri get _uri {
    final streams = symbols.map((s) => '$s@ticker').join('/');
    return Uri.parse('wss://stream.binance.com:9443/stream?streams=$streams');
  }

  Stream<MarketSocketEvent> events() async* {
    var attempt = 0;

    while (true) {
      try {
        final channel = WebSocketChannel.connect(_uri);
        yield MarketSocketConnected();
        attempt = 0;

        await for (final raw in channel.stream) {
          final ticker = _parse(raw as String);
          if (ticker != null) yield MarketTickerUpdated(ticker);
        }
      } catch (_) {
        // Сетевая ошибка/обрыв — лечится переподключением ниже.
      }

      attempt = math.min(attempt + 1, _backoffSeconds.length - 1);
      yield MarketSocketReconnecting();
      await Future<void>.delayed(Duration(seconds: _backoffSeconds[attempt]));
    }
  }

  Ticker? _parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return null;

    final symbol = (data['s'] as String?)?.toLowerCase();
    if (symbol == null) return null;

    return Ticker(
      symbol: symbol,
      price: _asDouble(data['c']),
      changePercent24h: _asDouble(data['P']),
      high24h: _asDouble(data['h']),
      low24h: _asDouble(data['l']),
      volumeQuote24h: _asDouble(data['q']),
    );
  }

  double _asDouble(Object? raw) => double.tryParse('$raw') ?? 0;
}
