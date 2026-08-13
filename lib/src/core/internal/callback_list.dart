/// Список колбэков с безопасной итерацией **без копирования на каждый
/// вызов** — алгоритм соответствует `ChangeNotifier` из
/// `package:flutter/src/foundation/change_notifier.dart`, адаптированному
/// под generic `T` вместо `VoidCallback`.
///
/// ### Почему не growable `List<T>`
///
/// Список слушателей хранится не как обычный растущий `List<T>`
/// (`<T>[]`), а вручную — fixed-length `List<T?>` + отдельный счётчик
/// [_count]. Это тот же приём, что и в самом `ChangeNotifier` Flutter SDK:
/// это горячий путь (вызывается на каждый `commit`/`notifyListeners`), и
/// накладные расходы growable-обёртки поверх fixed-length массива на нём
/// заметны.
///
/// ### Компактизация с гистерезисом
///
/// - если живых элементов ≤ половины текущей ёмкости массива — выделяется
///   новый массив точного размера (иначе список рос бы бесконечно после
///   разового всплеска подписчиков и никогда не сжимался обратно);
/// - иначе — компактизация НА МЕСТЕ через попарные свопы, без единой
///   аллокации.
///
/// ### Реентрантность
///
/// [add]/[remove]/[clear] безопасны для вызова изнутри [notify] — типичный
/// сценарий, когда слушатель сам меняет состав подписчиков (например,
/// реагирует на событие закрытием всего источника публикаций). Во время
/// активной итерации удаления не сдвигают массив физически (это сломало бы
/// индексы цикла), а помечают слот `null` (tombstone); реальная уборка
/// происходит в конце самого внешнего [notify].
///
/// ### Изоляция ошибок слушателей — параметр [notify]`.onError`
///
/// По умолчанию исключение из слушателя внутри [notify] **не
/// перехватывается** — прерывает текущий проход и летит вызывающему коду
/// (тот же контракт, что и раньше). Это осознанное поведение по умолчанию:
/// молчаливое поглощение чужого исключения без адресата — это подмена
/// семантики, а не перформанс-оптимизация.
///
/// Если вызывающий код передаёт `onError`, [notify] переключается в
/// изолированный режим: исключение из одного слушателя перехватывается,
/// передаётся в `onError`, а проход продолжается для остальных слушателей.
/// Так `StateStore` защищает свои каналы (`addOnChanged`/`addOnEffect`/
/// `addDispatchListener`) — один "плохой" слушатель (например, упавший
/// аналитический хук) не должен блокировать доставку события остальным
/// (см. `StateStore._ListenerHub` в `state_store.dart`).
final class CallbackList<T> {
  List<T?> _list = List<T?>.filled(0, null);

  /// Число слотов в [_list], реально занятых (включая ещё не
  /// скомпактированные tombstone-слоты) — не то же самое, что число
  /// активных слушателей во время реентрантного notify; см. [length].
  int _count = 0;

  /// Глубина вложенности активных [notify] — не ноль, если слушатель
  /// синхронно триггерит новую публикацию изнутри своего же вызова.
  int _notificationCallStackDepth = 0;

  /// Сколько слотов сейчас помечены `null` (tombstone) реентрантным
  /// [remove]/[clear] — ждут компактизации в конце самого внешнего [notify].
  int _reentrantlyRemoved = 0;

  /// Текущее число живых слушателей.
  int get length => _count - _reentrantlyRemoved;

  bool get isEmpty => length == 0;

  /// Как `ChangeNotifier.addListener`: если тот же [listener] уже
  /// зарегистрирован, добавляется ещё один инстанс — вызывается столько
  /// раз, сколько был добавлен, снимается по одному вхождению за [remove].
  void add(T listener) {
    if (_count == _list.length) {
      if (_count == 0) {
        _list = List<T?>.filled(1, null);
      } else {
        final grown = List<T?>.filled(_list.length * 2, null);
        for (var i = 0; i < _count; i++) {
          grown[i] = _list[i];
        }
        _list = grown;
      }
    }
    _list[_count++] = listener;
  }

