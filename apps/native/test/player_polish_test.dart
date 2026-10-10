import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/ui/scrolling_label.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'helpers/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  Widget app(Widget child, {bool reduced = false, bool ticker = true}) =>
      MaterialApp(
        theme: buildWaveTheme(const WaveCustomization(), Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: ticker,
              child: Center(child: SizedBox(width: 120, child: child)),
            ),
          ),
        ),
      );
  double x(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(ScrollingLabel),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .storage[12];
  testWidgets(
    'Overflow scrolls after start pause; fitting/reduced/hidden text stays still with complete semantics',
    (tester) async {
      const long =
          'An original very long track title with collaborators that does not fit';
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(const ScrollingLabel(long)));
      await tester.pump();
      expect(x(tester), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(x(tester), 0);
      await tester.pump(const Duration(seconds: 3));
      expect(x(tester), lessThan(-1));
      expect(find.bySemanticsLabel(long), findsOneWidget);
      await tester.pumpWidget(app(const ScrollingLabel('Short')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(x(tester), 0);
      await tester.pumpWidget(app(const ScrollingLabel(long), reduced: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(x(tester), 0);
      await tester.pumpWidget(app(const ScrollingLabel(long), ticker: false));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(x(tester), 0);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Loading cover breathes only while busy; reduced/TickerMode stable and disposal cancels ticker',
    (tester) async {
      Widget cover(bool loading) => TrackLoadingCover(
        loading: loading,
        child: const SizedBox(width: 52, height: 52),
      );
      double opacity() => tester
          .widget<Opacity>(find.byKey(const Key('track-loading-cover')))
          .opacity;
      await tester.pumpWidget(app(cover(true)));
      await tester.pump();
      final first = opacity();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(), isNot(first));
      await tester.pumpWidget(app(cover(false)));
      await tester.pump();
      expect(opacity(), 1);
      await tester.pumpWidget(app(cover(true), reduced: true));
      await tester.pump();
      expect(opacity(), 1);
      await tester.pumpWidget(app(cover(true), ticker: false));
      await tester.pump();
      expect(opacity(), 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Project control vectors retain bounded geometry at icon sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Wrap(
          children: [
            for (final icon in WaveControlIcon.supported)
              WaveControlIcon(icon, size: 20),
          ],
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
