# MVD_Transporte

App no oficial en Flutter para el transporte público de Montevideo: una pestaña nativa
«Mis paradas» —paradas y rutas guardadas con los tiempos de arribo de los ómnibus,
notificaciones y un widget de Android— y accesos rápidos a los sitios oficiales (Mi STM, recarga
de la tarjeta, Cómo Ir, Avisos), que se abren en el navegador del sistema (Custom Tabs /
SFSafariViewController) y no en un WebView integrado.

No está afiliada a la Intendencia de Montevideo.

## Datos

Los tiempos de arribo y los nombres de las paradas vienen de los servicios abiertos de la Intendencia de Montevideo
que usa la versión web de Cómo Ir (`api.montevideo.gub.uy/transporteRest`).
La búsqueda de paradas cercanas («Paradas cercanas») usa el WFS abierto del GeoServer de la IM
(`geoserver.montevideo.gub.uy/geoserver/ows`, capa `imm:v_uptu_paradas`, sin autenticación).
El botón «Ver en Cómo Ir» abre la parada con el deep link `m.montevideo.gub.uy/comoir/parada?numero={id}`.
El mapa de la API, las condiciones de uso y las restricciones legales están en [docs/REVIEW.md](docs/REVIEW.md).

## Cómo ejecutarla

```bash
flutter pub get
flutter test
flutter run
```

## Estructura

- `lib/services/mvd_api_service.dart` — cliente de la API (ETA, paradas)
- `lib/services/nearby_stops_service.dart` — paradas cercanas (geolocalización + WFS)
- `lib/services/background_worker.dart` — verificación de alertas en segundo plano (WorkManager, ≥15 min)
- `lib/models/bus_wait.dart`, `lib/services/bus_wait_service.dart`, `lib/services/bus_wait_task.dart` —
  «Estoy esperando»: en Android, un servicio en primer plano (consulta cada 30 s); en iOS, un recordatorio
  para la hora prevista
- `lib/ui/stops_page.dart` — paradas y rutas
- `lib/ui/home_page.dart` — pestañas, bloqueo biométrico
- `lib/ui/services_page.dart`, `lib/services/official_sites.dart` — sitios oficiales en el navegador del sistema
- `android/.../MVDTransporteWidgetProvider.kt` — widget de la pantalla de inicio

Historial de cambios: [CHANGELOG.md](CHANGELOG.md).
