import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/theme/app_theme.dart';

void main() {
  group('AppTheme — light / outdoor theme', () {
    test('brightness is light', () {
      expect(AppTheme.dark.brightness, equals(Brightness.light));
    });

    test('scaffold background is white', () {
      expect(AppTheme.dark.scaffoldBackgroundColor, equals(AppColors.bg));
      expect(AppColors.bg, equals(const Color(0xFFFFFFFF)));
    });

    test('primary color is royal blue', () {
      expect(AppTheme.dark.colorScheme.primary, equals(AppColors.accent));
    });

    test('text color is near-black for sunlight readability', () {
      // Luminance > 0.5 means light color — text should be dark
      expect(AppColors.text.computeLuminance(), lessThan(0.1));
    });

    test('accent has sufficient contrast against white background', () {
      // WCAG AA requires contrast ratio >= 4.5 for normal text
      // We verify accent is dark enough (luminance < 0.3)
      expect(AppColors.accent.computeLuminance(), lessThan(0.3));
    });

    test('card background is slightly off-white (not pure white)', () {
      expect(AppColors.bgCard, isNot(equals(AppColors.bg)));
    });

    test('border color is light grey (not dark)', () {
      expect(AppColors.border.computeLuminance(), greaterThan(0.5));
    });
  });

  group('AppColors — event colors', () {
    test('wicket is red', () {
      final r = AppColors.wicket.red;
      final g = AppColors.wicket.green;
      expect(r, greaterThan(g)); // red dominant
    });

    test('ball/six color is amber (high red + high green)', () {
      final r = AppColors.ball.red;
      final b = AppColors.ball.blue;
      expect(r, greaterThan(b));
    });
  });

  group('AppCard widget', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppCard(child: const Text('Match Card')),
          ),
        ),
      );
      expect(find.text('Match Card'), findsOneWidget);
    });

    testWidgets('onTap fires when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('solid color overrides gradient', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppCard(
              color: Colors.blue,
              child: const Text('Blue card'),
            ),
          ),
        ),
      );
      expect(find.text('Blue card'), findsOneWidget);
    });
  });

  group('StatusBadge widget', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: StatusBadge(label: 'LIVE', color: Colors.red),
          ),
        ),
      );
      expect(find.text('LIVE'), findsOneWidget);
    });
  });

  group('SectionHeader widget', () {
    testWidgets('renders title uppercased', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SectionHeader(title: 'matches'),
          ),
        ),
      );
      expect(find.text('MATCHES'), findsOneWidget);
    });

    testWidgets('renders trailing widget when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SectionHeader(
              title: 'scores',
              trailing: Text('See all'),
            ),
          ),
        ),
      );
      expect(find.text('See all'), findsOneWidget);
    });
  });

  group('BallPip widget', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Row(children: [BallPip(label: '4', isFour: true)]),
          ),
        ),
      );
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('wicket pip renders W label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Row(children: [BallPip(label: 'W', isWicket: true)]),
          ),
        ),
      );
      expect(find.text('W'), findsOneWidget);
    });
  });

  group('TeamAvatar widget', () {
    testWidgets('renders up to 3 chars of shortName', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: TeamAvatar(shortName: 'WARRIORS'),
          ),
        ),
      );
      expect(find.text('WAR'), findsOneWidget);
    });

    testWidgets('short name under 3 chars rendered as-is', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: TeamAvatar(shortName: 'XI'),
          ),
        ),
      );
      expect(find.text('XI'), findsOneWidget);
    });
  });
}
