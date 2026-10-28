import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/external_apps.dart';
import '../services/mvd_api_service.dart';
import '../services/official_sites.dart';
import 'privacy_policy_page.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/led_matrix.dart';
import 'widgets/pixel_icon.dart';
import 'widgets/timbre_app_bar.dart';
import 'widgets/timbre_bus.dart';

class InfoPage extends StatefulWidget {
  final bool biometricLockEnabled;

  /// Returns the lock state after the attempt (unchanged if cancelled).
  final Future<bool> Function(bool) onToggleBiometricLock;

  const InfoPage({
    super.key,
    required this.biometricLockEnabled,
    required this.onToggleBiometricLock,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  // Local copy: the parent's rebuild does not reach a pushed route
  late bool _biometricLockEnabled = widget.biometricLockEnabled;

  static const _notAffiliated = 'No está afiliada con la Intendencia de '
      'Montevideo, el STM ni ninguna empresa de transporte.';
  static const _sourceCode = 'github.com/undermindOS/MVD_Transporte';
  static const _contact = 'daniil@khrestenkov.com';
  static const _inBrowser = 'se abre en el navegador';

  /// Paragraphs of the cards.
  static final _reading = TimbreText.subtitle
      .copyWith(height: 1.45, color: TimbreColors.papel);

  Future<void> _onBiometricChanged(bool value) async {
    final result = await widget.onToggleBiometricLock(value);
    if (mounted) setState(() => _biometricLockEnabled = result);
  }

  Future<void> _openWeb(Uri uri) async {
    final ok = await SystemBrowser.open(uri);
    if (!ok && mounted) {
      _cannotOpen(
          'No se pudo abrir el navegador. Revisá que tengas uno activado.');
    }
  }

  Future<void> _writeEmail() async {
    var ok = false;
    try {
      ok = await ExternalApps.launch(Uri(scheme: 'mailto', path: _contact),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ Mail app error: $e');
    }
    if (!ok && mounted) {
      _cannotOpen('No se pudo abrir el correo. Revisá que tengas una app de '
          'correo configurada.');
    }
  }

  /// Bundled with the app: it opens here, not in the browser.
  void _openPrivacyPolicy() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()));

  /// What failed and what to do.
  void _cannotOpen(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The identity bar of the tabs, with the back arrow
      appBar: buildTimbreAppBar(context, title: 'Info'),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(TimbreSpace.l, 14, TimbreSpace.l, 28),
        children: [
          _card(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  // The app icon of the night board
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: TimbreColors.lineaNoche),
                    ),
                    child: const TimbreAppIcon(size: 64),
                  ),
                  const SizedBox(width: 14),
                  // The wordmark is a logo: with the largest fonts it
                  // scales down to the row instead of overflowing
                  Expanded(
                    child: Semantics(
                      label: 'Timbre MVD',
                      excludeSemantics: true,
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(text: 'Timbre', children: [
                            TextSpan(
                              text: ' MVD',
                              style: TextStyle(
                                  color: TimbreColors.ambar,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]),
                          style: TextStyle(
                              fontFamily: TimbreFonts.firaCondensed,
                              fontWeight: FontWeight.w800,
                              fontSize: 34,
                              height: 1,
                              color: TimbreColors.papel),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // The notice that matters most, on the LED board
                Semantics(
                  container: true,
                  label: 'Aplicación no oficial. $_notAffiliated',
                  excludeSemantics: true,
                  child: DecoratedBox(
                    // An inset board in the card
                    decoration: BoxDecoration(
                      color: TimbreColors.noche,
                      borderRadius: BorderRadius.circular(TimbreRadii.control),
                      border: Border.all(color: TimbreColors.lineaNoche),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(TimbreRadii.control),
                      child: Stack(children: [
                        const Positioned.fill(
                          child: LedMatrix(
                              color: TimbreColors.ambar, opacity: 0.11),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // A small system font must not shrink the
                              // dots below 19 px
                              MediaQuery.withClampedTextScaling(
                                minScaleFactor: 1,
                                child: Text('NO OFICIAL',
                                    style: TimbreText.cartel(22)
                                        .copyWith(letterSpacing: 1.5)),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _notAffiliated,
                                style: _reading,
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: MergeSemantics(
              child: Row(children: [
                // A label, not a lit LED
                const PixelIcon(PixelGlyphs.lock,
                    color: TimbreColors.etiquetaCartel,
                    size: TimbreIconSize.rowLarge),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bloqueo biométrico',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: TimbreColors.papel)),
                      SizedBox(height: 2),
                      // Mi STM lives in the browser now: the lock guards only
                      // what the app stores (saved stops and route alerts)
                      Text('Protege tus paradas y rutas guardadas',
                          style: TextStyle(
                              fontSize: 13,
                              color: TimbreColors.etiquetaCartel)),
                    ],
                  ),
                ),
                Switch(
                  value: _biometricLockEnabled,
                  onChanged: _onBiometricChanged,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Data source. Live ETAs come from the Cómo Ir online service, not
          // from an open dataset — if open datasets (e.g. GTFS) are added,
          // the "Licencia de Datos Abiertos – Uruguay" origin note must
          // name the provider, the license, the dataset and any changes.
          _card(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FUENTE DE DATOS', style: TimbreText.sectionLabel),
                const SizedBox(height: 8),
                Text(
                  'Tiempos de arribo, horarios por parada, novedades del '
                  'transporte y estado del GPS: servicios en línea de la '
                  'Intendencia de Montevideo, los mismos que usa Cómo Ir.',
                  style: _reading,
                ),
                // Only proxy builds get comfort data, and only they have a
                // server of their own in between
                if (MvdApiService.usesProxy) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Aire acondicionado y cero emisiones: API de transporte '
                    'público de Montevideo.',
                    style: _reading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Las consultas pasan por el servidor del proyecto, que no '
                    'guarda datos personales.',
                    style: _reading,
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Los tiempos son estimados. Los que llevan reloj son '
                  'horarios teóricos, sin ubicación GPS del ómnibus.',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: TimbreColors.etiquetaCartel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _LinkRow(
                title: 'Política de privacidad',
                icon: PixelGlyphs.chevronRight,
                onTap: _openPrivacyPolicy,
              ),
              const Divider(),
              _LinkRow(
                title: 'Código fuente',
                subtitle: _sourceCode,
                icon: PixelGlyphs.external,
                opensIn: _inBrowser,
                onTap: () => _openWeb(Uri.parse('https://$_sourceCode')),
              ),
              const Divider(),
              _LinkRow(
                title: 'Contacto',
                subtitle: _contact,
                icon: PixelGlyphs.mail,
                opensIn: 'se abre en tu app de correo',
                onTap: _writeEmail,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Desarrollada por Liberon Tech, de Khrestenkov & Co, con gratitud '
              'hacia Uruguay.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: TimbreColors.tenue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, required EdgeInsets padding}) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}

/// A link out of the app, or to a page of it. Screen readers hear one
/// phrase that says where a link out opens: "Código fuente, github.com/…,
/// se abre en el navegador".
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.opensIn,
  });

  final String title;
  final String? subtitle;
  final PixelGlyph icon;

  /// Where the link opens, said after the title ("se abre en el
  /// navegador"): the icon telling it is hidden from screen readers. Null
  /// for a page of the app.
  final String? opensIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: [title, ?subtitle, ?opensIn].join(', '),
      // excludeSemantics drops the InkWell's tap action too
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TimbreText.body
                            .copyWith(fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: TimbreColors.etiquetaCartel)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PixelIcon(icon,
                  size: TimbreIconSize.row, color: TimbreColors.ambar),
            ]),
          ),
        ),
      ),
    );
  }
}
