import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/custom_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<CustomTextProvider> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final group = await provider.addGroup('测试分组');
    for (var i = 0; i < 5; i++) {
      await provider.add(body: 'Passage $i. Second line.', groupId: group!.id);
    }
    provider.selectGroup(group!.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: CustomScreen(isPaneView: true)),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  /// The whole group panel: header row plus its scrollable list.
  double groupSectionHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('custom-group-section'))).height;

  double passageListHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('custom-passage-list'))).height;

  /// Drags the handle by [dy]; the first move only takes up the touch slop.
  Future<void> dragSplitter(WidgetTester tester, double dy) async {
    final handle = find.byKey(const ValueKey('custom-group-splitter'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(Offset(0, dy.sign * 20));
    await tester.pump();
    await gesture.moveBy(Offset(0, dy - dy.sign * 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the group list and the passages are separated by a splitter',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('custom-group-splitter')), findsOneWidget,
        reason: 'the two sections must be adjustable');

    final before = groupSectionHeight(tester);
    await dragSplitter(tester, 60);
    final after = groupSectionHeight(tester);

    // The gesture system keeps the first ~20 px as touch slop; what matters is
    // that the panel follows the pointer.
    expect(after, greaterThan(before + 30),
        reason: 'dragging down gives the group list more room');

    // A double click puts the default back.
    final handle = find.byKey(const ValueKey('custom-group-splitter'));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(groupSectionHeight(tester), closeTo(190, 1));
  });

  testWidgets('the splitter stops at the edges instead of eating the list',
      (tester) async {
    await pumpScreen(tester);

    await dragSplitter(tester, -600);
    expect(groupSectionHeight(tester), greaterThan(100),
        reason: 'the group list never collapses to nothing');

    await dragSplitter(tester, 600);
    // 600-high surface: room is kept for the header and the passage list.
    expect(groupSectionHeight(tester), lessThan(330));
    expect(passageListHeight(tester), greaterThan(100),
        reason: 'the passages keep a usable viewport above the bottom bar');
  });

  testWidgets('the chosen height is remembered', (tester) async {
    await pumpScreen(tester);
    await dragSplitter(tester, 50);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('ui_custom_group_height'), isNotNull);
  });
}
