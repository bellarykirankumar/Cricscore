// Root-level smoke test — kept minimal so it runs fast in CI.
// Detailed tests live in test/unit/ and test/widget/.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test runner is working', () => expect(1 + 1, equals(2)));
}
