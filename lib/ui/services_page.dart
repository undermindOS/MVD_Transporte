import 'package:flutter/material.dart';

import '../services/official_sites.dart';

/// Official web services as tiles; each one opens in the system browser.
class ServicesPage extends StatelessWidget {
  final ValueChanged<OfficialSite> onOpen;

  const ServicesPage({super.key, required this.onOpen});

  static const _tiles = [
    (
      site: OfficialSite.miStm,
      icon: Icons.account_circle_outlined,
      title: 'Mi STM',
      subtitle: 'Saldo y movimientos de tu tarjeta',
    ),
    (
      site: OfficialSite.recarga,
      icon: Icons.credit_card_outlined,
      title: 'Recarga',
      subtitle: 'Recargá tu tarjeta STM',
    ),
    (
      site: OfficialSite.comoIr,
      icon: Icons.map_outlined,
      title: 'Cómo Ir',
      subtitle: 'Planificá tu viaje en ómnibus',
    ),
    (
      site: OfficialSite.avisos,
      icon: Icons.notifications_outlined,
      title: 'Avisos',
      subtitle: 'Notificaciones de tu cuenta STM',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final t in _tiles)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: primary.withAlpha(30),
                foregroundColor: primary,
                child: Icon(t.icon),
              ),
              title: Text(t.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              subtitle: Text(t.subtitle),
              trailing: const Icon(Icons.open_in_new, color: Colors.black38),
              onTap: () => onOpen(t.site),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 16, 8, 24),
          child: Text(
            'Se abren en tu navegador, en el sitio oficial de la Intendencia '
            'de Montevideo. La app no tiene acceso a tu usuario, tu '
            'contraseña ni tu saldo.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
