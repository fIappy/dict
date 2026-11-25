import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/themes/theme_service.dart';
import 'package:local_dict/providers/vocabulary_provider.dart';
import 'package:local_dict/ui/screens/vocab_drill_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scene = ThemeScene(
  id: 'sports',
  label: '体育运动',
  hint: '比赛与训练',
  count: 2,
  groups: [
    ThemeGroup(
      id: 'people',
      label: '人',
      words: ['coach', 'team'],
      glosses: {'coach': '教练', 'team': '队伍'},
    ),
  ],
);

void main() {
  testWidgets('a wide drill keeps the theme left and the controls right',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VocabularyProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VocabDrillScreen(scene: _scene, hideLookup: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Left: the theme's words, each with its place in the list.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(find.text('coach'), findsWidgets);
    expect(find.text('循环朗读 2 词'), findsOneWidget);
    expect(find.text('体育运动'), findsWidgets);
    // The dictionary entry button belongs to the narrow layout only.
    expect(find.byTooltip('查词典'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
