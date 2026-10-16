import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// One block of a legal document.
class LegalBlock {
  final LegalBlockType type;
  final String text;

  const LegalBlock(this.type, this.text);
}

enum LegalBlockType { heading, paragraph, bullet }

/// Splits a document in the server's small format: "## " starts a heading,
/// "- " a bullet, and a blank line ends a paragraph. Lines of one paragraph
/// are joined, so an admin's hard wraps do not show.
List<LegalBlock> parseLegalBody(String body) {
  final blocks = <LegalBlock>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(LegalBlock(LegalBlockType.paragraph, paragraph.join(' ')));
    paragraph.clear();
  }

  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      blocks.add(LegalBlock(LegalBlockType.heading, line.substring(3).trim()));
    } else if (line.startsWith('- ')) {
      flush();
      blocks.add(LegalBlock(LegalBlockType.bullet, line.substring(2).trim()));
    } else {
      paragraph.add(line);
    }
  }
  flush();
  return blocks;
}

/// Renders a legal document body. Selectable, so a traveller can quote it.
class LegalBody extends StatelessWidget {
  final String body;

  const LegalBody({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    final blocks = parseLegalBody(body);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks.length; i++) _block(blocks[i], first: i == 0),
        ],
      ),
    );
  }

  Widget _block(LegalBlock block, {required bool first}) {
    switch (block.type) {
      case LegalBlockType.heading:
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : 22, bottom: 8),
          child: Text(
            block.text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        );
      case LegalBlockType.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8, right: 10),
                child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
              ),
              Expanded(child: Text(block.text, style: _bodyStyle)),
            ],
          ),
        );
      case LegalBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(block.text, style: _bodyStyle),
        );
    }
  }

  static const _bodyStyle = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: AppColors.textSecondary,
  );
}
