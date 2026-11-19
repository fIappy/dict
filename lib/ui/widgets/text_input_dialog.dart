import 'package:flutter/material.dart';

/// One text field in an alert, with its controller owned by the dialog.
///
/// `showDialog` completes when the route is popped, which is *before* the exit
/// animation has finished painting. Disposing a controller right after the await
/// therefore lets the field use a disposed controller ("TextEditingController
/// was used after being disposed"). The controller lives in the dialog's State
/// here, so it dies with the widget.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.hintText,
    this.confirmLabel = '确定',
  });

  final String title;
  final String initialValue;
  final String? hintText;
  final String confirmLabel;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
