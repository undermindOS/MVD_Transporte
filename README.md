# MVD_Transporte

Timbre MVD: app no oficial en Flutter para el transporte público de Montevideo. Tiene tres
pestañas nativas: «Mis paradas» —paradas y rutas guardadas con los tiempos de arribo de los
ómnibus, horarios, novedades, notificaciones y un widget de Android—, «Mapa», con tus paradas
guardadas y los ómnibus con GPS que se acercan a ellas, sobre un mapa que viene dentro de la app,
y «Servicios», con accesos rápidos a los sitios oficiales (Mi STM, recarga de la tarjeta, Cómo Ir,
Avisos), que se abren en el navegador del sistema (Custom Tabs / SFSafariViewController) y no en
un WebView integrado.

No está afiliada a la Intendencia de Montevideo.

## Datos

Con `--dart-define=MVD_PROXY_URL=…` la app le pide todo al proxy del proyecto, un Cloudflare
Worker ([proxy/](proxy/README.md)) con rutas `/v1`: tiempos de arribo, paradas (nombre, líneas y
destinos), horarios, el catálogo de paradas, novedades y el estado del GPS. El proxy guarda la
clave de la API oficial de la IM (`api.montevideo.gub.uy/api/transportepublico`, OAuth2,
14 pedidos por minuto para todos) y agrega a los ómnibus con GPS si tienen aire acondicionado y si
son «cero emisiones». Los tiempos de arribo y los horarios siguen saliendo de los servicios
abiertos que usa la versión web de Cómo Ir (`api.montevideo.gub.uy/transporteRest`), pero los
pide el proxy: la app no se conecta con ningún servidor de la Intendencia. «Paradas cercanas» se
calcula en el teléfono con el catálogo, así que tu ubicación no sale del dispositivo; con el mismo
catálogo se busca una parada por los nombres de sus calles («Buscar por calles»).

Sin `MVD_PROXY_URL`, la app usa directamente los servicios abiertos de la ciudad, como la versión
web de Cómo Ir: `transporteRest` para arribos, paradas y horarios, `notificacion/mensajes` para las
novedades y `pci.montevideo.gub.uy/buses/control` para el estado del GPS. No hay datos de confort,
ni destinos por línea, ni búsqueda por calles. «Paradas cercanas» le pide al WFS abierto del
GeoServer de la IM (`geoserver.montevideo.gub.uy/geoserver/ows`, capa `imm:v_uptu_paradas`, sin
autenticación) un área aproximada alrededor de tu posición redondeada a 3 decimales, y filtra en el
teléfono con la posición exacta. Este modo queda hasta que el proxy esté desplegado.

El mapa de la pestaña «Mapa» viene dentro de la app (`assets/map/`): un recorte de Protomaps de
Montevideo y alrededores, con datos de OpenStreetMap (licencia ODbL) y el estilo «Timbre Noche».
No hay servidor de teselas: moverlo no le pide nada a nadie, y el mapa no usa tu ubicación. La
posición de los ómnibus es `arrivals[].location` de `/v1`. La de una parada guardada que no la
tiene sale del catálogo con el proxy y, sin proxy, del mismo WFS de geoserver, pedida por número
de parada. Procedencia y licencias: [assets/map/README.md](assets/map/README.md).

El botón «Ver en Cómo Ir» abre la parada con el deep link `m.montevideo.gub.uy/comoir/parada?numero={id}`.
El contrato /v1 está en [docs/design/contrato-v1.md](docs/design/contrato-v1.md); el mapa de la API,
las condiciones de uso y las restricciones legales, en [docs/REVIEW.md](docs/REVIEW.md).

## Cómo ejecutarla

```bash
flutter pub get
flutter test
flutter run
```

Con el proxy (la dirección del Worker después del deploy, o `http://127.0.0.1:8787` con
`npm run dev` en `proxy/`):

```bash
flutter run --dart-define=MVD_PROXY_URL=https://mvd-transporte-proxy.<subdominio>.workers.dev
```

Las builds para las tiendas llevan el mismo `--dart-define`. Primero se despliega el proxy y
después la app.

## Estructura

- `lib/services/mvd_api_service.dart` — punto de entrada de los datos (arribos, paradas, horarios,
  catálogo, estado GPS); elige la fuente: el proxy o el modo directo
- `lib/services/api/` — capa de datos del contrato /v1: `ProxySource` (el proxy), `DirectSource` y
  `direct/` (los servicios de la ciudad convertidos a JSON v1 en el teléfono), `V1Parser`,
  `ApiResult`, `ContractRules`
- `proxy/` — Cloudflare Worker: rutas `/v1`, Durable Object `ImGateway` con la clave de la API oficial
- `proxy/contract/v1/` — el contrato /v1 compartido: casos, respuestas esperadas y vectores que usan
  las pruebas del proxy y de la app
- `lib/services/nearby_stops_service.dart` — paradas cercanas (con proxy, del catálogo en el
  teléfono; sin proxy, del WFS)
- `lib/services/background_worker.dart` — verificación de alertas en segundo plano (WorkManager, ≥15 min)
- `lib/models/bus_wait.dart`, `lib/services/bus_wait_service.dart`, `lib/services/bus_wait_task.dart` —
  «Estoy esperando»: en Android, un servicio en primer plano (consulta cada 30 s); en iOS, un recordatorio
  para la hora prevista
- `lib/ui/stops_page.dart` — paradas y rutas
- `lib/ui/home_page.dart` — pestañas
- `lib/ui/map/`, `lib/services/map/`, `lib/services/stop_locations_service.dart` — la pestaña Mapa:
  los ómnibus y sus hojas, el mapa base dentro de la app y la ubicación de las paradas guardadas
- `assets/map/`, `tool/map/` — el mapa base, su estilo y el generador del estilo
- `lib/ui/app_lock.dart`, `lib/ui/lock_screen.dart` — bloqueo biométrico, encima de toda la app
- `lib/ui/services_page.dart`, `lib/services/official_sites.dart` — sitios oficiales en el navegador del sistema
- `lib/ui/theme/` — el sistema de diseño Timbre: colores, medidas y opacidades (`timbre_tokens.dart`),
  estilos de texto (`timbre_text.dart`) y tema (`timbre_theme.dart`); los componentes están en
  `lib/ui/widgets/`. Guía: [docs/design/README.md](docs/design/README.md)
- `android/.../MVDTransporteWidgetProvider.kt` — widget de la pantalla de inicio

Historial de cambios: [CHANGELOG.md](CHANGELOG.md).
