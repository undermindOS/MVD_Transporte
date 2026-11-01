import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/pixel_icon.dart';

/// The glyph of a place: a house, a briefcase or a star.
PixelGlyph placeGlyph(PlaceKind kind) => switch (kind) {
  PlaceKind.casa => PixelGlyphs.home,
  PlaceKind.trabajo => PixelGlyphs.work,
  PlaceKind.favorito => PixelGlyphs.star,
};

/// The places over the top of the Mapa, one chip each: tapping one plans
/// the trip there. Casa and Trabajo always have a chip; one not marked yet
/// is unlit and says how to mark it.
class PlacesBar extends StatelessWidget {
  const PlacesBar({
    super.key,
    required this.places,
    required this.onPlace,
    required this.onMissing,
  });

  final List<Place> places;
  final ValueChanged<Place> onPlace;

  /// Casa or Trabajo, not marked yet.
  final ValueChanged<PlaceKind> onMissing;

  @override
  Widget build(BuildContext context) {
    Place? of(PlaceKind kind) =>
        places.where((p) => p.kind == kind).firstOrNull;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: TimbreSpace.s),
      child: Row(
        spacing: TimbreSpace.s,
        children: [
          for (final kind in [PlaceKind.casa, PlaceKind.trabajo])
            if (of(kind) case final place?)
              _PlaceChip(place: place, onTap: () => onPlace(place))
            else
              _MissingChip(kind: kind, onTap: () => onMissing(kind)),
          for (final place in places.where((p) => p.kind == PlaceKind.favorito))
            _PlaceChip(place: place, onTap: () => onPlace(place)),
        ],
      ),
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cómo llegar a ${place.name}',
      excludeSemantics: true,
      child: ActionChip(
        avatar: PixelIcon(
          placeGlyph(place.kind),
          size: TimbreIconSize.mark,
          color: TimbreColors.ambar,
        ),
        label: Text(place.name),
        onPressed: onTap,
      ),
    );
  }
}

class _MissingChip extends StatelessWidget {
  const _MissingChip({required this.kind, required this.onTap});

  final PlaceKind kind;
  final VoidCallback onTap;

  String get _name => kind == PlaceKind.casa ? 'Casa' : 'Trabajo';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$_name, sin marcar',
      excludeSemantics: true,
      child: ActionChip(
        avatar: PixelIcon(
          placeGlyph(kind),
          size: TimbreIconSize.mark,
          color: TimbreColors.tenue,
        ),
        label: Text(_name, style: const TextStyle(color: TimbreColors.tenue)),
        onPressed: onTap,
      ),
    );
  }
}

/// A place on the map: its glyph on an ink tile, lit amber, in a 44 px
/// target. Not the stop sign: a stop is always [PixelGlyphs.stop].
class PlaceMarker extends StatelessWidget {
  const PlaceMarker({super.key, required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: place.name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: TimbreColors.tinta,
              borderRadius: BorderRadius.circular(TimbreRadii.chip),
              border: Border.all(color: TimbreColors.ambarTenue, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: PixelIcon(
                placeGlyph(place.kind),
                size: 16,
                color: TimbreColors.ambar,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a sheet about a point or a place can ask for.
enum PlaceAction { goHere, setCasa, setTrabajo, addFavorite, rename, delete }

/// A long press on the map: plan a trip there, or keep it as a place.
class PointSheet extends StatelessWidget {
  const PointSheet({super.key, required this.places, required this.onAction});

  final List<Place> places;
  final ValueChanged<PlaceAction> onAction;

  bool _has(PlaceKind kind) => places.any((p) => p.kind == kind);

  @override
  Widget build(BuildContext context) {
    return _ActionSheet(
      title: 'Este punto',
      actions: [
        (PixelGlyphs.route, 'Cómo llegar acá', PlaceAction.goHere),
        (
          PixelGlyphs.home,
          _has(PlaceKind.casa) ? 'Mover Casa acá' : 'Marcar como Casa',
          PlaceAction.setCasa,
        ),
        (
          PixelGlyphs.work,
          _has(PlaceKind.trabajo) ? 'Mover Trabajo acá' : 'Marcar como Trabajo',
          PlaceAction.setTrabajo,
        ),
        (PixelGlyphs.star, 'Guardar como favorito', PlaceAction.addFavorite),
      ],
      onAction: onAction,
    );
  }
}

/// A place tapped on the map or on the bar: go there, rename a favourite,
/// or forget it.
class PlaceSheet extends StatelessWidget {
  const PlaceSheet({super.key, required this.place, required this.onAction});

  final Place place;
  final ValueChanged<PlaceAction> onAction;

  @override
  Widget build(BuildContext context) {
    return _ActionSheet(
      title: place.name,
      glyph: placeGlyph(place.kind),
      actions: [
        (PixelGlyphs.route, 'Cómo llegar', PlaceAction.goHere),
        if (place.kind == PlaceKind.favorito)
          (PixelGlyphs.star, 'Cambiar el nombre', PlaceAction.rename),
        (PixelGlyphs.trash, 'Olvidar este lugar', PlaceAction.delete),
      ],
      onAction: onAction,
    );
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.actions,
    required this.onAction,
    this.glyph,
  });

  final String title;
  final PixelGlyph? glyph;
  final List<(PixelGlyph, String, PlaceAction)> actions;
  final ValueChanged<PlaceAction> onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: TimbreSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    if (glyph != null) ...[
                      PixelIcon(
                        glyph!,
                        size: TimbreIconSize.row,
                        color: TimbreColors.ambar,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: Text(title, style: TimbreText.stopName)),
                  ],
                ),
              ),
            ),
            const Divider(),
            for (final (icon, label, action) in actions)
              ListTile(
                leading: PixelIcon(
                  icon,
                  size: TimbreIconSize.row,
                  color: action == PlaceAction.delete
                      ? TimbreColors.rojoLed
                      : TimbreColors.ambar,
                ),
                title: Text(label),
                onTap: () => onAction(action),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks the name of a favourite; null when cancelled or left empty.
Future<String?> askPlaceName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: initial),
    ).then((name) {
      final trimmed = name?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    });

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  // Owned here: disposed with the dialog, after its exit animation
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nombre del lugar'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Por ejemplo, Facultad'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
