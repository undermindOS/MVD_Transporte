import 'package:flutter/material.dart';

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

  Future<void> _onBiometricChanged(bool value) async {
    final result = await widget.onToggleBiometricLock(value);
    if (mounted) setState(() => _biometricLockEnabled = result);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Info',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Icon(Icons.info_outline, size: 80, color: primary),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Acerca de',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Aplicación no oficial que reúne servicios de transporte público en línea y Cómo Ir para facilitar el uso del transporte en Montevideo. No está afiliada con la Intendencia de Montevideo ni con ninguna empresa de transporte.',
              style: TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 24),
            const Text(
              'Desarrollada por undermindOS / Liberon.tech con gratitud hacia Uruguay.',
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.black87,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            _buildBiometricTile(context, primary),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildContactItem(context, Icons.email, 'zhongnanhaii@yahoo.com'),
            const SizedBox(height: 12),
            _buildContactItem(
              context,
              Icons.code,
              'github.com/undermindOS/MVD_Transporte',
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            // Data source. Live ETAs come from the Cómo Ir online service, not
            // from an open dataset — if open datasets (e.g. GTFS) are added,
            // the "Licencia de Datos Abiertos – Uruguay" origin note must
            // name the provider, the license, the dataset and any changes.
            const Text(
              'Fuente de datos: servicios en línea de la Intendencia de '
              'Montevideo (los mismos que usa Cómo Ir). Los tiempos de arribo '
              'son estimados y pueden variar; los marcados con reloj son '
              'horarios teóricos, sin ubicación GPS del ómnibus.',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black54),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricTile(BuildContext context, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.fingerprint, color: primary, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bloqueo biométrico',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                // Mi STM lives in the browser now: the lock guards only
                // what the app stores (saved stops and route alerts)
                Text(
                  'Protege tus paradas y rutas guardadas',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          Switch(
            value: _biometricLockEnabled,
            onChanged: _onBiometricChanged,
            activeThumbColor: primary,
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
