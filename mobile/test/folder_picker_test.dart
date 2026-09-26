// FolderPicker is stateless (the sheet owns the item and the requests), so it
// can be tested on its own with plain data -- no backend, no platform channels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/folder.dart';
import 'package:mobile/models/item.dart';
import 'package:mobile/widgets/folder_picker.dart';

Item _item({bool processed = true, String? folderId, String? folderName, String? folderBy, String? suggestion}) =>
    Item(
      id: 'i1',
      url: 'https://example.com',
      title: 'One-pan pasta',
      summary: 'A quick pasta.',
      processed: processed,
      hasContent: true,
      folderId: folderId,
      folderName: folderName,
      folderBy: folderBy,
      folderSuggestion: suggestion,
      createdAt: DateTime(2026, 9, 26),
    );

final _folders = [
  Folder(id: 'f1', name: 'Recipes', itemCount: 12),
  Folder(id: 'f2', name: 'Gym', itemCount: 1),
];

Future<void> _pump(WidgetTester tester, Item item,
    {List<Folder>? folders, bool aiWorking = false, VoidCallback? onPickAi, ValueChanged<Folder>? onPickFolder, VoidCallback? onCreate}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: FolderPicker(
          item: item,
          folders: folders ?? _folders,
          aiWorking: aiWorking,
          onPickAi: onPickAi ?? () {},
          onPickFolder: onPickFolder ?? (_) {},
          onCreate: onCreate ?? () {},
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('AI card comes first, folders next, "New folder" last', (tester) async {
    await _pump(tester, _item());
    final ai = tester.getTopLeft(find.text('Let AI pick'));
    final recipes = tester.getTopLeft(find.text('Recipes'));
    final create = tester.getTopLeft(find.text('New folder'));
    expect(ai.dy, lessThan(recipes.dy));
    expect(recipes.dy <= create.dy, isTrue);
    expect(find.text('12 items'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Skip this and it stays in Unfiled.'), findsOneWidget);
  });

  testWidgets('the suggestion is shown before tapping: existing vs new folder', (tester) async {
    await _pump(tester, _item(suggestion: 'recipes'));
    expect(find.text('Suggests recipes'), findsOneWidget);
    await _pump(tester, _item(suggestion: 'Databases'));
    expect(find.text('Suggests a new folder: Databases'), findsOneWidget);
  });

  testWidgets('taps are passed up', (tester) async {
    var ai = 0, create = 0;
    Folder? picked;
    await _pump(tester, _item(),
        onPickAi: () => ai++, onPickFolder: (f) => picked = f, onCreate: () => create++);
    await tester.tap(find.text('Let AI pick'));
    await tester.tap(find.text('Gym'));
    await tester.tap(find.text('New folder'));
    expect(ai, 1);
    expect(picked?.id, 'f2');
    expect(create, 1);
  });

  testWidgets('waiting for the AI, then placed by it', (tester) async {
    await _pump(tester, _item(processed: false, folderBy: 'ai'), aiWorking: true);
    expect(find.text('Choosing a folder…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(tester, _item(folderId: 'f1', folderName: 'Recipes', folderBy: 'ai'));
    expect(find.text('Put it in Recipes'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget); // tag on the folder the AI chose
    expect(find.text('Skip this and it stays in Unfiled.'), findsNothing);
  });

  testWidgets('a folder the AI just created shows even before the list reloads', (tester) async {
    await _pump(tester, _item(folderId: 'new', folderName: 'Databases', folderBy: 'ai'));
    expect(find.text('Databases'), findsOneWidget);
  });

  testWidgets('no folders yet', (tester) async {
    await _pump(tester, _item(processed: false), folders: []);
    expect(find.text('No folders yet. The AI will name one for this link.'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });
}
