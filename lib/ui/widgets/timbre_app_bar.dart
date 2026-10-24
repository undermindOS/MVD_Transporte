import 'package:flutter/material.dart';

import 'cartel.dart';
import 'led_matrix.dart';
import 'page_title_bar.dart';

/// The identity bar of every screen: the blue board with its unlit LEDs,
/// the lit plate (cartel compacto) on top and the page title below.
/// Pushed screens (Info, Horarios) get the back arrow next to the plate.
AppBar buildTimbreAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? subtitleTrailing,
  TextStyle subtitleStyle = PageTitleBar.defaultSubtitleStyle,
  String? semanticLabel,
  List<Widget>? actions,
}) {
  return AppBar(
    title: const CartelCompacto(),
    centerTitle: false,
    // The board continues to the right of the plate and fades out under
    // the title, so the text stays clean
    flexibleSpace: const LedMatrix(
      opacity: 0.8,
      fadeFrom: AlignmentDirectional.centerEnd,
    ),
    actions: actions,
    bottom: PageTitleBar(
      title: title,
      subtitle: subtitle,
      subtitleTrailing: subtitleTrailing,
      subtitleStyle: subtitleStyle,
      semanticLabel: semanticLabel,
      textScaler: MediaQuery.textScalerOf(context),
    ),
  );
}
