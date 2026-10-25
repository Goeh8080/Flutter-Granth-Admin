import 'dart:async';

/// Runs [action] [delay] after the last [call] (search boxes: filter 250 ms after typing stops,
/// not on every keystroke).
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 250)]);
  final Duration delay;
  Timer? _t;

  void call(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  /// Runs [action] now and drops any pending one.
  void now(void Function() action) {
    _t?.cancel();
    action();
  }

  void dispose() => _t?.cancel();
}

/// Remembers the last result of [compute]; recomputes only when the key changes
/// (keys are compared with `==`; lists by identity). Keeps sort/filter work out of `build()`.
class Memo<K, V> {
  K? _key;
  V? _value;
  bool _has = false;

  V get(K key, V Function() compute) {
    if (_has && _key == key) return _value as V;
    _key = key;
    _has = true;
    return _value = compute();
  }

  void clear() => _has = false;
}
