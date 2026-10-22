import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/custom_detail_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the passage editor has exactly one scrollbar', (tester) async {
    // The bug: the framework adds its own scrollbar to every scrollable
    // (EditableText included), so the explicit always-visible one doubled it —
    // two bars dragging in sync. The fix disables the framework's in this
    // subtree; this test keeps it that way.
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final item = await provider.add(
      body: [for (var i = 0; i < 80; i++) 'Sentence number $i.'].join(' '),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CustomDetailView(itemId: item.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget,
        reason: 'the text field carries the only scrollbar');

    // Ask the behaviour the field actually resolves: with the framework's
    // scrollbars switched off it must hand the child back untouched instead of
    // wrapping it in a second bar.
    final fieldContext = tester.element(find.byType(TextField).last);
    final behavior = ScrollConfiguration.of(fieldContext);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const probe = SizedBox(key: ValueKey('probe'));
    final wrapped = behavior.buildScrollbar(
      fieldContext,
      probe,
      ScrollableDetails.vertical(controller: controller),
    );
    expect(identical(wrapped, probe), isTrue,
        reason: 'the framework must not draw a second bar inside the field');
  });

  testWidgets('the body field scrolls instead of pushing the buttons away',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final item = await provider.add(
      body: [for (var i = 0; i < 200; i++) 'Sentence number $i.'].join(' '),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CustomDetailView(itemId: item.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Even with a very long passage the controls keep their place at the top of
    // the pane's flow: the field takes the free height.
    final field = tester.getRect(find.byType(TextField).last);
    final save = tester.getRect(find.widgetWithText(FilledButton, '保存'));
    expect(field.height, lessThan(600));
    expect(save.top, greaterThan(field.bottom - 1));
    expect(tester.takeException(), isNull);
  });
}
