import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/official_sites.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/timbre_bus.dart';

class InfoPage extends StatefulWidget {
  final bool biometricLockEnabled;

  /// Returns the lock state after the attempt (unchanged if cancelled).
  final Future<bool> Function(bool) onToggleBiometricLock;

  /// Public privacy policy. Google Play wants it inside the app too; the
  /// row stays hidden until the policy is published (docs/privacy-policy.md
  /// is still a draft).
  final Uri? privacyPolicyUrl;

  const InfoPage({
    super.key,
    required this.biometricLockEnabled,
    required this.onToggleBiometricLock,
    this.privacyPolicyUrl,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  // Local copy: the parent's rebuild does not reach a pushed route
  late bool _biometricLockEnabled = widget.biometricLockEnabled;

  static const _sourceCode = 'github.com/undermindOS/MVD_Transporte';
  static const _contact = 'zhongnanhaii@yahoo.com';

  Future<void> _onBiometricChanged(bool value) async {
    final result = await widget.onToggleBiometricLock(value);
    if (mounted) setState(() => _biometricLockEnabled = result);
  }

  Future<void> _openWeb(Uri uri) async {
    final ok = await SystemBrowser.open(uri);
    if (!ok && mounted) _cannotOpen();
  }

  Future<void> _writeEmail() async {
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'mailto', path: _contact),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ Mail app error: $e');
    }
    if (!ok && mounted) _cannotOpen();
  }

  void _cannotOpen() => ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('No se pudo abrir')));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Info'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
        children: [
          _card(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const TimbreAppIcon(size: 64),
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
                                  color: TimbreColors.anillo,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]),
                          style: TextStyle(
                              fontFamily: TimbreFonts.firaCondensed,
                              fontWeight: FontWeight.w800,
                              fontSize: 34,
                              height: 1,
                              color: TimbreColors.azul),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: TimbreColors.niebla,
                    borderRadius: BorderRadius.circular(TimbreRadii.control),
                  ),
                  child: const Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: 'Aplicación no oficial. ',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: 'No está afiliada con la Intendencia de '
                              'Montevideo, el STM ni ninguna empresa de '
                              'transporte.'),
                    ]),
                    style: TextStyle(
                        fontSize: 14, height: 1.45, color: TimbreColors.tinta),
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
                const Icon(Icons.lock_outline,
                    color: TimbreColors.azul, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bloqueo biométrico',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: TimbreColors.tinta)),
                      SizedBox(height: 2),
                      // Mi STM lives in the browser now: the lock guards only
                      // what the app stores (saved stops and route alerts)
                      Text('Protege tus paradas y rutas guardadas',
                          style: TextStyle(
                              fontSize: 13, color: TimbreColors.grisTexto)),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FUENTE DE DATOS', style: TimbreText.sectionLabel),
                SizedBox(height: 8),
                Text(
                  'Tiempos de arribo, horarios por parada, novedades del '
                  'transporte y estado del GPS: servicios en línea de la '
                  'Intendencia de Montevideo, los mismos que usa Cómo Ir.',
                  style: TextStyle(
                      fontSize: 14, height: 1.45, color: TimbreColors.tinta),
                ),
                SizedBox(height: 8),
                Text(
                  'Aire acondicionado y cero emisiones: API de transporte '
                  'público de Montevideo.',
                  style: TextStyle(
                      fontSize: 14, height: 1.45, color: TimbreColors.tinta),
                ),
                SizedBox(height: 8),
                Text(
                  'Los tiempos son estimados. Los que llevan reloj son '
                  'horarios teóricos, sin ubicación GPS del ómnibus.',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: TimbreColors.grisTexto),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (widget.privacyPolicyUrl != null) ...[
                _LinkRow(
                  title: 'Política de privacidad',
                  icon: Icons.open_in_new,
                  onTap: () => _openWeb(widget.privacyPolicyUrl!),
                ),
                const Divider(),
              ],
              _LinkRow(
                title: 'Código fuente',
                subtitle: _sourceCode,
                icon: Icons.open_in_new,
                onTap: () => _openWeb(Uri.parse('https://$_sourceCode')),
              ),
              const Divider(),
              _LinkRow(
                title: 'Contacto',
                subtitle: _contact,
                icon: Icons.mail_outline,
                onTap: _writeEmail,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Desarrollada por undermindOS / Liberon.tech con gratitud '
              'hacia Uruguay.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: TimbreColors.grisTexto),
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: TimbreColors.tinta)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 13, color: TimbreColors.grisTexto)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: TimbreColors.azul),
          ]),
        ),
      ),
    );
  }
}
