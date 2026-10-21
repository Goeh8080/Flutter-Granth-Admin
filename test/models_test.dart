import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/models/models.dart';

void main() {
  test('parses string numbers and nulls', () {
    final p = Praman.fromJson({
      'id': '861',
      'title': 'गीता',
      'topic_id': '12',
      'granth_id': null,
      'pageNumber': '878',
      'image_path': 'uploads/x.jpg',
      'isActive': '1',
      'is_favorate': '0',
      'editorImagePath': null,
      'youtube_url': 'HLhZeRregP0',
      'youtube_start': '30',
    });
    expect(p.id, 861);
    expect(p.granthId, 0);
    expect(p.pageNumber, 878);
    expect(p.isActive, isTrue);
    expect(p.isFavorite, isFalse);
    expect(p.imageUrl, 'https://granth.wnmsolutions.com/uploads/x.jpg');
    expect(p.editorImageUrl, isNull);
    expect(p.youtubeWatchUri.toString(), 'https://www.youtube.com/watch?v=HLhZeRregP0&t=30s');
  });

  test('youtube id extraction', () {
    expect(extractYoutubeId('https://youtu.be/HLhZeRregP0?t=3'), 'HLhZeRregP0');
    expect(extractYoutubeId('https://www.youtube.com/watch?v=HLhZeRregP0&x=1'), 'HLhZeRregP0');
    expect(extractYoutubeId('https://www.youtube.com/shorts/HLhZeRregP0'), 'HLhZeRregP0');
    expect(extractYoutubeId('HLhZeRregP0'), 'HLhZeRregP0');
  });

  test('parses captured live JSON fixtures if present', () {
    final dir = Directory('_probe');
    if (!dir.existsSync()) return;
    List<Map<String, dynamic>> load(String f) => asMapList(jsonDecode(File('_probe/$f').readAsStringSync())['data']);
    expect(load('get_topics.json').map(Topic.fromJson).length, greaterThan(0));
    expect(load('get_granths.json').map(Granth.fromJson).length, greaterThan(0));
    expect(load('get_pramans.json').map(Praman.fromJson).length, greaterThan(0));
    expect(load('get_feedbacks.json').map(FeedbackItem.fromJson).length, greaterThan(0));
  });
}
