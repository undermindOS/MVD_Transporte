# En el código

Timbre MVD vive en el código de este repositorio: la app en Flutter (`lib/`)
y el proxy en un Worker de Cloudflare (`proxy/`). Esta página es el mapa:
qué archivo tiene qué y dónde se prueba. Si algo de acá no coincide con el
código, manda el código y hay que corregir la página
([README.md](README.md)).

Cómo viajan los datos entre la app y el proxy está en
[contrato-v1.md](contrato-v1.md); acá solo se nombran los archivos.

## De un vistazo

```
lib/
  main.dart              arranque, MaterialApp, licencias de las fuentes
  ui/theme/              tokens, estilos de texto y tema: los valores
  ui/widgets/            componentes del tablero
  ui/*.dart              pantallas
  ui/map/                la pestaña Mapa: la página, los ómnibus y las hojas
  services/              fachada de datos, caché, avisos, widget, navegador
  services/api/          capa /v1: fuentes, adaptadores, lector, reglas
  services/map/          el mapa base: el archivo PMTiles y el estilo
  models/                modelos (dos se guardan en Hive)
test/                    pruebas de la app; test/contract: el contrato /v1
proxy/
  src/                   el Worker, el Durable Object y un cliente por fuente
  contract/v1/           el contrato en datos, compartido con la app
  scripts/smoke.js       prueba de humo contra un proxy desplegado
assets/                  ícono, pantalla de inicio, fuentes, licencias y el mapa base
tool/map/                el generador del estilo del mapa base
android/, ios/           widget, notificaciones, estilos, Info.plist
docs/design/             este sistema; tokens.json lo verifica una prueba
```

## Tema: `lib/ui/theme/`

| Archivo | Qué tiene |
|---|---|
| `timbre_tokens.dart` | La única fuente de valores. `TimbreColors` (los 12 colores), `TimbreRadii`, `TimbreSpace` (con `touch` = 44), `TimbreOpacity` (LED apagados y toque), `TimbreIconSize` y `TimbreShadow.ledGlow`. Ver [02-color.md](02-color.md), [05-formas-y-espacio.md](05-formas-y-espacio.md) y [06-luz-y-movimiento.md](06-luz-y-movimiento.md) |
| `timbre_text.dart` | `TimbreFonts` (`fira`, `firaCondensed`, `doto`, `dotoMinSize` = 19) y `TimbreText`: `largeFrom` = 1.5, `isLarge(context)` y todos los estilos. Los del tablero: `pageTitle`, `sectionLabel`, `stopName`, `lineBadge`, `destination`, `liveMinutes()`, `minuteUnit`, `scheduleTime`, `cartel()`, `cartelLabel`. Los de lectura, en Fira Sans: `dialogTitle`, `buttonLarge`, `body`, `button`, `subtitle`, `tabLabel`, `caption`, `navLabel`. Ver [03-tipografia.md](03-tipografia.md) |
| `timbre_theme.dart` | `buildTimbreTheme()`: el `ColorScheme` oscuro (`Brightness.dark`) y el aspecto de cada pieza de Material: barra de la app y de estado, navegación, pestañas, tarjetas, botones, segmentos, interruptor, chips, hojas, diálogos, campos, snackbar, botón flotante, insignia, indicadores de carga, filas de lista, tooltip y selector de hora |

