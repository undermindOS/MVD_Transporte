import 'dart:convert';

enum PolicyBlockKind { title, heading, paragraph, bullet }

/// A run of text in a block: plain, `**bold**` or `` `code` ``.
class PolicySpan {
  final String text;
  final bool bold;
  final bool code;

  const PolicySpan(this.text, {this.bold = false, this.code = false});

  @override
  String toString() => bold
      ? '**$text**'
      : code
          ? '`$text`'
          : text;
}

class PolicyBlock {
  final PolicyBlockKind kind;
  final List<PolicySpan> spans;

  const PolicyBlock(this.kind, this.spans);

  /// The words, without the markup.
  String get text => spans.map((s) => s.text).join();

  @override
  String toString() => '${kind.name}: ${spans.join()}';
}

/// Splits the privacy policy (docs/privacy-policy.md) into blocks.
///
/// Reads only the Markdown that file uses: `# ` title, `## ` headings,
/// paragraphs (lines joined until a blank line), `- ` list items, and
/// `**bold**` and `` `code` `` inside them. Quoted lines (`>`) are notes for
/// the maintainer, not for users: they are dropped.
List<PolicyBlock> policyToBlocks(String source) {
  final blocks = <PolicyBlock>[];
  final lines = <String>[];
  var kind = PolicyBlockKind.paragraph;

  void flush() {
    if (lines.isNotEmpty) {
      blocks.add(PolicyBlock(kind, policySpans(lines.join(' '))));
    }
    lines.clear();
  }

  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('>')) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      blocks.add(PolicyBlock(
          PolicyBlockKind.heading, policySpans(line.substring(3).trim())));
    } else if (line.startsWith('# ')) {
      flush();
      blocks.add(PolicyBlock(
          PolicyBlockKind.title, policySpans(line.substring(2).trim())));
    } else if (line.startsWith('- ')) {
      flush();
      kind = PolicyBlockKind.bullet;
      lines.add(line.substring(2).trim());
    } else {
      // A new paragraph, or the next line of the open one (a list item
      // continues on indented lines)
      if (lines.isEmpty) kind = PolicyBlockKind.paragraph;
      lines.add(line);
    }
  }
  flush();
  return blocks;
}

final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');

/// The spans of one block of text: `**bold**`, `` `code` `` and the plain
/// text around them.
List<PolicySpan> policySpans(String text) {
  final spans = <PolicySpan>[];
  var start = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > start) {
      spans.add(PolicySpan(text.substring(start, match.start)));
    }
    spans.add(match[1] != null
        ? PolicySpan(match[1]!, bold: true)
        : PolicySpan(match[2]!, code: true));
    start = match.end;
  }
  if (start < text.length) spans.add(PolicySpan(text.substring(start)));
  return spans;
}
