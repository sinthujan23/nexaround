import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// A package's description with the headings, bold, lists and dividers the
/// admin and partner editors can write (light Markdown).
///
/// A single line break stays a line break, so text written before the editor
/// existed keeps its shape. Links are not offered by the editors and are not
/// tappable here. [plain] is shown when the server sent no formatted text.
class ExperienceDescription extends StatelessWidget {
  final String? markdown;
  final String? plain;

  const ExperienceDescription({super.key, this.markdown, this.plain});

  static const _body = TextStyle(
    fontSize: 15,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final text = (markdown ?? '').trim();
    if (text.isEmpty) {
      return Text((plain ?? '').trim(), style: _body);
    }
    return MarkdownBody(
      data: text,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: _body,
        pPadding: EdgeInsets.zero,
        strong: _body.copyWith(fontWeight: FontWeight.w800),
        em: _body.copyWith(fontStyle: FontStyle.italic),
        h1: _heading(19),
        h2: _heading(18),
        h3: _heading(16).copyWith(fontWeight: FontWeight.w700),
        h1Padding: const EdgeInsets.only(top: 14),
        h2Padding: const EdgeInsets.only(top: 14),
        h3Padding: const EdgeInsets.only(top: 10),
        listBullet: _body.copyWith(color: AppColors.brandGreen),
        listIndent: 20,
        blockSpacing: 10,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border.withValues(alpha: 0.9), width: 1),
          ),
        ),
      ),
    );
  }

  static TextStyle _heading(double size) => TextStyle(
        fontSize: size,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      );
}
