import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/alphabet/alphabet_data.dart';
import 'package:local_dict/core/ipa/ipa_data.dart';
import 'package:local_dict/providers/alphabet_provider.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/favorites_provider.dart';
import 'package:local_dict/providers/frequency_provider.dart';
import 'package:local_dict/providers/history_provider.dart';
import 'package:local_dict/providers/ipa_provider.dart';
import 'package:local_dict/providers/numbers_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/providers/themes_provider.dart';
import 'package:local_dict/ui/screens/alphabet_detail_view.dart';
import 'package:local_dict/ui/screens/custom_detail_view.dart';
import 'package:local_dict/ui/screens/home_screen.dart';
import 'package:local_dict/ui/screens/ipa_detail_view.dart';
import 'package:local_dict/ui/screens/numbers_detail_view.dart';
import 'package:provider/provider.dart';

/// A 363 x 792 dp window: the logical size of a 1272 x 2772 phone at 560 dpi.
const Size _phone = Size(363, 792);

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => FrequencyProvider()),
        ChangeNotifierProvider(create: (_) => IpaProvider()),
        ChangeNotifierProvider(create: (_) => AlphabetProvider()),
        ChangeNotifierProvider(create: (_) => NumbersProvider()),
        ChangeNotifierProvider(create: (_) => ThemesProvider()),
        ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
        ChangeNotifierProvider(create: (_) => CustomTextProvider()),
      ],
      child: MaterialApp(home: child),
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_wrap(child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _usePhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('phone bar: every destination lays out without overflow',
      (tester) async {
    await _usePhone(tester);
    await _pump(tester, const HomeScreen());

    expect(tester.takeException(), isNull);
    const icons = <IconData>[
      Icons.bookmark_outline_rounded,
      Icons.trending_up_rounded,
      Icons.category_outlined,
      Icons.record_voice_over_outlined,
      Icons.text_fields_outlined,
      Icons.numbers_outlined,
      Icons.history_rounded,
      Icons.edit_note_outlined,
      Icons.settings_outlined,
    ];
    for (final icon in icons) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'destination $icon');
    }
  });

  testWidgets('phone: IPA detail fits for every phoneme', (tester) async {
    await _usePhone(tester);
    for (final phoneme in IpaData.allPhonemes) {
      await _pump(tester, IpaDetailView(phoneme: phoneme));
      expect(tester.takeException(), isNull, reason: phoneme.symbol);
    }
  });

  testWidgets('phone: alphabet detail fits for every letter', (tester) async {
    await _usePhone(tester);
    for (final letter in AlphabetData.allLetters) {
      await _pump(tester, AlphabetDetailView(letter: letter));
      expect(tester.takeException(), isNull, reason: letter.upper);
    }
  });

  testWidgets('phone: numbers detail fits', (tester) async {
    await _usePhone(tester);
    await _pump(tester, const NumbersDetailView());
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: the passage editor is a page with its own bar',
      (tester) async {
    await _usePhone(tester);
    await _pump(tester, const CustomDetailView());
    expect(tester.takeException(), isNull);
    // Pushed as a page, not a bare pane: a bar, so there is a way back and the
    // fields sit below the status bar.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('新增短文'), findsWidgets);
  });
}
