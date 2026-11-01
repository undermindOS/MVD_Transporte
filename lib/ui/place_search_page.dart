import 'dart:async';

import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services/place_search.dart';
import '../services/rutas/itinerary.dart' show GeoPoint;
import 'map/places_ui.dart' show placeGlyph;
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/pixel_icon.dart';

/// What the search page returns: a place in words and where it is.
typedef PickedPlace = ({String name, String? address, GeoPoint point});

/// The search, as in a map app: type an address, a corner or a name;
/// suggestions come as you type (from the city and OpenStreetMap), the
/// keyboard's search key asks once more. [places] are offered before
/// typing, as shortcuts. Pops a [PickedPlace].
class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({
    super.key,
    this.hint = 'Buscar una dirección o un lugar',
    this.places = const [],
  });

  final String hint;
  final List<Place> places;

  /// Tests answer here.
  @visibleForTesting
  static Future<List<PlaceHit>> Function(String text) suggest =
      PlaceSearch.suggest;
  @visibleForTesting
  static Future<List<PlaceHit>> Function(String text) search =
      PlaceSearch.search;

  /// How long typing must pause before the suggestions are asked.
  static const debounce = Duration(milliseconds: 400);

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _wait;
  // The last request: older answers are dropped
  var _asked = 0;
  List<PlaceHit> _hits = const [];
  bool _busy = false;
  bool _failed = false;
  // A suggestion being located (the city's are looked up when picked)
  PlaceHit? _locating;

  @override
  void dispose() {
    _wait?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _wait?.cancel();
    if (text.trim().length < 3) {
      _asked++;
      setState(() {
        _hits = const [];
        _busy = false;
        _failed = false;
      });
      return;
    }
    _wait = Timer(
      PlaceSearchPage.debounce,
      () => _ask(PlaceSearchPage.suggest),
    );
  }

  Future<void> _ask(Future<List<PlaceHit>> Function(String) how) async {
    final asked = ++_asked;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final hits = await how(_field.text);
      if (!mounted || asked != _asked) return;
      setState(() => _hits = hits);
    } catch (_) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _hits = const [];
        _failed = true;
      });
    } finally {
      if (mounted && asked == _asked) setState(() => _busy = false);
    }
  }

  Future<void> _pick(PlaceHit hit) async {
    // A street alone: type its number or corner next, as map apps do
    if (hit.kind == PlaceHitKind.street) {
      final text = '${hit.title} ';
      _field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _focus.requestFocus();
      _typed(text);
      return;
    }
    setState(() => _locating = hit);
    final point = await hit.locate().catchError((_) => null);
    if (!mounted) return;
    setState(() => _locating = null);
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo ubicar ese lugar. Probá con otro.'),
        ),
      );
      return;
    }
    Navigator.pop<PickedPlace>(context, (
      name: hit.title,
      address: hit.subtitle.isEmpty ? null : hit.subtitle,
      point: point,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final typing = _field.text.trim().length >= 3;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: _typed,
          onSubmitted: (_) {
            _wait?.cancel();
            if (_field.text.trim().length >= 3) _ask(PlaceSearchPage.search);
          },
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              tooltip: 'Borrar',
              icon: const PixelIcon(PixelGlyphs.close),
              onPressed: () {
                _field.clear();
                _typed('');
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (!typing) ...[
            for (final place in widget.places)
              _Row(
                glyph: placeGlyph(place.kind),
                title: place.name,
                subtitle: place.address ?? 'Marcado en el mapa',
                onTap: () => Navigator.pop<PickedPlace>(context, (
                  name: place.name,
                  address: place.address,
                  point: (lat: place.lat, lon: place.lon),
                )),
              ),
            Padding(
              padding: const EdgeInsets.all(TimbreSpace.l),
              child: Text(
                'Escribí una dirección («18 de Julio 1453»), una esquina '
                '(«Bulevar Artigas y Rivera») o el nombre de un lugar.',
                style: TimbreText.caption.copyWith(color: TimbreColors.tenue),
              ),
            ),
          ] else if (_failed)
            const _Note(
              glyph: PixelGlyphs.warning,
              text: 'No se pudo buscar. Revisá la conexión.',
            )
          else if (!_busy && _hits.isEmpty)
            const _Note(
              glyph: PixelGlyphs.search,
              text:
                  'Sin resultados. Probá con la calle y el número, o una '
                  'esquina.',
            )
          else
            for (final hit in _hits)
              _Row(
                glyph: switch (hit.kind) {
                  PlaceHitKind.address ||
                  PlaceHitKind.corner ||
                  PlaceHitKind.street => PixelGlyphs.streets,
                  PlaceHitKind.landmark || PlaceHitKind.poi => PixelGlyphs.pin,
                },
                title: hit.title,
                subtitle: hit.subtitle,
                busy: identical(hit, _locating),
                onTap: _locating == null ? () => _pick(hit) : null,
              ),
          if (typing && _hits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(TimbreSpace.l),
              child: Text(
                'Direcciones: Intendencia de Montevideo. Lugares: © '
                'OpenStreetMap.',
                style: TimbreText.caption.copyWith(color: TimbreColors.tenue),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final PixelGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: PixelIcon(
        glyph,
        size: TimbreIconSize.row,
        color: TimbreColors.etiquetaCartel,
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.glyph, required this.text});

  final PixelGlyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TimbreSpace.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelIcon(glyph, size: TimbreIconSize.row, color: TimbreColors.tenue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TimbreText.subtitle.copyWith(color: TimbreColors.tenue),
            ),
          ),
        ],
      ),
    );
  }
}
