import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';

/// Reads [text] aloud with the reader's own voice settings.
///
/// One entry point for every selection in the app, so 朗读 means the same thing
/// whether the text came from a definition, a custom passage or an AI answer.
void speakSelection(BuildContext context, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  final speech = context.read<EntrySpeechProvider>();
  final settings = context.read<SettingsProvider>();
  speech.speakText(
    trimmed,
    rate: settings.speechRate,
    accent: accentForLanguage(settings.ttsLanguage),
  );
}

Widget _toolbar({
  required BuildContext context,
  required String selected,
  required List<ContextMenuButtonItem> items,
  required TextSelectionToolbarAnchors anchors,
}) {
  final buttons = [
    if (selected.trim().isNotEmpty)
      ContextMenuButtonItem(
        label: '朗读',
        onPressed: () {
          ContextMenuController.removeAny();
          speakSelection(context, selected);
        },
      ),
    ...items,
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: buttons,
  );
}

/// The selection toolbar for any [TextField] or [SelectableText], with 朗读
/// first when something is selected.
Widget speakableEditableMenu(BuildContext context, EditableTextState state) {
  final value = state.textEditingValue;
  final selection = value.selection;
  final selected = selection.isValid && !selection.isCollapsed
      ? selection.textInside(value.text)
      : '';
  return _toolbar(
    context: context,
    selected: selected,
    anchors: state.contextMenuAnchors,
    items: state.contextMenuButtonItems,
  );
}

/// A [SelectableText] whose selection menu can read the selection out loud.
///
/// Drop-in replacement: same constructor shape as the widget it wraps.
class SpeakableText extends StatelessWidget {
  const SpeakableText(this.data, {super.key, this.style}) : span = null;

  const SpeakableText.rich(TextSpan this.span, {super.key, this.style})
      : data = '';

  final String data;
  final TextSpan? span;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final span = this.span;
    if (span == null) {
      return SelectableText(
        data,
        style: style,
        contextMenuBuilder: speakableEditableMenu,
      );
    }
    return SelectableText.rich(
      span,
      style: style,
      contextMenuBuilder: speakableEditableMenu,
    );
  }
}

/// A [SelectionArea] whose selection menu can read the selection out loud.
///
/// The selected text comes from [SelectionArea.onSelectionChanged] because the
/// selection state does not expose it; everything else is the stock area.
class SpeakableSelectionArea extends StatefulWidget {
  const SpeakableSelectionArea({
    super.key,
    required this.child,
    this.onSelectionChanged,
  });

  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<SpeakableSelectionArea> createState() => _SpeakableSelectionAreaState();
}

class _SpeakableSelectionAreaState extends State<SpeakableSelectionArea> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) {
        _selected = content?.plainText ?? '';
        widget.onSelectionChanged?.call(content);
      },
      contextMenuBuilder: (context, state) => _toolbar(
        context: context,
        selected: _selected,
        anchors: state.contextMenuAnchors,
        items: state.contextMenuButtonItems,
      ),
      child: widget.child,
    );
  }
}
