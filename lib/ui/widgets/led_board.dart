import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/timbre_tokens.dart';
import 'cartel.dart';
import 'led_matrix.dart';

/// A whole screen that is the LED board: ink, the unlit amber dots from
/// edge to edge, the content in the middle and the TIMBRE MVD plate at the
/// bottom. The lock screens and the welcome stand on it. With large text
/// the board scrolls; it is never shorter than the screen.
class LedBoard extends StatelessWidget {
  const LedBoard({
    super.key,
    this.header,
    required this.child,
    this.plate = true,
  });

  /// Above the content, at the top of the board: the welcome's step dots.
  final Widget? header;

  /// The content, centered between the top and the plate.
  final Widget child;

  /// The TIMBRE MVD plate (`CartelCompacto`) at the bottom.
  final bool plate;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: TimbreColors.tinta,
      ),
      child: Scaffold(
        backgroundColor: TimbreColors.tinta,
        body: Stack(
          children: [
            const Positioned.fill(
              child: LedMatrix(
                pitch: 8,
                dot: 2.4,
                color: TimbreColors.ambar,
                opacity: 0.09,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    // The whole board: the content stays in the middle, also
                    // when it is narrower than the screen
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          header == null
                              ? const SizedBox(height: 24)
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 8,
                                  ),
                                  child: header,
                                ),
                          child,
                          plate
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 32, bottom: 20),
                                  child: CartelCompacto(),
                                )
                              : const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
