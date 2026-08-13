import 'package:flutter/material.dart';

/// Единая палитра — тёмный финтех-дашборд (тёмно-синий фон, карточки чуть
/// светлее, зелёный/красный для роста/падения, индиго — акцент бренда).
abstract final class AppColors {
  static const background = Color(0xFF0B0E14);
  static const surface = Color(0xFF12151F);
  static const surfaceElevated = Color(0xFF171B28);
  static const border = Color(0xFF232838);

  static const textPrimary = Color(0xFFF3F4F8);
  static const textSecondary = Color(0xFF9AA1B4);
  static const textMuted = Color(0xFF5E6478);

  static const accent = Color(0xFF6C7BFF);
  static const accentSoft = Color(0x1A6C7BFF);

  static const up = Color(0xFF22C55E);
  static const upSoft = Color(0x1A22C55E);
  static const down = Color(0xFFF04452);
  static const downSoft = Color(0x1AF04452);

  static const warning = Color(0xFFF5A623);
}