`MaterialApp` usa solo `theme: buildTimbreTheme()`, sin `darkTheme` ni
`themeMode` (`lib/main.dart`): hay un solo tema
([12-decisiones.md](12-decisiones.md#siempre-oscuro-sin-tema-claro)).

## Componentes: `lib/ui/widgets/`

| Archivo | Símbolos | Dónde se usa |
|---|---|---|
| `arrival_row.dart` | `ArrivalRow(arrival, waited, stale, onTap)`: un ómnibus en el tablero | Tarjetas de parada y de ruta (`stops_page.dart`), hoja de una parada del Mapa (`map/map_sheets.dart`) |
| `line_badge.dart` | `LineBadge(line, live, compact)`: relleno con GPS, contorno sin GPS | `ArrivalRow`, Horarios, hoja de un ómnibus del Mapa |
| `cartel.dart` | `CartelCompacto` (la placa TIMBRE MVD), `LiveDot`, `LlegandoChip`, `MinutosEnVivo`, `CartelTira` (la hoja de «Estoy esperando») y `CartelParada` | `CartelCompacto`, en la barra de cada pantalla y en el bloqueo; `MinutosEnVivo` (con `LiveDot`, o `LlegandoChip` a 0 min), en `ArrivalRow` y en la hoja de un ómnibus del Mapa; `CartelTira`, en `stops_page.dart`. `CartelParada` hoy solo aparece en `test/cartel_test.dart` |
| `empty_state.dart` | `TimbreEmptyState(message, sign, detail)`: una lista vacía como cartel | Mis paradas, Horarios, Novedades, el Mapa sin paradas |
| `segmented.dart` | `TimbreSegmented<T>` | Tipo de día en Horarios; 3, 5 o 10 min en «Estoy esperando» |
| `page_title_bar.dart` | `PageTitleBar`: el título grande y el subtítulo (hasta 4 líneas, `subtitleMaxLines`), con la altura medida según la letra del sistema | `buildTimbreAppBar` |
| `timbre_app_bar.dart` | `buildTimbreAppBar(…)`: el tablero de arriba con sus LED, la placa y el título | `HomePage`, Horarios, Info, Privacidad |
| `led_matrix.dart` | `LedMatrix(pitch, dot, color, opacity, fadeFrom)`: los LED apagados | La barra de arriba, los mosaicos de Servicios, el bloqueo, Info, la fecha sin leer de Novedades, `TimbreEmptyState`, `TimbreAppIcon` |
| `led_lock.dart` | `LedLock(pitch, scanning)`: el candado animado | Pantalla de bloqueo |
| `pixel_icon.dart` | `PixelGlyph` (12 filas de 12 celdas) y `PixelIcon(glyph, size, color, glow, semanticLabel)` | Todos los íconos de la app |
| `pixel_glyphs.dart` | `PixelGlyphs`: los 34 glifos. Es `part of 'pixel_icon.dart'` | Ver [04-iconos.md](04-iconos.md) |
| `timbre_bus.dart` | `TimbreBusPalette`, `TimbreBusDetail`, `TimbreBus`, `TimbreAppIcon` y `TimbreBusPainter`: el ómnibus de la marca | La placa, `TimbreEmptyState`; `TimbreAppIcon(size: 64)` en Info |

Tres archivos de apoyo están junto a las pantallas:

- `lib/ui/spoken_text.dart`: `spokenName()`, que pasa los nombres en
  mayúsculas de la API («PUNTA CARRETAS») a la forma en que los lee bien un
  lector de pantalla ([11-accesibilidad.md](11-accesibilidad.md)).
- `lib/ui/safe_html.dart`: `SafeHtml` y `htmlToBlocks`. Muestran solo el
  texto del HTML de una novedad: sin WebView, sin scripts, sin imágenes.
- `lib/ui/policy_markdown.dart`: `policyToBlocks`, que lee solo el Markdown
  de `docs/privacy-policy.md` (`# `, `## `, párrafos, `- `, `**negrita**` y
  `` `código` ``) y deja afuera las líneas citadas (`>`).

Qué muestra cada componente y de qué campo sale: [08-componentes.md](08-componentes.md)
y [pantalla-a-datos.md](pantalla-a-datos.md).

## Pantallas: `lib/main.dart` y `lib/ui/`

| Archivo | Qué es |
|---|---|
| `lib/main.dart` | `main()`: deja la pantalla de inicio hasta abrir Hive, las notificaciones, WorkManager y «Estoy esperando»; registra las licencias de las fuentes y de pixelarticons (`_registerFontLicenses`). `MiTransporteMVDApp`: `MaterialApp` con título «Timbre MVD», `HomePage.routeObserver` y `AppLock.routeGuard` en `navigatorObservers`, y `AppLock` en `builder`; recibe `deviceAuth` (`LocalDeviceAuth` por defecto, uno falso en las pruebas) |
| `app_lock.dart` | `AppLock` y `AppLockState`: el bloqueo biométrico, encima del `Navigator`. Pide la autenticación, vuelve a bloquear después del segundo plano, escucha `ExternalApps.launches`, hace la preparación única del primer desbloqueo (`_setupAfterAuth`) y prende o apaga el bloqueo desde Info (`setEnabled`). `AppLock.of(context)` da `locked` y `enabled`; `routeGuard` no deja cerrar rutas mientras está bloqueada; `clock` lo adelantan las pruebas |
| `home_page.dart` | `HomePage`: la navegación de abajo (Mis paradas, Mapa y Servicios, con los índices `_stopsTab` y `_mapaTab`), la apertura de Info (con `enabled` y `setEnabled` de `AppLock`) y de los sitios en el navegador. `routeObserver` avisa a Mis paradas y al Mapa cuando una página los tapa; con la app bloqueada, también les pasa `active: false`. El Mapa se arma la primera vez que se elige su pestaña (`_mapaOpened`), dentro de un `TickerMode` que lo deja sin animar fuera de la vista |
| `stops_page.dart` | `StopsPage`: las subpestañas Paradas, Rutas y Novedades; las tarjetas; `_refresh` (cada 30 s, `autoRefreshInterval`, solo con la pantalla a la vista); los datos viejos (`_staleFor` y `_liveFor`, desde `_BoardView.receivedAt` con el reloj `StopsPage.clock` que las pruebas adelantan; `_staleRowGrace`, en el reloj de la fuente); la hoja de «Estoy esperando» (`_showWaitSheet`); los diálogos `_AddStopDialog` y `_AddRouteDialog`; los ajustes de aviso (`_AlertSettingsSheet`); el aviso de GPS parcial |
| `news_list.dart` | `NewsList`, `_NewsRow`, `_DateTile`, `_FailedBanner`; `showNewsDetail` y `openExternalLink` |
| `schedule_page.dart` | `SchedulePage` (Horarios), `_HourHeader`, `_PassRow` |
| `services_page.dart` | `ServicesPage`, `_SiteTile`, `_BrowserNote` |
| `info_page.dart` | `InfoPage`, `_LinkRow` |
| `privacy_policy_page.dart` | `PrivacyPolicyPage` (Privacidad): lee el asset `docs/privacy-policy.md` (declarado en `pubspec.yaml`) y lo muestra con `policyToBlocks` |
| `lock_screen.dart` | `LockScreen`, con `LedLock` |

Estados, datos y refresco de cada pantalla: [09-pantallas.md](09-pantallas.md).

## El Mapa: `lib/ui/map/` y `lib/services/map/`

| Archivo | Qué tiene |
|---|---|
| `ui/map/mapa_page.dart` | `MapaPage(active, basemapLoader)`: la pestaña. Sin paradas guardadas, el cartel vacío y nada más. Al estar a la vista: el mapa base (una sola carga a la vez), `StopLocationsService.fillMissing`, los tableros de `MvdApiService.latestBoards` y `getBoards` cada 30 s (`StopsPage.autoRefreshInterval`), el salto de vueltas después de un 429 y su propio `WidgetsBindingObserver` (segundo plano, memoria baja). `MapaBasemap` envuelve a `Basemap` (`bundled`) para que las pruebas pasen uno sin teselas; `MapaPage.defaultBasemapLoader` y `MapaPage.clock` los cambian las pruebas. Privados: `_MapaView` (el `FlutterMap`, la cámara y sus opciones, armadas una vez), `_StopMarker`, `_Attribution`, `_MapNote`, `_FailedBanner`, `_NoStops`, `_Loading`, `_BasemapFailed` |
| `ui/map/map_buses.dart` | `MapBuses.from`: de los tableros de las paradas guardadas a la lista de `MapBus`, sin widgets y con el reloj de afuera. Un ómnibus por `tripId` `bus-…`, las posiciones fuera del recorte afuera, `liveness` (`liveFor` = 1 min, `staleFor` = 5 min, desde que el tablero llegó al teléfono) y `overdue` (`staleRowGrace` = 1 min, con el reloj de la fuente). `MapBus` lleva `etas`, una por parada (`MapBusEta`) |
| `ui/map/bus_layer.dart` | `BusLayer(buses, handle, animate)`: todos los ómnibus en una capa pintada. Píldoras desde el zoom 14 del estilo (`pillMinStyleZoom`), puntos más lejos; el movimiento de 1 s (`moveDuration`), que salta con reducir movimiento o con `animate: false`; el atlas de píldoras, que se vuelve a dibujar al volver del segundo plano. `BusLayerHandle.hitTest` dice qué ómnibus quedó debajo de un toque |
| `ui/map/map_sheets.dart` | `BusSheet` y `StopSheet`, las hojas de un ómnibus y de una parada; `stopPhrase`, la frase de una parada para el lector |
| `services/map/basemap.dart` | `Basemap`: el mapa base. `load` copia `assets/map/mvd-20261028.pmtiles` a `getApplicationCacheDirectory()/map/` (una vez, por un `.tmp`, y borra las copias viejas) y compila `assets/map/style_noche.json` con `ThemeReader`. Expone `bounds` (del encabezado del archivo), `attribution`, `layer()`, `fmZoom`/`styleZoom` (zoom del estilo = zoom de `flutter_map` − 1), `clearMemoryCache` y `dispose` |
| `services/map/local_pmtiles_provider.dart` | `LocalPmTilesProvider.open(path)`: lee las teselas del archivo copiado, sin red, y las entrega todavía comprimidas |

Procedencia, licencias y cómo regenerar el mapa base: [assets/map/README.md](../../assets/map/README.md).

## Datos: `lib/services/api/`

La capa /v1. La app siempre lee JSON con la forma /v1, venga del proxy o
armado en el teléfono ([contrato-v1.md](contrato-v1.md#en-la-app)).

| Archivo | Qué tiene |
|---|---|
| `api_result.dart` | `ApiFailure` (`offline`, `timeout`, `notFound`, `busy`, `unavailable`, `failed`), `ApiResult`, `ApiOk` y `ApiError` (con `retryAfter`) |
| `v1_source.dart` | La interfaz `V1Source`, un método por ruta: `stop`, `arrivals`, `schedule`, `catalogStops`, `news`, `gpsStatus`. Cada uno devuelve un `SourceAnswer` |
| `proxy_source.dart` | `ProxySource`: pide `/v1/…` al proxy. Tiempo máximo de 10 s, 30 s para el catálogo y 20 s para las novedades; `retryAfterOf` lee `Retry-After` (60 s si falta) |
| `direct_source.dart` | `DirectSource`: sin proxy, llama a la Intendencia desde el teléfono, con 10 s de tiempo máximo. `catalogStops` da `unavailable`. Una respuesta que no se puede convertir da `failed` solo para ese pedido (`_converted`) |
| `direct/transporte_rest_adapter.dart` | `TransporteRestAdapter`: parada, arribos y horario de transporteRest a /v1 |
| `direct/wfs_adapter.dart` | `WfsAdapter`: la capa WFS de geoserver a ítems del catálogo (paradas cercanas y ubicación de las paradas del Mapa en modo directo) |
| `direct/news_adapter.dart` | `NewsAdapter`, `NewsPageV1`: las páginas de notificacion a novedades /v1 |
| `direct/pci_adapter.dart` | `PciAdapter`: el GPS por empresa de pci a /v1 |
| `v1_parser.dart` | `V1Parser`: el único lector de cada forma /v1 a modelos. Una forma equivocada da `null`, que la fachada convierte en `failed` |
| `contract_rules.dart` | `ContractRules`: las reglas de derivación, espejo de `proxy/src/rules.js`. El comentario de cada regla nombra su archivo de vectores |

## Servicios: `lib/services/`

| Archivo | Qué tiene |
|---|---|
| `mvd_api_service.dart` | `MvdApiService`, la fachada. `proxyUrl` sale de `--dart-define=MVD_PROXY_URL`; `usesProxy` y `source` eligen `ProxySource` o `DirectSource`. Llamadas: `getBoard`, `getBoards` (cada parada una vez, en paralelo; cada tablero bueno queda en `latestBoards`, el más nuevo por parada, con la hora en que llegó al teléfono, que lee el Mapa: `ReceivedBoard`, con el reloj `MvdApiService.clock`; un tablero con `fetchedAt` más viejo no reemplaza al guardado, salvo que el guardado haya llegado «después de ahora», un reloj atrasado), `getStopDetails`, `healPlaceholderStops`, `getSchedule` (guardado 6 h), `getStopCatalog` (guardado un día; uno sin líneas, 15 min, y nunca encima de una copia con líneas), `searchStops`, `getNews`, `getGpsStatus`, `isValidStopId`, `montevideoClock`. Después de un 429 no pide nada hasta `retryAfter`. Quedan por compatibilidad `getNextArrivals`, `resolveStop` (con `StopNotFoundException`), `parseArrivals` y `parseSchedule` |
| `cache_service.dart` | `CacheService`: las cajas de Hive `settings`, `stops` y `routes`, y la caja diferida `catalog` (el cuerpo del catálogo y `fetched_at_ms`). La migración `cache_schema` = 2 borra el catálogo viejo de `settings` |
| `nearby_stops_service.dart` | `NearbyStopsService`: `findNearMe`, `nearbyFrom`, `radiusMeters` = 400, `boxHalfSideMeters` = 472, `openAppSettings` (con `ExternalApps.open`); `NearbyStopsError`. Sin proxy, `fetchStop` pide a geoserver una parada por su número (`buildStopUri`, `CQL_FILTER`, sin caja) |
| `stop_locations_service.dart` | `StopLocationsService.fillMissing`: la ubicación de las paradas guardadas que no la tienen, para el Mapa. Con proxy, del catálogo del teléfono; sin proxy, de `NearbyStopsService.fetchStop`, una por vez. Cada parada se busca como mucho cada 10 min (`retryInterval`) y la ubicación se guarda en `BusStop` |
| `transport_news_service.dart` | `TransportNewsService`: refresco cada 10 min, o 30 s si lo pedís; guarda hasta 30 novedades; `unreadCount`, `markRead` |
| `bus_status_service.dart` | `BusStatusService`: el GPS por empresa, una consulta por minuto como mucho; `partialWarning` |
| `background_worker.dart` | `BackgroundWorker`: la tarea de WorkManager cada 15 min (`checkAlerts`), y `sync` para registrarla o cancelarla y para vaciar el widget cuando no queda ninguna ruta activa |
| `home_widget_feed.dart` | `WidgetFeed`: escribe las claves del widget de Android (`update`, `clear`) ([10-superficies.md](10-superficies.md#qué-muestra-las-claves)) |
| `notification_service.dart` | `NotificationService`: el canal `bus_alerts`, `showBusAlert`, `showRouteAlert`, `scheduleWaitReminder` |
| `bus_wait_service.dart` | `BusWaitService` («Estoy esperando»), `AndroidBusWait` (servicio en primer plano, canal `bus_wait`) y `ScheduledBusWait` (recordatorio en iOS); `WaitStart` |
| `bus_wait_task.dart` | `BusWaitTaskHandler`: la consulta cada 30 s dentro del servicio de Android |
| `official_sites.dart` | `OfficialSite` (`miStm`, `recarga`, `comoIr`, `avisos`), `comoIrStop` y `SystemBrowser.open`: los sitios oficiales se abren en el navegador, nunca dentro de la app |
| `external_apps.dart` | `ExternalApps`: la única salida a otra app. `launch` abre una URL (navegador, correo, enlace de una novedad) y `open`, una llamada de plugin (los ajustes del sistema); las dos avisan antes a `launches`, que escucha el bloqueo |
| `device_auth.dart` | `DeviceAuth`, el pedido de autenticación del sistema, y `LocalDeviceAuth`, con `local_auth` (`stickyAuth`, `biometricOnly: false`) |

## Modelos: `lib/models/`

| Archivo | Qué es |
|---|---|
| `bus_arrival.dart` | `BusArrival` y `ArrivalState` (`arriving`, `live`, `scheduled`): un ítem de `arrivals`; `location` (`{lat, lng}` o `null`) es la posición del ómnibus con GPS |
| `arrivals_board.dart` | `ArrivalsBoard`: `stopId`, `fetchedAt` y los arribos. `ReceivedBoard`: un tablero y la hora en que llegó al teléfono. `ReceivedBoardClock.sourceNow`: el «ahora» de la fuente (`fetchedAt` más lo que el tablero lleva en el teléfono), con el que Mis paradas y `MapBuses.overdue` cortan las filas estimadas vencidas |
| `stop_details.dart` | `StopDetails` y `StopDirection`: nombre, líneas y direcciones de una parada |
| `catalog_stop.dart` | `CatalogStop`: una parada del catálogo, con líneas y posición; `fold` para buscar por calles |
| `nearby_stop.dart` | `NearbyStop`: una parada cercana, con su distancia |
| `scheduled_pass.dart` | `ScheduledPass` y `DayType` (`habil`, `sabado`, `domingo`) |
| `transport_news.dart` | `TransportNews`: `fromV1` lee la red; `fromJson`/`toJson`, la caché |
| `gps_status.dart` | `OperatorGpsStatus`, con `partialThreshold` = 70 |
| `bus_stop.dart` | `BusStop`, guardado en Hive (`typeId` 0, caja `stops`); el adaptador está en `bus_stop.g.dart`. `latitude` y `longitude` en 0, 0 quieren decir «sin ubicación» (`hasLocation`, que no se guarda) |
| `route_alert.dart` | `RouteAlert`, guardado en Hive (`typeId` 1, caja `routes`), campos 0 a 11; el 11 es `preferredVariantIds`. `accepts` decide si un ómnibus sirve a la ruta. El adaptador está en `route_alert.g.dart` |
| `alert_schedule.dart` | `AlertSchedule`: días y horas de un aviso |
| `bus_wait.dart` | `BusWait`, `WaitCheck`, `WaitOutcome`: el viaje que esperás; `expectedAt` en el reloj de la fuente, `clockOffset` y `expectedOnPhone` en el del teléfono |

Los `*.g.dart` se generan con `dart run build_runner build`. `hive_generator`
no entiende los elementos de colección con `?` (`[?x]`): si los usás en
`lib/`, regenerar los adaptadores falla.

## Pruebas: `test/`

| Grupo | Archivos |
|---|---|
| Diseño y marca | `design_tokens_test.dart` (`tokens.json` igual al código), `brand_assets_test.dart`, `cartel_test.dart`, `screens_test.dart`, `lock_screen_test.dart`, `info_page_test.dart`, `privacy_policy_test.dart`, `spoken_text_test.dart`, `safe_html_test.dart` |
| Letra grande | `stops_layout_test.dart`, `stop_search_layout_test.dart`, `map/mapa_layout_test.dart` |
| Pantallas y flujos | `widget_test.dart` (también: el Mapa no se arma hasta que se elige y pide solo a la vista), `app_lock_test.dart` (el bloqueo sobre la app entera, con un `DeviceAuth` falso; tampoco el Mapa pide nada bloqueado), `stops_page_test.dart`, `stops_board_test.dart`, `add_dialogs_test.dart`, `stop_search_test.dart`, `news_tab_test.dart`, `schedule_test.dart` |
| Mapa | `map/mapa_page_test.dart` (la pestaña con proxy y sin proxy, con un mapa base sin teselas), `map/mapa_camera_test.dart` (una parada ubicada con el mapa ya abierto entra en la cámara), `map/map_buses_test.dart`, `map/bus_layer_test.dart`, `map/basemap_test.dart` (la copia del archivo), `map/local_pmtiles_provider_test.dart`, `map/basemap_assets_test.dart` (los archivos de `assets/map/`: SHA-256, bordes y el estilo compilado, sin ámbar) |
| Datos | `mvd_api_service_test.dart`, `cache_service_test.dart`, `nearby_stops_service_test.dart`, `stop_locations_service_test.dart`, `transport_news_service_test.dart`, `bus_status_service_test.dart`, `background_worker_test.dart`, `bus_wait_test.dart`, `route_alert_test.dart`, `alert_schedule_test.dart` |
| Privacidad | `proxy_privacy_test.dart` (cada servicio con proxy pide solo al proxy y nunca manda la posición), `proxy_bff_test.dart` (lo mismo, desde las pantallas) |
| Contrato /v1 | `contract/contract_test.dart` (modo directo y modo proxy contra los goldens), `contract/rules_test.dart` (los vectores) |
| Apoyo | `support/layout.dart` (`loadBundledFonts()`, `usePhoneScreen()`: 390 × 844), `support/contract_cases.dart` (lee `proxy/contract/v1`), `support/pmtiles_builder.dart` (archivos PMTiles chicos para las pruebas, copiado de `flutter_map_vector_tiles` con su licencia BSD-3) |
| Capturas | `fixtures/`: respuestas reales que usan las pruebas de servicios y pantallas. Las del contrato están en `proxy/contract/v1/upstream/` |

Qué tener en cuenta:

- **Corré `flutter test` desde la raíz del repositorio.** Las pruebas del
  contrato, `design_tokens_test.dart` y `support/layout.dart` leen archivos
  por ruta relativa.
- **Disposición con fuentes reales.** Las pruebas de layout cargan las
  fuentes de la app y usan un teléfono de 390 × 844, con la letra a 1×, 1.3×
  y 2×. Cualquier desborde hace fallar la prueba.
- **Lectores de pantalla.** Cada fila se prueba por su frase completa, con
  `find.bySemanticsLabel`.
- **Hive en pruebas de widgets.** En cada archivo, solo la primera prueba
  que espera una escritura en una caja puede esperarla; las siguientes no
  despiertan. Por eso algunos flujos tienen archivo propio (ver el
  comentario al principio de `test/stop_search_test.dart`).
- **El Mapa en pruebas de widgets.** El estilo de verdad se compila en un
  isolate que no contesta dentro de una prueba de widgets. Las pruebas le
  pasan a `MapaPage` un `MapaBasemap` sin teselas (`basemapLoader`), y las
  de la app entera cambian `MapaPage.defaultBasemapLoader`. El mapa base de
  verdad se prueba aparte, con `test()`: `map/basemap_assets_test.dart`.
- **Canales de plataforma.** Una llamada a un canal sin simular, como
  `home_widget`, no termina nunca dentro de una prueba de widgets. Simulalo
  (`MethodChannel('home_widget')`) o no esperes esa llamada. La línea
  «Widget data error: MissingPluginException» en la salida no es un fallo.
- **Lo que no prueban.** Los recursos de Android y el widget se comprueban
  con `flutter build apk --debug` y con `brand_assets_test.dart`, sin
  emulador. Los cambios de iOS (`Info.plist`, storyboard) no se compilaron
  en esta versión.

## Proxy: `proxy/`

| Archivo | Qué tiene |
|---|---|
| `src/index.js` | El Worker: límite por IP, solo `GET`, sin query string, la tabla `ROUTES` de las seis rutas `/v1`, el `Cache-Control` de cada una y `respond()`, que convierte cualquier error en JSON |
| `src/im_gateway.js` | `ImGateway`, el Durable Object: el único que llama a la API oficial (`BUDGET_PER_MINUTE` = 12), y el índice de paradas en 64 partes (`STOP_META_BUCKETS`). Rutas internas: `/vehicles`, `/stops/{id}/meta`, `/catalog/stops`; `/lines/{line}/buses` y `/catalog/lines` quedan sin ruta pública |
| `src/transporte_rest.js`, `src/notificacion.js`, `src/pci.js`, `src/geoserver.js`, `src/im_api.js` | Un cliente por fuente, cada uno con su lectura a la forma /v1 |
| `src/rules.js` | Las reglas de derivación; su gemelo en Dart es `contract_rules.dart` |
| `src/errors.js`, `src/http.js` | `UpstreamError`, `StopNotFoundError`; `fetchUpstream` con un User-Agent, un tiempo máximo y errores de texto fijo |
| `wrangler.jsonc` | La caché de Workers, el Durable Object `IM_GATEWAY` y el límite de 300 pedidos por minuto por IP |
| `scripts/smoke.js` | Prueba de humo contra un proxy desplegado |
| `test/` | `contract.test.js`, `rules.test.js`, `index.test.js`, `im_gateway.test.js`, `geoserver.test.js`, `notificacion.test.js`, `pci.test.js`, `smoke.test.js`; `support/contract.js` lee el contrato |

Cómo correrlo, desplegarlo y qué registra: [proxy/README.md](../../proxy/README.md).

## Contrato: `proxy/contract/v1/`

| Archivo | Qué es |
|---|---|
| `cases.json` | Los 24 casos compartidos: pedido, fuentes simuladas, respuesta esperada |
| `direct_masks.json` | Los campos que el modo directo no tiene (confort y direcciones) |
| `responses/` | Los cuerpos /v1 esperados (goldens), escritos a mano |
| `upstream/` | Capturas de cada fuente, con fecha |
| `vectors/` | Entradas y salidas de cada regla de derivación, nueve archivos |

Lo corren los dos lados: `proxy/test/contract.test.js` y
`proxy/test/rules.test.js` en el proxy, `test/contract/` en la app. La
mecánica está en [proxy/contract/v1/README.md](../../proxy/contract/v1/README.md);
el porqué, en [contrato-v1.md](contrato-v1.md#11-el-triángulo-de-pruebas).

## Plataforma y recursos

| Dónde | Qué |
|---|---|
| `assets/` | El ícono y la pantalla de inicio (`app_icon*.png`, `splash_icon*.png`, `README.md`), las fuentes con sus licencias OFL (`fonts/`), la licencia MIT de pixelarticons (`licenses/`) y el mapa base (`map/`: `mvd-20261028.pmtiles`, `style_noche.json` y su `README.md`, que no viaja con la app) |
| `tool/map/` | El generador del estilo «Timbre Noche» (`gen_style.mjs`, `flavor_noche.json` y un `package.json` con versiones fijas). Cómo se usa: [assets/map/README.md](../../assets/map/README.md) |
| `pubspec.yaml` | Las familias de fuentes, los archivos que viajan con la app (las licencias, la política y los dos archivos del mapa base, nunca la carpeta entera) y la configuración de `flutter_launcher_icons` |
| `flutter_native_splash.yaml` | La pantalla de inicio |
| `android/app/src/main/res/` | El widget (`layout/mvd_transporte_widget.xml`, `xml/mvd_transporte_widget_info.xml`, `drawable/widget_*`, `drawable-nodpi/widget_plate.png`), el ícono de notificación `drawable/ic_stat_timbre.xml`, `values/colors.xml`, `values/strings.xml` y los cuatro `styles.xml` |
| `android/app/src/main/kotlin/com/liberontech/stmapp/MVDTransporteWidgetProvider.kt` | Lee las claves del widget y llena sus vistas |
| `android/app/src/main/AndroidManifest.xml` | El nombre, el servicio en primer plano `dataSync` y el ícono del aviso fijo (`com.liberontech.stmapp.NOTIFICATION_ICON`) |
| `ios/Runner/` | `Info.plist`, `Base.lproj/LaunchScreen.storyboard`, `AppDelegate.swift` |

Detalle de cada superficie: [10-superficies.md](10-superficies.md).

## Fuentes

| En Flutter | Archivos | Pesos |
|---|---|---|
| `TimbreFonts.fira` = `'FiraSans'` | `assets/fonts/FiraSans-*.ttf` | 400, 500, 600, 700 |
| `TimbreFonts.firaCondensed` = `'FiraSansExtraCondensed'` | `assets/fonts/FiraSansExtraCondensed-*.ttf` | 600, 700, 800 |
| `TimbreFonts.doto` = `'Doto'` | `assets/fonts/Doto-Black.ttf` | 900 |

Las tres van con la app bajo SIL OFL 1.1, y `_registerFontLicenses` en
`lib/main.dart` las muestra en la página de licencias del sistema. En este
sistema se nombran por su familia: Fira Sans, Fira Sans Extra Condensed,
Doto ([03-tipografia.md](03-tipografia.md)).

## Cómo agregar

El proceso completo (código, `tokens.json`, prueba y documentación en el
mismo cambio) está en [README.md](README.md#cómo-proponer-un-cambio).

- **Un color o un tamaño.** Un token nuevo en `timbre_tokens.dart`, con un
  comentario que diga dónde se usa y, si es color de texto, su contraste.
  Después, la misma entrada en [tokens.json](tokens.json) y en el mapa que
  corresponde de `test/design_tokens_test.dart`. En los widgets no se
  escriben literales `Color(0x…)`; la única excepción hoy es el negro opaco
  del shader de `led_matrix.dart`.
- **Un ícono.** Un `PixelGlyph` en `PixelGlyphs`: 12 textos de 12
  caracteres, `#` encendido y `.` apagado, con un comentario de para qué se
  usa. Si sale de pixelarticons, marcalo `(pixelarticons)` en el comentario.
  Si cambiás `clock`, `route` o `external`, rehacé a mano su vector del
  widget de Android ([10-superficies.md](10-superficies.md#cómo-se-ve)).
- **Un componente.** En `lib/ui/widgets/`. Colores y letras solo de los
  tokens y de `TimbreText`. Para el lector de pantalla, una sola frase con
  `Semantics` (los nombres de la API, con `spokenName`). Una prueba de
  layout con fuentes reales a 1×, 1.3× y 2×.
- **Una pantalla.** La barra de arriba con `buildTimbreAppBar` (la placa y
  `PageTitleBar`), el fondo `noche` que pone el tema, `TimbreEmptyState`
  para una lista vacía y los textos de [07-textos.md](07-textos.md).
- **Un dato nuevo de la API.** Primero el contrato: el golden, los
  vectores y los casos, en los dos lados
  ([contrato-v1.md](contrato-v1.md#10-para-cambiar-el-contrato)). Después
  `V1Parser` y el modelo.

---

Ver también: [README.md](README.md), [contrato-v1.md](contrato-v1.md),
[pantalla-a-datos.md](pantalla-a-datos.md).
