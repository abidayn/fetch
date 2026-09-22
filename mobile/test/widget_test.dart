// Smoke test bawaan flutter create sudah tidak relevan (referensinya ke
// MyApp/counter yang sudah dihapus).
//
// Kenapa cuma pump() sekali, bukan pumpAndSettle(): flutter test jalan di
// Dart VM tanpa platform Android sungguhan, jadi panggilan platform channel
// (flutter_secure_storage buat baca token, receive_sharing_intent buat cek
// share masuk) tidak punya handler asli dan menggantung selamanya tanpa
// mocking eksplisit. Ditambah CircularProgressIndicator yang berputar terus
// selama itu -- pumpAndSettle() tidak akan pernah selesai menunggu animasi
// berhenti. Untuk smoke test (app harus bisa di-build tanpa exception),
// satu pump() sudah cukup buktikan widget tree valid.
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(FetchApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
