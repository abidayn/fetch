// FolderPicker only holds the typed search text (the sheet owns the item and
// the requests), so it can be tested on its own with plain data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/folder.dart';
import 'package:mobile/widgets/folder_picker.dart';

final _folders = [
  Folder(id: 'f1', name: 'Recipes', itemCount: 12, lastSavedAt: DateTime(2026, 9, 1)),
  Folder(id: 'f2', name: 'Gym', itemCount: 1, lastSavedAt: DateTime(2026, 9, 20)),
];

Future<void> _pump(WidgetTester tester,
    {List<Folder>? folders,
    bool showAi = true,
    String? selectedId,
    VoidCallback? onPickAi,
    ValueChanged<Folder>? onPickFolder,
    ValueChanged<String>? onCreate}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: FolderPicker(
          folders: folders ?? _folders,
          showAi: showAi,
          selectedId: selectedId,
          onPickAi: onPickAi ?? () {},
          onPickFolder: onPickFolder ?? (_) {},
          onCreate: onCreate ?? (_) {},
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('Let Fetch pick first, folders most recently used first, New folder last', (tester) async {
    await _pump(tester);
    final ai = tester.getTopLeft(find.text('Let Fetch pick'));
    final gym = tester.getTopLeft(find.text('Gym')); // saved into more recently
    final recipes = tester.getTopLeft(find.text('Recipes'));
    final create = tester.getTopLeft(find.text('New folder'));
    expect(ai.dy, lessThan(gym.dy));
    expect(gym.dx, lessThan(recipes.dx));
    expect(recipes.dx, lessThan(create.dx));
    expect(find.text('12 saves'), findsOneWidget);
    expect(find.text('1 save'), findsOneWidget);
  });

  testWidgets('no AI option outside the first step', (tester) async {
    await _pump(tester, showAi: false, selectedId: 'f1');
    expect(find.text('Let Fetch pick'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // the selected folder
  });

  testWidgets('taps are passed up', (tester) async {
    var ai = 0;
    Folder? picked;
    String? created;
    await _pump(tester, onPickAi: () => ai++, onPickFolder: (f) => picked = f, onCreate: (n) => created = n);
    await tester.tap(find.text('Let Fetch pick'));
    await tester.tap(find.text('Gym'));
    await tester.tap(find.text('New folder'));
    expect(ai, 1);
    expect(picked?.id, 'f2');
    expect(created, ''); // nothing typed -> empty name dialog
  });

  testWidgets('no folders yet: only Let Fetch pick and New folder', (tester) async {
    await _pump(tester, folders: []);
    expect(find.text('Let Fetch pick'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });

  group('finding a folder', () {
    final many = [
      for (final n in ['Recipes', 'Gym', 'Home gym', 'Travel', 'Reading list', 'Side project', 'Music'])
        Folder(id: n, name: n, itemCount: 0),
    ];

    test('filterFolders: case-insensitive, starts-with first, empty = all', () {
      expect(filterFolders(many, 'GYM').map((f) => f.name), ['Gym', 'Home gym']);
      expect(filterFolders(many, 'ym').map((f) => f.name), ['Gym', 'Home gym']);
      expect(filterFolders(many, '  '), many);
      expect(filterFolders(many, 'zzz'), isEmpty);
    });

    testWidgets('no search box with few folders', (tester) async {
      await _pump(tester, folders: many.take(kFolderSearchThreshold).toList());
      expect(find.widgetWithText(TextField, 'Find a folder'), findsNothing);
    });

    testWidgets('the search box filters the folder cards', (tester) async {
      await _pump(tester, folders: many);
      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pump();
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Home gym'), findsOneWidget);
      expect(find.text('Recipes'), findsNothing);
      expect(find.text('Let Fetch pick'), findsOneWidget); // always shown
      expect(find.text('New folder'), findsOneWidget); // something matched: plain "+"
    });

    testWidgets('no match offers to create the typed name', (tester) async {
      String? created;
      await _pump(tester, folders: many, onCreate: (name) => created = name);
      await tester.enterText(find.byType(TextField), 'Databases');
      await tester.pump();
      expect(find.text('No folder with that name.'), findsOneWidget);
      await tester.tap(find.text('New folder "Databases"'));
      expect(created, 'Databases');
    });
  });
}
