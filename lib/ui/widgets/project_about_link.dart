import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../project_about_page.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'pixel_icon.dart';

/// One entry point shared by Info and the bottom of Servicios.
class ProjectAboutLink extends StatelessWidget {
  const ProjectAboutLink({super.key, this.compact = false});

  /// Servicios keeps this secondary to the official service tiles.
  final bool compact;

  static void open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ProjectAboutPage()));

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Acerca de Timbre MVD, Liberon Tech y Khrestenkov & Co',
    onTap: () => open(context),
    excludeSemantics: true,
    child: Material(
      color: TimbreColors.tinta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.card),
        side: const BorderSide(color: TimbreColors.lineaNoche),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(context),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProjectBrandLogos(compact: compact),
              SizedBox(height: compact ? 10 : 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Acerca de Timbre MVD',
                      style: TimbreText.button.copyWith(
                        color: TimbreColors.papel,
                        fontSize: compact ? 14 : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const PixelIcon(
                    PixelGlyphs.chevronRight,
                    size: 22,
                    color: TimbreColors.ambar,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Liberon Tech · Khrestenkov & Co',
                style: TimbreText.caption,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Original vector shapes: white artwork; the mascot has a black face on white.
class ProjectBrandLogos extends StatelessWidget {
  const ProjectBrandLogos({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 48 : 80,
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Keep the logo anchors from the two-column layout. Place the line
        // halfway across the visible gap, rather than at the column boundary.
        const columnGap = 32.0;
        final columnWidth = (constraints.maxWidth - columnGap) / 2;
        final liberonWidth = columnWidth.clamp(0.0, compact ? 168.0 : 260.0);
        final khdWidth = columnWidth.clamp(0.0, compact ? 48.0 : 72.0);
        final khdLeft = columnWidth + columnGap + (columnWidth - khdWidth) / 2;
        // The SVG viewBox starts at x=54 and is 610 wide; the artwork ends
        // at x=655. Exclude its transparent right margin from the gap.
        final liberonRight = liberonWidth * (655 - 54) / 610;
        final dividerX = (liberonRight + khdLeft) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: liberonWidth,
                      height: compact ? 46 : 76,
                      child: SvgPicture.asset(
                        'assets/brands/liberon-tech-white.svg',
                        fit: BoxFit.contain,
                        semanticsLabel: 'Liberon Tech',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: columnGap),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: SizedBox.square(
                      dimension: compact ? 48 : 72,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 6 : 8),
                          child: SvgPicture.asset(
                            'assets/brands/khrestenkov-co-white.svg',
                            fit: BoxFit.contain,
                            semanticsLabel: 'Khrestenkov & Co',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: dividerX - 0.5,
              top: 4,
              bottom: 4,
              width: 1,
              child: ColoredBox(
                color: TimbreColors.papel.withValues(alpha: 0.3),
              ),
            ),
          ],
        );
      },
    ),
  );
}
