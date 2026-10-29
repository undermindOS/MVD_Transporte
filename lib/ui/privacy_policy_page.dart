import 'package:flutter/material.dart';

import 'policy_markdown.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/timbre_app_bar.dart';

/// The privacy policy, opened from Info. Google Play wants it inside the
/// app too: the app bundles docs/privacy-policy.md, the one text of the
/// policy, so it reads the same as the published one and opens offline.
class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  /// Declared in pubspec.yaml `assets`.
  static const asset = 'docs/privacy-policy.md';

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  // Read once per opening, not on every rebuild. Not kept in the bundle's
  // cache: the page is seldom opened, and in widget tests a cached future
  // belongs to the fake clock of the test that read it first
  late final Future<List<PolicyBlock>> _blocks = DefaultAssetBundle.of(context)
      .loadString(PrivacyPolicyPage.asset, cache: false)
      .then(policyToBlocks);

  /// Paragraphs, as in Info's cards.
  static final _reading =
      TimbreText.subtitle.copyWith(height: 1.45, color: TimbreColors.papel);

  static final _title = TimbreText.dialogTitle.copyWith(height: 1.25);

  static const _bold = TextStyle(fontWeight: FontWeight.w700);

  // No monospace face is bundled. Addresses are data, in the condensed
  // family: «geoserver.montevideo.gub.uy» stays on one line at 2× text
  static const _code = TextStyle(
      fontFamily: TimbreFonts.firaCondensed, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The identity bar of the tabs, with the back arrow
      appBar: buildTimbreAppBar(context, title: 'Privacidad'),
      body: FutureBuilder<List<PolicyBlock>>(
        future: _blocks,
        builder: (context, snapshot) {
          final blocks = snapshot.data;
          if (blocks == null) return const SizedBox.shrink();
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(TimbreSpace.l, 18, TimbreSpace.l, 28),
            children: [for (final block in blocks) _block(block)],
          );
        },
      ),
    );
  }

  Widget _block(PolicyBlock block) => switch (block.kind) {
        PolicyBlockKind.title => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Semantics(
                header: true, child: Text(block.text, style: _title)),
          ),
        // In uppercase like «FUENTE DE DATOS»; screen readers hear the
        // words as written
        PolicyBlockKind.heading => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            child: Semantics(
              header: true,
              label: block.text,
              excludeSemantics: true,
              child: Text(block.text.toUpperCase(),
                  style: TimbreText.sectionLabel),
            ),
          ),
        PolicyBlockKind.paragraph => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(_spans(block), style: _reading),
          ),
        PolicyBlockKind.bullet => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Text('•', style: _reading)),
                const SizedBox(width: 10),
                Expanded(child: Text.rich(_spans(block), style: _reading)),
              ],
            ),
          ),
      };

  TextSpan _spans(PolicyBlock block) => TextSpan(children: [
        for (final span in block.spans)
          TextSpan(
            text: span.text,
            style: span.bold
                ? _bold
                : span.code
                    ? _code
                    : null,
          ),
      ]);
}
