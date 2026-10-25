import 'dart:convert';

/// Pure helpers to edit the folder tree (kept as raw maps so unknown server fields survive).
/// Tree shape: {religions:[{id,title,icon,tone,visible,coming_soon,groups:[{…,subgroups:[…]}]}], other:{…}}.

final RegExp kSlug = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');

bool validSlug(String s) => kSlug.hasMatch(s);

Map<String, dynamic> deepCopy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

bool sameTree(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);

List<Map<String, dynamic>> listOf(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

/// Mutable access to the list stored under [key] of [node] (created when absent).
List<Map<String, dynamic>> childList(Map<String, dynamic> node, String key) {
  final cur = node[key];
  if (cur is List) {
    // make sure entries are Map<String,dynamic>
    final out = [for (final e in cur) if (e is Map) e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)];
    node[key] = out;
    return out;
  }
  final out = <Map<String, dynamic>>[];
  node[key] = out;
  return out;
}

/// Error text for a new folder id among [siblings], or null when ok.
String? idError(String id, Iterable<String> siblings, {bool religion = false}) {
  if (!validSlug(id)) return 'आईडी: छोटे अंग्रेज़ी अक्षर/अंक/_/- (अधिकतम 40) / use a-z 0-9 _ -';
  if (religion && id == 'other') return '"other" आरक्षित है / reserved';
  if (siblings.contains(id)) return 'यह आईडी पहले से है / id already used';
  return null;
}

String? titleError(String t) {
  final s = t.trim();
  if (s.isEmpty) return 'नाम खाली नहीं हो सकता / title required';
  if (s.length > 60) return 'नाम 60 अक्षर तक / max 60 chars';
  return null;
}

Map<String, dynamic> newNode(String id, String title, {String? icon, String? tone, bool religion = false}) => {
  'id': id,
  'title': title.trim(),
  'icon': ?icon,
  if (religion) 'tone': ?tone,
  'visible': true,
  if (religion) 'groups': <Map<String, dynamic>>[] else ...{'granthIds': <String>[], 'keywords': <String>[], 'notKeywords': <String>[]},
};

/// Adds a sub-group to [group]. A group that has sub-groups carries no granthIds/keywords itself.
void addSubgroup(Map<String, dynamic> group, Map<String, dynamic> sub) {
  group.remove('granthIds');
  group.remove('keywords');
  group.remove('notKeywords');
  childList(group, 'subgroups').add(sub);
}

/// Removes the child at [index] of [list]; for sub-group lists drops the key when empty.
void removeChild(Map<String, dynamic> parent, String key, int index) {
  final l = childList(parent, key);
  if (index < 0 || index >= l.length) return;
  l.removeAt(index);
  if (key == 'subgroups' && l.isEmpty) {
    parent.remove('subgroups');
    parent.putIfAbsent('granthIds', () => <String>[]);
    parent.putIfAbsent('keywords', () => <String>[]);
  }
}

/// Moves element [index] by [delta] (-1 up, +1 down). Returns whether anything moved.
bool moveChild(List<Map<String, dynamic>> list, int index, int delta) {
  final to = index + delta;
  if (index < 0 || index >= list.length || to < 0 || to >= list.length) return false;
  final x = list.removeAt(index);
  list.insert(to, x);
  return true;
}

/// Leaf keys (`religion/group[/sub]`) found under [node] given its path prefix.
List<String> leafKeysUnder(Map<String, dynamic> node, String prefix) {
  final subs = listOf(node['subgroups']);
  if (subs.isNotEmpty) return [for (final s in subs) '$prefix/${s['id']}'];
  return [prefix];
}

List<String> religionLeafKeys(Map<String, dynamic> religion) {
  final id = '${religion['id']}';
  return [
    for (final g in listOf(religion['groups'])) ...leafKeysUnder(g, '$id/${g['id']}'),
  ];
}
