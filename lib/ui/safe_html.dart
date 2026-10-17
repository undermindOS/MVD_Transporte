import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

enum HtmlBlockKind { paragraph, heading, listItem }

class HtmlBlock {
  final HtmlBlockKind kind;
  final String text;

  const HtmlBlock(this.kind, this.text);

  @override
  String toString() => '${kind.name}: $text';
}

/// Shows the text of an HTML fragment (IM news use `<h1>`, `<p>`, lists).
///
/// The markup is parsed into a DOM and only its text is drawn as Flutter
/// widgets: no WebView, no JavaScript, no images or links are loaded;
/// `<script>`, `<style>` and embedded content are dropped.
class SafeHtml extends StatelessWidget {
  final String html;

  const SafeHtml(this.html, {super.key});

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in htmlToBlocks(html))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: switch (block.kind) {
              HtmlBlockKind.heading => Text(block.text,
                  style: base.copyWith(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              HtmlBlockKind.listItem => Text('•  ${block.text}', style: base),
              HtmlBlockKind.paragraph => Text(block.text, style: base),
            },
          ),
      ],
    );
  }
}

const _skipped = {
  'script', 'style', 'noscript', 'template', 'iframe', 'frame', 'object',
  'embed', 'svg', 'math', 'img', 'video', 'audio', 'canvas', 'head', 'title',
};

const _blocks = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'blockquote', 'ul',
  'ol', 'li', 'table', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre',
};

/// Splits an HTML fragment into text blocks. Plain text (no tags) keeps
/// its line breaks; HTML collapses whitespace like a browser does.
List<HtmlBlock> htmlToBlocks(String source) {
  if (!source.contains('<')) {
    return source
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => HtmlBlock(HtmlBlockKind.paragraph, p))
        .toList();
  }

  final blocks = <HtmlBlock>[];
  final buffer = StringBuffer();

  void flush(HtmlBlockKind kind) {
    final text = buffer
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    buffer.clear();
    if (text.isNotEmpty) blocks.add(HtmlBlock(kind, text));
  }

  void walk(dom.Node node, HtmlBlockKind kind) {
    if (node is dom.Text) {
      buffer.write(node.text.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    if (node is! dom.Element && node is! dom.DocumentFragment) return;

    final tag = node is dom.Element ? node.localName ?? '' : '';
    if (_skipped.contains(tag)) return;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }

    if (!_blocks.contains(tag)) {
      for (final child in node.nodes) {
        walk(child, kind);
      }
      return;
    }

    final inner = tag.length == 2 && tag.startsWith('h')
        ? HtmlBlockKind.heading
        : tag == 'li'
            ? HtmlBlockKind.listItem
            : kind;
    flush(kind);
    for (final child in node.nodes) {
      walk(child, inner);
    }
    flush(inner);
  }

  walk(html_parser.parseFragment(source), HtmlBlockKind.paragraph);
  flush(HtmlBlockKind.paragraph);
  return blocks;
}