  void _removeAt(int index) {
    // Сжимаем backing-массив только если живых элементов после удаления
    // ≤ половины его длины — иначе просто сдвигаем хвост на месте, без
    // реаллокации. Без этого порога список рос бы, но никогда не
    // уменьшался, а с ним — не дёргался бы grow/shrink на каждый цикл
    // add/remove одного элемента у границы.
    _count -= 1;
    if (_count * 2 <= _list.length) {
      final shrunk = List<T?>.filled(_count, null);
      for (var i = 0; i < index; i++) {
        shrunk[i] = _list[i];
      }
      for (var i = index; i < _count; i++) {
        shrunk[i] = _list[i + 1];
      }
      _list = shrunk;
    } else {
      for (var i = index; i < _count; i++) {
        _list[i] = _list[i + 1];
      }
      _list[_count] = null;
    }
  }

  /// Убирает первое вхождение [listener] (сравнение по `==`). Не найден —
  /// no-op, безопасно для повторного вызова.
  void remove(T listener) {
    for (var i = 0; i < _count; i++) {
      final at = _list[i];
      if (at != listener) continue;

      if (_notificationCallStackDepth > 0) {
        _list[i] = null;
        _reentrantlyRemoved++;
      } else {
        _removeAt(i);
      }
      return;
    }
  }

  /// Убирает всех слушателей. Безопасен для вызова изнутри [notify] — см.
  /// докстринг класса про реентрантность.
  void clear() {
    if (_notificationCallStackDepth > 0) {
      for (var i = 0; i < _count; i++) {
        _list[i] = null;
      }
      _reentrantlyRemoved = _count;
    } else {
      _list = List<T?>.filled(0, null);
      _count = 0;
      _reentrantlyRemoved = 0;
    }
  }

  /// Вызывает [callback] для каждого текущего слушателя. Слушатели,
  /// добавленные во время вызова, в этот проход не попадают; удалённые во
  /// время вызова — попадают, но пропускаются.
  ///
  /// [onError], если передан, включает изоляцию ошибок между слушателями —
  /// см. докстринг класса, раздел "Изоляция ошибок слушателей". Без
  /// [onError] поведение как раньше: первое исключение прерывает проход.
  void notify(
    void Function(T listener) callback, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_count == 0) return;

    _notificationCallStackDepth++;
    final end = _count;
    for (var i = 0; i < end; i++) {
      final listener = _list[i];
      if (listener == null) continue;

      if (onError == null) {
        callback(listener);
      } else {
        try {
          callback(listener);
        } catch (e, st) {
          onError(e, st);
        }
      }
    }
    _notificationCallStackDepth--;

    if (_notificationCallStackDepth == 0 && _reentrantlyRemoved > 0) {
      _compactAfterReentrantRemoval();
    }
  }

  /// Физическая уборка tombstone-слотов, накопленных реентрантными
  /// [remove]/[clear] во время только что завершившегося самого внешнего
  /// [notify].
  void _compactAfterReentrantRemoval() {
    final newLength = _count - _reentrantlyRemoved;

    if (newLength * 2 <= _list.length) {
      // Сильно разрежено (больше половины — tombstone) — перевыделяем
      // точный по размеру массив одним проходом.
      final compacted = List<T?>.filled(newLength, null);
      var w = 0;
      for (var i = 0; i < _count; i++) {
        final listener = _list[i];
        if (listener != null) compacted[w++] = listener;
      }
      _list = compacted;
    } else {
      // Иначе — компактизация НА МЕСТЕ попарными свопами, без аллокации:
      // каждый null-слот в живой части меняется местами с ближайшим
      // следующим не-null.
      for (var i = 0; i < newLength; i++) {
        if (_list[i] == null) {
          var swap = i + 1;
          while (_list[swap] == null) {
            swap++;
          }
          _list[i] = _list[swap];
          _list[swap] = null;
        }
      }
    }

    _reentrantlyRemoved = 0;
    _count = newLength;
  }
}
