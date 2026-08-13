/// Снимок рыночных данных по одной паре: цена + 24-часовая сводка.
final class Ticker {
  const Ticker({
    required this.symbol,
    required this.price,
    required this.changePercent24h,
    required this.high24h,
    required this.low24h,
    required this.volumeQuote24h,
  });

  final String symbol;
  final double price;
  final double changePercent24h;
  final double high24h;
  final double low24h;

  /// Объём торгов за 24ч в котируемой валюте (USDT) — уже в долларах.
  final double volumeQuote24h;

  bool get isUp => changePercent24h >= 0;

  @override
  bool operator ==(Object other) =>
      other is Ticker &&
      other.symbol == symbol &&
      other.price == price &&
      other.changePercent24h == changePercent24h &&
      other.high24h == high24h &&
      other.low24h == low24h &&
      other.volumeQuote24h == volumeQuote24h;

  @override
  int get hashCode => Object.hash(
    symbol,
    price,
    changePercent24h,
    high24h,
    low24h,
    volumeQuote24h,
  );
}
