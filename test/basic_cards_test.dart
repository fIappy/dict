import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/alphabet_provider.dart';
import 'package:local_dict/providers/numbers_provider.dart';
import 'package:local_dict/ui/screens/alphabet_screen.dart';
import 'package:local_dict/ui/screens/numbers_screen.dart';
import 'package:local_dict/ui/widgets/numbers_sections.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _alphabetColumns(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

Future<void> _pumpAlphabet(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AlphabetProvider(),
      child: const MaterialApp(
        home: Scaffold(body: AlphabetScreen(isPaneView: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpNumbers(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = NumbersProvider();
  await provider.initialize();
  await tester.pumpWidget(
    ChangeNotifierProvider<NumbersProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(body: NumbersScreen(isPaneView: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('letters: two cards on a phone, three on a wide pane',
      (tester) async {
    await _pumpAlphabet(tester, const Size(363, 792));
    expect(_alphabetColumns(tester), 2);
    expect(tester.takeException(), isNull);

    await _pumpAlphabet(tester, const Size(1200, 800));
    expect(_alphabetColumns(tester), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('numbers: cards shrink to keep two per row, cap at three',
      (tester) async {
    await _pumpNumbers(tester, const Size(363, 792));
    final cards = find.byType(NumberExampleCard);
    expect(cards, findsWidgets);
    final first = tester.getTopLeft(cards.at(0));
    final second = tester.getTopLeft(cards.at(1));
    expect(second.dy, first.dy, reason: 'the first two cards share a row');
    expect(second.dx, greaterThan(first.dx));
    final width = tester.getSize(cards.at(0)).width;
    expect(width, lessThan(200), reason: 'the card shrank with the pane');
    expect(tester.takeException(), isNull);

    await _pumpNumbers(tester, const Size(1200, 800));
    final wide = find.byType(NumberExampleCard);
    final a = tester.getTopLeft(wide.at(0));
    final b = tester.getTopLeft(wide.at(1));
    final c = tester.getTopLeft(wide.at(2));
    final d = tester.getTopLeft(wide.at(3));
    expect(b.dy, a.dy);
    expect(c.dy, a.dy);
    expect(d.dy, greaterThan(a.dy), reason: 'never more than three per row');
    expect(tester.takeException(), isNull);
  });
}
