import 'package:flutter/material.dart';

import '../../services/widget_refresh_settings.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'segmented.dart';

/// The same choice in Info and at the end of the first-launch welcome.
class WidgetRefreshOptions extends StatefulWidget {
  const WidgetRefreshOptions({super.key});

  @override
  State<WidgetRefreshOptions> createState() => _WidgetRefreshOptionsState();
}

class _WidgetRefreshOptionsState extends State<WidgetRefreshOptions> {
  int _minutes = WidgetRefreshSettings.defaultMinutes;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final minutes = await WidgetRefreshSettings.load();
    if (mounted) {
      setState(() {
        _minutes = minutes;
        _busy = false;
      });
    }
  }

  Future<void> _change(int minutes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await WidgetRefreshSettings.save(minutes);
      if (mounted) setState(() => _minutes = minutes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar. Tocá para reintentar.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('ACTUALIZACIÓN DEL WIDGET', style: TimbreText.sectionLabel),
      const SizedBox(height: 10),
      IgnorePointer(
        ignoring: _busy,
        child: TimbreSegmented<int>(
          values: WidgetRefreshSettings.options,
          selected: _minutes,
          labelOf: WidgetRefreshSettings.label,
          onChanged: _change,
          semanticLabel: 'Frecuencia de actualización del widget',
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Conserva la última consulta y su hora. Tocá ↻ en el widget '
        'para actualizar cuando quieras.',
        style: TimbreText.caption.copyWith(color: TimbreColors.papel),
      ),
      const SizedBox(height: 6),
      const Text(
        'Android puede demorar las actualizaciones automáticas para '
        'ahorrar batería.',
        style: TimbreText.caption,
      ),
    ],
  );
}
