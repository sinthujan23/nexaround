import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';

import '../vendor_ui.dart';

/// The Markdown the web portal's DescriptionEditor writes: "## " headings,
/// **bold** and "- " lists. Pure, so the buttons can be tested.
class MarkdownEdit {
  final String text;
  final TextSelection selection;

  const MarkdownEdit(this.text, this.selection);

  /// The whole lines the selection touches.
  static (int, int) _lines(String text, TextSelection sel) {
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final next = text.indexOf('\n', end);
    return (lineStart, next == -1 ? text.length : next);
  }

  /// Starts each touched line with [prefix], or takes it off when all have it.
  static MarkdownEdit prefixLines(String text, TextSelection sel, String prefix) {
    final (from, to) = _lines(text, sel);
    final lines = text.substring(from, to).split('\n');
    final all = lines.every((l) => l.startsWith(prefix));
    final changed = lines
        .map((l) => all ? l.substring(prefix.length) : (l.startsWith(prefix) ? l : '$prefix$l'))
        .join('\n');
    final out = text.replaceRange(from, to, changed);
    return MarkdownEdit(out, TextSelection.collapsed(offset: from + changed.length));
  }

  /// Wraps the selection in **…**; with nothing selected, inserts a pair to
  /// type between.
  static MarkdownEdit bold(String text, TextSelection sel) {
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final inner = text.substring(start, end);
    final out = text.replaceRange(start, end, '**$inner**');
    return MarkdownEdit(
      out,
      inner.isEmpty
          ? TextSelection.collapsed(offset: start + 2)
          : TextSelection(baseOffset: start, extentOffset: end + 4),
    );
  }
}

class DescriptionEditor extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const DescriptionEditor({super.key, required this.value, required this.onChanged});

  @override
  State<DescriptionEditor> createState() => _DescriptionEditorState();
}

class _DescriptionEditorState extends State<DescriptionEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  bool _preview = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(MarkdownEdit edit) {
    _controller.value = TextEditingValue(text: edit.text, selection: edit.selection);
    widget.onChanged(edit.text);
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 20, color: AppColors.textPrimary),
        onPressed: _preview ? null : onTap,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _tool(Icons.title_rounded, 'Heading', () {
              _apply(MarkdownEdit.prefixLines(_controller.text, _controller.selection, '## '));
            }),
            _tool(Icons.format_bold_rounded, 'Bold', () {
              _apply(MarkdownEdit.bold(_controller.text, _controller.selection));
            }),
            _tool(Icons.format_list_bulleted_rounded, 'List', () {
              _apply(MarkdownEdit.prefixLines(_controller.text, _controller.selection, '- '));
            }),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_rounded : Icons.visibility_outlined, size: 18),
              label: Text(_preview ? 'Edit' : 'Preview'),
            ),
          ],
        ),
        if (_preview)
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _controller.text.trim().isEmpty
                ? const Text('Nothing to show yet.',
                    style: TextStyle(color: AppColors.textTertiary))
                : ExperienceDescription(markdown: _controller.text),
          )
        else
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            onChanged: widget.onChanged,
            decoration: vendorInput(
              'Description',
              hint: 'Itinerary, what to bring, safety notes…',
              helper: 'Select text and use the buttons for headings, bold and lists. '
                  'Preview shows what travellers will see.',
            ),
          ),
      ],
    );
  }
}
