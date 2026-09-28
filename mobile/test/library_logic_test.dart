// The pure rules behind the library screens (lib/logic/library.dart).
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/logic/library.dart';
import 'package:mobile/models/folder.dart';
import 'package:mobile/models/item.dart';

final _now = DateTime(2026, 9, 26, 12);

Item _item(String id,
        {bool processed = true,
        bool hasContent = true,
        String? folderId,
        String? folderBy,
        String? suggestion,
        String? classifiedBy,
        int daysAgo = 0,
        String url = 'https://example.com/x'}) =>
    Item(
      id: id,
      url: url,
      title: 'T$id',
      summary: 'S',
      processed: processed,
      hasContent: hasContent,
      folderId: folderId,
      folderBy: folderBy,
      folderSuggestion: suggestion,
      classifiedBy: classifiedBy,
      createdAt: _now.subtract(Duration(days: daysAgo)),
    );

void main() {
  group('Needs you', () {
    test('a suggestion waiting for the user', () {
      final it = _item('1', folderBy: 'ai', suggestion: 'Gift ideas');
      expect(needReasons(it), {NeedReason.suggestion});
    });

    test('an unreadable link, until the user adds a title', () {
      expect(needReasons(_item('1', hasContent: false, folderBy: 'user')), {NeedReason.unreadable});
      expect(needReasons(_item('1', hasContent: false, folderBy: 'user', classifiedBy: 'user')), isEmpty);
    });

    test('nobody decided a folder', () {
      expect(needReasons(_item('1')), {NeedReason.noFolder});
    });

    test('Fetch was asked but could not pick', () {
      expect(needReasons(_item('1', folderBy: 'ai')), {NeedReason.noFolder});
    });

    test('left in Unsorted on purpose, filed, or still processing: nothing needed', () {
      expect(needReasons(_item('1', folderBy: 'user')), isEmpty);
      expect(needReasons(_item('1', folderId: 'f', folderBy: 'ai')), isEmpty);
      expect(needReasons(_item('1', processed: false)), isEmpty);
    });

    test('summary line', () {
      final items = [
        _item('1', folderBy: 'ai', suggestion: 'Gift ideas'),
        _item('2', hasContent: false),
        _item('3'),
        _item('4'),
      ];
      expect(needsSummary(items), '1 folder suggestion · 1 unreadable link · 2 without a folder');
    });
  });

  test('timeAgo', () {
    expect(timeAgo(_now.subtract(const Duration(seconds: 30)), _now), 'Just now');
    expect(timeAgo(_now.subtract(const Duration(minutes: 12)), _now), '12 min ago');
    expect(timeAgo(_now.subtract(const Duration(hours: 5)), _now), 'Today');
    expect(timeAgo(_now.subtract(const Duration(days: 3)), _now), '3d ago');
    expect(timeAgo(_now.subtract(const Duration(days: 15)), _now), '2w ago');
    expect(timeAgo(_now.subtract(const Duration(days: 90)), _now), '3mo ago');
  });

  test('chip folders: 4 most recently used, the selected one always visible', () {
    final folders = [
      for (var i = 0; i < 6; i++) Folder(id: 'f$i', name: 'F$i', itemCount: 0, createdAt: DateTime(2026, 1, i + 1)),
    ];
    // A save in f0 today makes it the most recently used.
    final items = [_item('a', folderId: 'f0')];
    expect(chipFolders(folders, items, null).map((f) => f.id), ['f0', 'f5', 'f4', 'f3']);
    expect(chipFolders(folders, items, 'f1').map((f) => f.id), ['f1', 'f0', 'f5', 'f4']);
  });

  group('From a while ago', () {
    final items = [
      for (var i = 0; i < 8; i++) _item('$i', daysAgo: i < 3 ? 1 : 20 + i),
    ];

    test('only old, readable saves; at most 3; same all day', () {
      final picked = fromAWhileAgo(items, _now);
      expect(picked.length, 3);
      expect(picked.every((it) => _now.difference(it.createdAt).inDays > 14), isTrue);
      expect(fromAWhileAgo(items, _now.add(const Duration(hours: 5))).map((i) => i.id), picked.map((i) => i.id));
    });

    test('needs at least 6 saves', () {
      expect(fromAWhileAgo(items.take(5).toList(), _now), isEmpty);
    });
  });

  group('answers', () {
    test('citations become parts; unknown numbers are dropped', () {
      final parts = parseAnswer('Pasta [1] and toast [2], not [7].', 2);
      expect(parts.where((p) => p.cite != null).map((p) => p.cite), [1, 2]);
      expect(parts.map((p) => p.text ?? '').join(), 'Pasta  and toast , not .');
      expect(citedSources(parts), [1, 2]);
    });

    test('an answer without citations is one text part', () {
      final parts = parseAnswer('None of your saved items match this question.', 0);
      expect(parts.length, 1);
      expect(citedSources(parts), isEmpty);
    });
  });

  test('the app a share came from', () {
    expect(sourceAppName('https://www.tiktok.com/@a/video/1'), 'TikTok');
    expect(sourceAppName('https://youtu.be/abc'), 'YouTube');
    expect(sourceAppName('https://www.instagram.com/reel/x'), 'Instagram');
    expect(sourceAppName('https://example.com'), isNull);
  });

  test('platform before processing is guessed from the URL', () {
    final it = Item(id: '1', url: 'https://m.youtube.com/watch?v=x', processed: false, hasContent: false, createdAt: _now);
    expect(it.platformKey, 'youtube');
    expect(it.openLabel, 'Open in YouTube');
    expect(_item('2', url: 'https://example.com').openLabel, 'Open in browser');
  });
}
