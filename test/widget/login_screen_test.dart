import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/screens/auth/login_screen.dart';
import 'package:cricscore/theme/app_theme.dart';

// Wrap the screen in a minimal shell — no GoRouter, no Firebase.
Widget _shell() => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark, // AppTheme.dark is now the light theme
        home: const LoginScreen(),
      ),
    );

void main() {
  group('LoginScreen — UI', () {
    testWidgets('renders email field, password field and Sign in button',
        (tester) async {
      await tester.pumpWidget(_shell());
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('CricScore'), findsOneWidget);
    });

    testWidgets('shows validation error when both fields are empty',
        (tester) async {
      await tester.pumpWidget(_shell());

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Please enter email and password'), findsOneWidget);
    });

    testWidgets('shows validation error when only email is filled',
        (tester) async {
      await tester.pumpWidget(_shell());

      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Please enter email and password'), findsOneWidget);
    });

    testWidgets('no validation error shown on initial load', (tester) async {
      await tester.pumpWidget(_shell());
      expect(find.text('Please enter email and password'), findsNothing);
    });

    testWidgets('password field is obscured by default', (tester) async {
      await tester.pumpWidget(_shell());
      final passField = tester.widget<TextField>(find.byType(TextField).last);
      expect(passField.obscureText, isTrue);
    });

    testWidgets('tapping visibility icon toggles password visibility',
        (tester) async {
      await tester.pumpWidget(_shell());

      // Initially obscured — icon shows "visibility" (eye open = click to reveal)
      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
    });
  });
}
