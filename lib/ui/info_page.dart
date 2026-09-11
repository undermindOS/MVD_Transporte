import 'package:flutter/material.dart';

class InfoPage extends StatelessWidget {
  final bool biometricLockEnabled;
  final void Function(bool) onToggleBiometricLock;

  const InfoPage({
    super.key,
    required this.biometricLockEnabled,
    required this.onToggleBiometricLock,
  });

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
              'github.com/undermindOS/mi_Transporte_MVD',
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
                Text(
                  'Protege tu información con huella o Face ID',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          Switch(
            value: biometricLockEnabled,
            onChanged: onToggleBiometricLock,
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
