/// Цена монеты может быть и $70000 (BTC), и $0.5 (XRP) — фиксированное
/// число знаков после запятой ломает читаемость на одном из краёв
/// диапазона. Показываем больше дробных разрядов для дешёвых монет.
String formatPrice(double price) {
  if (price == 0) return '0';
  if (price >= 100) return price.toStringAsFixed(2);
  if (price >= 1) return price.toStringAsFixed(4);
  return price.toStringAsFixed(6);
}

/// Компактное форматирование крупных чисел объёма/капитализации:
/// 1234567 → '1.23M', 1234567890 → '1.23B'.
String formatCompactUsd(double value) {
  final abs = value.abs();
  if (abs >= 1e9) return '\$${(value / 1e9).toStringAsFixed(2)}B';
  if (abs >= 1e6) return '\$${(value / 1e6).toStringAsFixed(2)}M';
  if (abs >= 1e3) return '\$${(value / 1e3).toStringAsFixed(2)}K';
  return '\$${value.toStringAsFixed(2)}';
}

String formatPercent(double value) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(2)}%';
}
