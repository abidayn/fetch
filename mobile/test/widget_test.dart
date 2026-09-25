// The default `flutter create` smoke test no longer applied (it referenced
// the MyApp/counter that has been removed).
//
// Why a single pump() rather than pumpAndSettle(): flutter test runs in the
// Dart VM without a real Android platform, so platform-channel calls
// (flutter_secure_storage reading the token, receive_sharing_intent checking
// for incoming shares) have no real handler and hang forever without
// explicit mocking. On top of that a CircularProgressIndicator keeps spinning
// the whole time -- pumpAndSettle() would never finish waiting for the
// animation to stop. For a smoke test (the app must build without an
// exception), one pump() is enough to prove the widget tree is valid.
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(FetchApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
