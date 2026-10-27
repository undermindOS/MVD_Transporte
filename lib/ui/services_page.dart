import 'package:flutter/material.dart';

import '../services/official_sites.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/led_matrix.dart';
import 'widgets/pixel_icon.dart';

typedef _Site = ({
  OfficialSite site,
  PixelGlyph icon,
  String title,
  String subtitle,
});

/// Official web services as small LED boards; each one opens in the
/// system browser (the ↗ on the tile says so).
class ServicesPage extends StatelessWidget {
  final ValueChanged<OfficialSite> onOpen;

  const ServicesPage({super.key, required this.onOpen});

  static const List<_Site> _card = [
    (
      site: OfficialSite.miStm,
      icon: PixelGlyphs.card,
      title: 'Mi STM',
      subtitle: 'Saldo y movimientos de tu tarjeta',
    ),
    (
      site: OfficialSite.recarga,
      icon: PixelGlyphs.money,
      title: 'Recarga',
      subtitle: 'Recargá tu tarjeta STM',
    ),
    (
      site: OfficialSite.avisos,
      icon: PixelGlyphs.bell,
      title: 'Avisos',
      subtitle: 'Notificaciones de tu cuenta STM',
    ),
  ];

  static const List<_Site> _travel = [
    (
      site: OfficialSite.comoIr,
      icon: PixelGlyphs.map,
      title: 'Cómo Ir',
      subtitle: 'Planificá tu viaje en ómnibus',
    ),
  ];

  static const _sectionTitle = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: TimbreColors.papel,
  );

  @override
  Widget build(BuildContext context) {
    // A Material, not a colored box: the tiles' tap ripple paints on it
    return Material(
      color: TimbreColors.noche,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
        children: [
          Semantics(
            header: true,
            child: const Text('Tu tarjeta STM', style: _sectionTitle),
          ),
          const SizedBox(height: 14),
          _grid(_card),
          const SizedBox(height: 26),
          Semantics(
            header: true,
            child: const Text('Para moverte', style: _sectionTitle),
          ),
          const SizedBox(height: 14),
          _grid(_travel),
          const SizedBox(height: 24),
          const _BrowserNote(),
        ],
      ),
    );
  }

  /// Three tiles per row, like the board; a short last row keeps the size.
  /// On tablets the tiles stop growing at [_maxTile] instead of turning
  /// into big empty boards.
  Widget _grid(List<_Site> sites) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = ((constraints.maxWidth - 2 * _gap) / 3).clamp(
          0.0,
          _maxTile,
        );
        return Wrap(
          spacing: _gap,
          runSpacing: 18,
          children: [
            for (final s in sites)
              SizedBox(
                width: tile,
                child: _SiteTile(site: s, onTap: () => onOpen(s.site)),
              ),
          ],
        );
      },
    );
  }

  static const _gap = 12.0;
  static const _maxTile = 168.0;
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({required this.site, required this.onTap});

  final _Site site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${site.title}. ${site.subtitle}. '
          'Abre el sitio oficial en el navegador',
      // excludeSemantics drops the InkWell's tap action too
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TimbreRadii.card),
        // Tapping lights the board up
        splashColor:
            TimbreColors.ambar.withValues(alpha: TimbreOpacity.pressSplash),
        highlightColor:
            TimbreColors.ambar.withValues(alpha: TimbreOpacity.pressHighlight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              // A small LED board, the material of the header plate. Ink,
              // so the tap ripple shows on it
              child: Ink(
                decoration: BoxDecoration(
                  color: TimbreColors.tinta,
                  borderRadius: BorderRadius.circular(TimbreRadii.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TimbreRadii.card),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child:
                            LedMatrix(color: TimbreColors.ambar, opacity: 0.11),
                      ),
                      Center(
                        child: PixelIcon(
                          site.icon,
                          size: 48,
                          color: TimbreColors.ambar,
                          glow: true,
                        ),
                      ),
                      const Positioned(
                        top: 9,
                        right: 9,
                        child: PixelIcon(
                          PixelGlyphs.external,
                          size: 16,
                          color: TimbreColors.ambarTenue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              site.title,
              style: const TextStyle(
                fontFamily: TimbreFonts.fira,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: TimbreColors.papel,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              site.subtitle,
              style: const TextStyle(
                fontFamily: TimbreFonts.fira,
                fontSize: 13,
                height: 1.35,
                color: TimbreColors.etiquetaCartel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserNote extends StatelessWidget {
  const _BrowserNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TimbreColors.tinta,
        borderRadius: BorderRadius.circular(TimbreRadii.button),
        border: Border.all(color: TimbreColors.lineaNoche),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PixelIcon(PixelGlyphs.external,
                size: 22, color: TimbreColors.ambar),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Se abren en tu navegador, en el sitio oficial de la '
                'Intendencia de Montevideo. La app no tiene acceso a tu '
                'usuario, tu contraseña ni tu saldo. Timbre MVD no es una '
                'app oficial.',
                style: TimbreText.subtitle
                    .copyWith(height: 1.45, color: TimbreColors.papel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
