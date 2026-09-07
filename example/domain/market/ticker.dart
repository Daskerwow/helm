/// Снимок рыночных данных по одной паре: цена + 24-часовая сводка.
final class const Ticker({
  required final String symbol,
  required final double price,
  required final double changePercent24h,
  required final double high24h,
  required final double low24h,

  /// Объём торгов за 24ч в котируемой валюте (USDT) — уже в долларах.
  required final double volumeQuote24h,
}) {
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
