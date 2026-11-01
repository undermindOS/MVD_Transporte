import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../../services/places_service.dart';
import '../map/places_ui.dart' show askPlaceName, placeGlyph;
import '../place_search_page.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'pixel_icon.dart';
import 'segmented.dart';

/// «Mis lugares» in Ajustes: Casa, Trabajo and the favourites, each found
/// by address with the search; a new favourite; and how far you walk to a
/// stop. Changes show on the Mapa at once ([PlacesService.places]).
class PlacesSettings extends StatefulWidget {
  const PlacesSettings({super.key});

  @override
  State<PlacesSettings> createState() => _PlacesSettingsState();
}

class _PlacesSettingsState extends State<PlacesSettings> {
  late int _walk = PlacesService.walkMinutes;

  @override
  void initState() {
    super.initState();
    PlacesService.ensureLoaded();
  }

  Future<PickedPlace?> _find(String hint) =>
      Navigator.of(context).push<PickedPlace>(
        MaterialPageRoute(builder: (_) => PlaceSearchPage(hint: hint)),
      );

  static String _address(PickedPlace p) =>
      p.address == null ? p.name : '${p.name} · ${p.address}';

  /// Casa or Trabajo not marked yet: find it.
  Future<void> _mark(PlaceKind kind) async {
    final picked = await _find(
      kind == PlaceKind.casa
          ? '¿Dónde está tu casa?'
          : '¿Dónde está tu trabajo?',
    );
    if (picked == null) return;
    await PlacesService.save(
      Place.at(
        kind,
        lat: picked.point.lat,
        lon: picked.point.lon,
        address: _address(picked),
      ),
    );
  }

  Future<void> _add() async {
    final picked = await _find('Buscar el lugar');
    if (picked == null || !mounted) return;
    final name = await askPlaceName(context, initial: picked.name);
    if (name == null) return;
    await PlacesService.save(
      Place.at(
        PlaceKind.favorito,
        lat: picked.point.lat,
        lon: picked.point.lon,
        name: name,
        address: _address(picked),
      ),
    );
  }

  /// A marked place: move it, rename a favourite, or forget it.
  Future<void> _edit(Place place) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(place.name, style: TimbreText.stopName),
            ),
            const Divider(),
            ListTile(
              leading: const PixelIcon(
                PixelGlyphs.search,
                size: TimbreIconSize.row,
                color: TimbreColors.ambar,
              ),
              title: const Text('Cambiar la dirección'),
              onTap: () => Navigator.pop(sheet, 'move'),
            ),
            if (place.kind == PlaceKind.favorito)
              ListTile(
                leading: const PixelIcon(
                  PixelGlyphs.star,
                  size: TimbreIconSize.row,
                  color: TimbreColors.ambar,
                ),
                title: const Text('Cambiar el nombre'),
                onTap: () => Navigator.pop(sheet, 'rename'),
              ),
            ListTile(
              leading: const PixelIcon(
                PixelGlyphs.trash,
                size: TimbreIconSize.row,
                color: TimbreColors.rojoLed,
              ),
              title: const Text('Olvidar este lugar'),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'move':
        final picked = await _find('Nueva dirección de ${place.name}');
        if (picked == null) return;
        await PlacesService.save(
          place.movedTo(
            lat: picked.point.lat,
            lon: picked.point.lon,
            address: _address(picked),
          ),
        );
      case 'rename':
        final name = await askPlaceName(context, initial: place.name);
        if (name != null) await PlacesService.save(place.renamed(name));
      case 'delete':
        await PlacesService.delete(place.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Place>>(
      valueListenable: PlacesService.places,
      builder: (context, places, _) {
        Place? of(PlaceKind kind) =>
            places.where((p) => p.kind == kind).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('MIS LUGARES', style: TimbreText.sectionLabel),
            ),
            for (final kind in [PlaceKind.casa, PlaceKind.trabajo])
              if (of(kind) case final place?)
                _PlaceRow(
                  glyph: placeGlyph(kind),
                  title: place.name,
                  subtitle: place.address ?? 'Marcado en el mapa',
                  onTap: () => _edit(place),
                )
              else
                _PlaceRow(
                  glyph: placeGlyph(kind),
                  title: kind == PlaceKind.casa ? 'Casa' : 'Trabajo',
                  subtitle: 'Sin marcar · tocá para buscar la dirección',
                  dim: true,
                  onTap: () => _mark(kind),
                ),
            for (final place in places.where(
              (p) => p.kind == PlaceKind.favorito,
            ))
              _PlaceRow(
                glyph: PixelGlyphs.star,
                title: place.name,
                subtitle: place.address ?? 'Marcado en el mapa',
                onTap: () => _edit(place),
              ),
            _PlaceRow(
              glyph: PixelGlyphs.plus,
              title: 'Agregar un lugar',
              subtitle: 'Por dirección, esquina o nombre',
              onTap: _add,
            ),
            const SizedBox(height: TimbreSpace.s),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'CAMINAR HASTA LA PARADA',
                style: TimbreText.sectionLabel,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TimbreSegmented<int>(
                values: PlacesService.walkOptions,
                selected: _walk,
                labelOf: (m) => '$m min',
                semanticLabel: 'Caminar hasta la parada',
                onChanged: (m) {
                  setState(() => _walk = m);
                  PlacesService.setWalkMinutes(m);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dim = false,
  });

  final PixelGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                PixelIcon(
                  glyph,
                  size: TimbreIconSize.rowLarge,
                  color: dim ? TimbreColors.tenue : TimbreColors.ambar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: dim ? TimbreColors.tenue : TimbreColors.papel,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: TimbreColors.etiquetaCartel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
