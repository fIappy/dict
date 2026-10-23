import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
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

/// Where the last secondary click landed, in global coordinates.
///
/// Right-clicking text does not move the caret in Flutter — it only records the
/// position — so the menu has to turn this back into a character offset.
Offset? _lastSecondaryTap;

/// Call from a [Listener] wrapped around selectable text so 从这里开始朗读 knows
/// which sentence was clicked.
void rememberSecondaryTap(Offset globalPosition) {
  _lastSecondaryTap = globalPosition;
}

/// The character offset under the last right-click, when one happened.
///
/// The builder's context has no render object of its own, so the editable's
/// render subtree is walked to find the paragraph that can answer.
int? _offsetFromSecondaryTap(BuildContext context) {
  final global = _lastSecondaryTap;
  if (global == null) return null;
  final editable = _findRender<RenderEditable>(context.findRenderObject());
  return editable?.getPositionForPoint(global).offset;
}

T? _findRender<T extends RenderObject>(RenderObject? root) {
  if (root == null) return null;
  if (root is T) return root;
  T? found;
  root.visitChildren((child) {
    found ??= _findRender<T>(child);
  });
  return found;
}

void _playFrom(BuildContext context, List<String> sentences) {
  final speech = context.read<EntrySpeechProvider>();
  final settings = context.read<SettingsProvider>();
  speech.playAll(
    [
      for (final sentence in sentences)
        EntryUtterance(text: sentence, isPhrase: false),
    ],
    rate: settings.speechRate,
    gap: settings.sentenceGap,
    accent: accentForLanguage(settings.ttsLanguage),
    loop: false,
    engine: settings.speechEngine,
  );
}

Widget _toolbar({
  required BuildContext context,
  required String selected,
  required List<ContextMenuButtonItem> items,
  required TextSelectionToolbarAnchors anchors,
  List<String>? fromHere,
}) {
  final buttons = [
    if (fromHere != null && fromHere.isNotEmpty)
      ContextMenuButtonItem(
        label: '从这里开始朗读',
        onPressed: () {
          ContextMenuController.removeAny();
          _playFrom(context, fromHere);
        },
      ),
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
  final caret = _offsetFromSecondaryTap(state.context);
  final from = caret != null
      ? sentencesFrom(value.text, caret)
      : const <String>[];
  return _toolbar(
    context: context,
    selected: selected,
    anchors: state.contextMenuAnchors,
    items: state.contextMenuButtonItems,
    fromHere: from.isEmpty ? null : from,
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
      return Listener(
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            rememberSecondaryTap(event.position);
          }
        },
        child: SelectableText(
          data,
          style: style,
          contextMenuBuilder: speakableEditableMenu,
        ),
      );
    }
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kSecondaryMouseButton != 0) {
          rememberSecondaryTap(event.position);
        }
      },
      child: SelectableText.rich(
        span,
        style: style,
        contextMenuBuilder: speakableEditableMenu,
      ),
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
