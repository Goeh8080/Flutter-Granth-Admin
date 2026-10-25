/// Null-safe helpers: the API returns numbers as strings and sometimes null.
int asInt(Object? v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? fallback;
}

String asStr(Object? v) => v == null ? '' : v.toString();

bool asFlag(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase();
  return s == '1' || s == 'true';
}

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.map((k, e) => MapEntry(k.toString(), e)) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(Object? v) =>
    v is List ? v.whereType<Map>().map(asMap).toList() : const [];
