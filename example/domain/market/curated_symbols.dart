/// Дашборд сознательно ограничен фиксированной корзиной из 10 ликвидных
/// пар — вместо полного списка Binance (сотни пар), который годится для
/// экрана-поиска, но не для аналитической панели: гейнеры/лузеры/сводка
/// должны считаться по понятному, стабильному набору активов.
const List<String> curatedSymbols = [
  'btcusdt',
  'ethusdt',
  'bnbusdt',
  'solusdt',
  'xrpusdt',
  'adausdt',
  'dogeusdt',
  'avaxusdt',
  'dotusdt',
  'linkusdt',
];

/// Человекочитаемое имя монеты — тикер сам по себе (BTC, ETH...) не всегда
/// говорит новичку, что это за актив.
const Map<String, String> symbolDisplayNames = {
  'btcusdt': 'Bitcoin',
  'ethusdt': 'Ethereum',
  'bnbusdt': 'BNB',
  'solusdt': 'Solana',
  'xrpusdt': 'XRP',
  'adausdt': 'Cardano',
  'dogeusdt': 'Dogecoin',
  'avaxusdt': 'Avalanche',
  'dotusdt': 'Polkadot',
  'linkusdt': 'Chainlink',
};

/// 'btcusdt' → 'BTC'
String symbolTicker(String symbol) {
  final upper = symbol.toUpperCase();
  return upper.endsWith('USDT') ? upper.substring(0, upper.length - 4) : upper;
}

/// 'btcusdt' → 'BTC / USDT'
String symbolLabel(String symbol) => '${symbolTicker(symbol)} / USDT';

/// 'btcusdt' → 'Bitcoin' (с фолбэком на тикер, если монеты нет в корзине)
String symbolName(String symbol) =>
    symbolDisplayNames[symbol] ?? symbolTicker(symbol);
