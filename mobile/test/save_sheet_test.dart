// The save sheet's stages, driven by a fake backend: the sheet only talks to
// ApiClient, so overriding the few calls it makes is enough.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/token_storage.dart';
import 'package:mobile/models/item.dart';
import 'package:mobile/widgets/save_result_sheet.dart';

Map<String, dynamic> _json({
  bool hasContent = true,
  String? folderId,
  String? folderName,
  String? folderBy,
  String? suggestion,
}) =>
    {
      'id': 'i1',
      'url': 'https://www.tiktok.com/@a/video/1',
      'platform': 'tiktok',
      'author': '@a',
      'title': hasContent ? 'Korean street toast' : null,
      'summary': hasContent ? 'Three ways.' : null,
      'category': null,
      'classified_by': hasContent ? 'gemini:x' : null,
      'processed': true,
      'has_content': hasContent,
      'folder_id': folderId,
      'folder_name': folderName,
      'folder_by': folderBy,
      'folder_suggestion': suggestion,
      'created_at': '2026-09-26T10:00:00Z',
    };

class _FakeApi extends ApiClient {
  _FakeApi(this.item) : super(TokenStorage());

  Map<String, dynamic> item;
  final calls = <String>[];

  @override
  Future<List<dynamic>> listFolders() async => [
        {'id': 'f1', 'name': 'Recipes', 'item_count': 2, 'last_saved_at': null, 'created_at': '2026-09-01T00:00:00Z'},
      ];

  @override
  Future<Map<String, dynamic>> getItem(String id) async => item;

  @override
  Future<Map<String, dynamic>> setItemFolder(String itemId,
      {String? folderId, bool ai = false, bool acceptSuggestion = false}) async {
    if (ai) {
      calls.add('ai');
      item = {...item, 'folder_by': 'ai'};
    } else if (acceptSuggestion) {
      calls.add('accept');
      item = {...item, 'folder_id': 'f9', 'folder_name': item['folder_suggestion'], 'folder_by': 'ai'};
    } else {
      calls.add('folder:$folderId');
      item = {
        ...item,
        'folder_id': folderId,
        'folder_name': folderId == null ? null : 'Recipes',
        'folder_by': 'user',
      };
    }
    return item;
  }
}

Future<void> _open(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSaveResultSheet(context, api, Item.fromJson(api.item), fromShare: true),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Lets the sheet's 1-second progress ticker notice the stage changed and stop.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no folder fits: Fetch suggests one, the user creates it', (tester) async {
    final api = _FakeApi(_json(suggestion: 'Street food'));
    await _open(tester, api);
    expect(find.text('Where should it go?'), findsOneWidget);

    await tester.tap(find.text('Let Fetch pick'));
    await _settle(tester);
    expect(find.text('Create a "Street food" folder for it?'), findsOneWidget);

    await tester.tap(find.text('Create folder'));
    await _settle(tester);
    expect(find.text('All set'), findsOneWidget);
    expect(find.text('Picked by Fetch'), findsOneWidget);
    expect(find.text('Back to TikTok'), findsOneWidget);
    expect(api.calls, ['ai', 'accept']);
  });

  testWidgets('unreadable link: pick a folder or leave it in Unsorted', (tester) async {
    final api = _FakeApi(_json(hasContent: false));
    await _open(tester, api);
    await tester.tap(find.text('Let Fetch pick'));
    await _settle(tester);
    expect(find.text("Saved, but Fetch couldn't read it"), findsOneWidget);

    await tester.tap(find.text('Leave it in Unsorted'));
    await _settle(tester);
    expect(find.text('All set'), findsOneWidget);
    expect(find.text('Not in a folder'), findsOneWidget);
    expect(api.calls, ['ai', 'folder:null']);
  });

  testWidgets('picking a folder, then changing it', (tester) async {
    final api = _FakeApi(_json());
    await _open(tester, api);
    await tester.tap(find.text('Recipes'));
    await _settle(tester);
    expect(find.text('Picked by you'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a folder'), findsOneWidget);
    expect(find.text('Let Fetch pick'), findsNothing);
  });

  testWidgets('closing without choosing lets Fetch pick', (tester) async {
    final api = _FakeApi(_json());
    await _open(tester, api);
    await tester.tapAt(const Offset(10, 10)); // the scrim above the sheet
    await tester.pumpAndSettle();
    expect(api.calls, ['ai']);
  });
}
