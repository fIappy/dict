import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/ui/widgets/annotated_text.dart';

void main() {
  testWidgets('the sentence being read is drawn in red', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnnotatedText(
            'One. Two. Three.',
            themeWords: {},
            speakingIndex: 1,
          ),
        ),
      ),
    );

    // SelectableText renders through RenderEditable, so the span tree comes
    // from the widget rather than from a RichText.
    final rich = tester.widget<SelectableText>(find.byType(SelectableText).first);
    final root = rich.textSpan!;
    // The coloured spans are the sentence wrappers: their plain text is the
    // sentence they contain. visitChildren skips wrappers without text of
    // their own, so walk the tree here.
    final reds = <String>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.style?.color != null) {
        final plain = span.toPlainText().trim();
        if (plain.isNotEmpty) reds.add(plain);
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    collect(root);

    expect(reds, contains('Two.'),
        reason: 'only the sentence that is sounding is red');
    expect(reds, isNot(contains('One.')));
    expect(reds, isNot(contains('Three.')));
  });

  testWidgets('the layout survives the red mark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnnotatedText(
            'One.\nTwo.',
            themeWords: {},
            speakingIndex: 1,
          ),
        ),
      ),
    );

    final selectable =
        tester.widget<SelectableText>(find.byType(SelectableText).first);
    expect(selectable.textSpan!.toPlainText(), 'One.\nTwo.',
        reason: 'a one-sentence-per-line passage keeps its line breaks');
  });

  testWidgets('with nothing read the passage stays one span', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnnotatedText('One. Two.', themeWords: {}),
        ),
      ),
    );

    final selectable =
        tester.widget<SelectableText>(find.byType(SelectableText).first);
    expect(selectable.textSpan!.toPlainText(), 'One. Two.');
  });
}
