# MVD Transporte — revisión, API y marco legal

**Fecha:** 2026-10-17 · **Rama:** `main` · **Flutter** 3.41.1 / Dart 3.11.0

Todas las afirmaciones sobre la API se verificaron con solicitudes en vivo el 17/10/2026; las de las reglas de las tiendas
y la licencia, en las fuentes primarias, con los enlaces al final. Parte de los puntos se volvió a verificar en
una sesión de revisión paralela; los hallazgos coincidentes están marcados con ✔︎.

**Actualización 2026-10-27** (rama `feat/timbre-bff`): el mapa de la API (§2) y las propuestas de §6 (1, 2 y 9,
y la paginación de las novedades) describen ahora el proxy `/v1`, un Backend-for-Frontend: de qué fuente sale
cada ruta, el presupuesto de la API oficial y el índice de paradas (§2.5). El resto del documento es la revisión
del 17/10. El contrato completo está en [design/contrato-v1.md](design/contrato-v1.md).

---

## 1. Qué es esta aplicación

Aplicación Flutter (Android como plataforma principal; iOS configurado parcialmente):

| Pestaña | Tipo | Fuente |
|---|---|---|
| Inicio | WebView | `stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml` (Mi STM, inicio de sesión mediante SAML SSO `ih.montevideo.gub.uy`) |
| Recarga | WebView | `stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml` |
| Mis paradas | nativa | paradas y rutas A→B con ETA, alertas (WorkManager, cada 15 min) |
| Cómo Ir | WebView | `m.montevideo.gub.uy/comoir/` (SPA en Ionic 3) |
| Avisos | WebView | `stm.gub.uy/.../notificaciones.xhtml` |

Además: bloqueo biométrico, widget de Android (saldo de la tarjeta obtenido por scraping + próximo ómnibus),
almacenamiento en Hive.

**Hallazgo principal:** la parte nativa (ETA, nombres de paradas, alertas, widget) **no funcionaba**:
los dos endpoints que usaba están muertos (ver §2).

---

## 2. API de la Intendencia de Montevideo

### 2.1 Lo que usaba la aplicación — muerto

| Solicitud | Respuesta 17/10/2026 |
|---|---|
| `POST m.montevideo.gub.uy/stmonlineRest/nextETA` `{"parada": N}` | `400 {"error": "Argumentos invalidos!!!"}` (con `linea`, FeatureCollection vacía ✔︎) |
| `GET m.montevideo.gub.uy/transporteRest/variantes/{id}` | `500 No existe la ubicación de parada…` para cualquier id |

### 2.2 Endpoints abiertos de Cómo Ir (sin autorización)

Se encontraron en la configuración de `m.montevideo.gub.uy/comoir/build/main.js`. Hoy se usan `siguientesParada`
(arribos y horarios), `lineas`, `notificacion/mensajes`, `pci…/buses/control`, el WFS `imm:v_uptu_paradas` y el
deep link `/comoir/parada` («Ver en Cómo Ir»). Con `MVD_PROXY_URL` los pide el proxy (§2.5) y la app solo abre el
deep link en el navegador; sin él, los pide la app (`lib/services/api/direct_source.dart` y `direct/`; el WFS,
`lib/services/nearby_stops_service.dart`; las novedades, `lib/services/transport_news_service.dart`).

| Endpoint | Propósito |
|---|---|
| `GET api.montevideo.gub.uy/transporteRest/siguientesParada/{parada}` | próximos ómnibus (POST con `[codigoLinea…]`: filtro por líneas) |
| `GET …/transporteRest/lineas/{parada}` | `{"descripcion":"<esquina>","lineas":[{"descripcion":"G8","codigo":437}]}` |
| `GET …/transporteRest/siguientesParada/{parada}/{HABIL\|SABADO\|DOMINGO}/{H:MM}` | horarios por tipo de día: ~50 pasadas desde `H:MM` (`8:05` y `8:5` son equivalentes), pasando la medianoche; `minutos:null`, `real:false`, `accesibilidad:false/0`; otro `tipoDia` → 500 |
| `POST …/transporteRest/siguientesRuteo/…`, `…/partesCirculares/` | ETA por trayecto, circulares |
| `api.montevideo.gub.uy/comoirRest/rest/comoir/{caminando,bus,cortarRecorrido,duracionRuteo}` | cálculo de trayectos |
| `api.montevideo.gub.uy/ubicacionesRest/…` | geocodificación: esquinas, direcciones, POI |
| `GET api.montevideo.gub.uy/notificacion/mensajes?idApp=1&fromIdMessage=N` | noticias oficiales del transporte (desvíos, cambios): hasta 10 mensajes con `id > N` **en orden de almacenamiento, no por id**; `count` es cuántos hay en total por encima de `N`; `N=0` son los más antiguos (2020). `fecha` en ms |
| `GET pci.montevideo.gub.uy/buses/control` | % de cobertura GPS por empresa `[{"empresa":"CUTCSA","valor":100}…]` |
| `geoserver.montevideo.gub.uy/geoserver/ows` WFS `imm:v_uptu_paradas` | 42 672 registros «parada × variante», EPSG:32721 (`srsName=EPSG:4326` para lat/lon) ✔︎ |
| `https://m.montevideo.gub.uy/comoir/parada?numero={id}` | deep link: abrir la parada en Cómo Ir (el servidor devuelve la SPA y el código procesa `numero`) |

Formato de `siguientesParada` (respuesta real, parada 3140):

```json
{"linea":"145","destino":"PLAZA ESPAÑA","minutos":5,"real":true,
 "coordinates":[-56.142532,-34.88331],"idEmpresa":50,"idBus":247,
 "horaDesc":"7:39","accesibilidad":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y LUCIANO ROMERO"}
```

WFS de paradas (la app lo usa en «Paradas cercanas» solo sin proxy: `NearbyStopsService.buildUri` en
`lib/services/nearby_stops_service.dart`; con proxy, las cercanas salen del catálogo en el teléfono, §2.5):

```
GET geoserver.montevideo.gub.uy/geoserver/ows?service=wfs&version=2.0.0&request=GetFeature
    &typename=imm:v_uptu_paradas&outputFormat=application/json&srsName=EPSG:4326
    &propertyName=cod_ubic_parada,desc_linea,calle,esquina,the_geom
    &bbox={minLon},{minLat},{maxLon},{maxLat},EPSG:4326
```

- Un registro = «parada × variante de línea»; agrupar por `cod_ubic_parada`, que es el mismo número
  que en `transporteRest` y en el deep link de Cómo Ir (574 → «SAN JOSE y ANDES», las mismas líneas que en `lineas/574`).
- BBOX con el sufijo `EPSG:4326`: el orden es **lon,lat**; con lat,lon devuelve 0 registros sin avisar.
  Las coordenadas de la respuesta vienen como `[lon, lat]`.
- Centro, radio de 400 m: ~1 070 registros / 39 paradas en el bbox, 287 KB de JSON, 8 KB con gzip (el servidor comprime).
- Fixture para los tests: `test/fixtures/wfs_paradas_18_de_julio.json` (respuesta en vivo del 2026-10-17).
- La app no manda la posición exacta: el centro del bbox es la posición redondeada a 3 decimales (unos 110 m) y
  el medio lado es 472 m (`boxHalfSideMeters`: los 400 m del radio más 72 m, la media diagonal de una celda de
  0,001°), así el bbox siempre contiene el círculo de 400 m alrededor de la posición real. Después filtra en el
  teléfono con la posición exacta.
- El proxy usa la misma capa entera, sin bbox ni token, como CSV para el índice de paradas (§2.5):
  `outputFormat=csv&propertyName=cod_ubic_parada,desc_linea,cod_variante` (`proxy/src/geoserver.js`). El
  2026-10-27: 2,57 MB, 4 972 paradas, 16 438 pares parada × línea y 42 672 pares parada × variante.

`real:false`: horario sin GPS (`coordinates:null`, `minutos` puede ser 945).
`idEmpresa`: 10 COETC, 20 COME, 50 CUTCSA, 70 UCOT. Parada inexistente → `500 "No existe…"`.

### 2.3 API oficial documentada

`https://api.montevideo.gub.uy/api/transportepublico` (Swagger: `/swagger/spec/publictransport.json`) ✔︎

- OAuth2 **client_credentials**, token: `https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/protocol/openid-connect/token`
  (manual `docs/manualdeconexion.pdf`; el `/token` corto del Swagger también responde); sin token → `403`.
  El token dura 300 s y no hay refresh token.
- Clave del dueño: la aplicación «MVD Transporte» en el portal, plan **Basico**. El secreto está solo en los
  secretos del Worker (`proxy/`), no en la aplicación ni en git.

**Verificado con solicitudes en vivo el 2026-10-19** ✔︎

- **El límite es de 14 solicitudes por minuto para toda la clave**, en una ventana fija que empieza en :00: la
  solicitud 15 → `429 Usage limit exceeded`, y `Retry-After` da los segundos que faltan para el minuto siguiente.
  Las solicitudes de token no cuentan. Ni el portal ni el manual dicen cuál es el límite. Por eso la aplicación
  no puede llamar a la API por su cuenta: la clave es una sola para todos los usuarios, así que hace falta un
  proxy con una instantánea compartida (`proxy/src/im_gateway.js`).

| Endpoint | Resultado |
|---|---|
| `GET /buses` | ✅ toda la flota con GPS: ~980 ómnibus, 36 KB con gzip / 380 KB, ~4 s. `company`, `busId`, `line`, `lineVariantId`, `location`, `timestamp` (con ~10 s de atraso), `speed`, `access`, `thermalConfort`, `emissions` |
| `GET /buses?lines=` / `?busstopId=` / `?company=`, `format=geojson` | ✅ el mismo formato, con filtro |
| `GET /buses/busstops` | ✅ 4 972 paradas: `busstopId`, `street1`, `street2`, `location` (4 no tienen `street2`) |
| `GET /buses/linevariants`, `/{lineVariantId}` | ✅ 2 148 variantes: `line`, `origin`, `destination`, `subline`, `special` |
| `GET /buses/gtfs/static/latest/version.txt`, `google_transit.zip` | ✅ versión `20261019`, archivo de 16,9 MB (`HEAD` → 403, solo `GET`) |
| `GET /buses/busstops/{id}/upcomingbuses?lines=` | ❌ siempre `[]`, aun cuando `transporteRest` muestra en el mismo minuto un ómnibus con GPS a 4 min; repetir `lines=` → 500. En el Swagger el esquema de la respuesta es `BusLineVariantItem`, aunque por el sentido debería ser `ETAItem` |
| `GET /buses/busstops/{id}/lines` | ❌ `400 Bad Request` para cualquier parada |
| `GET /buses/geo?center&radius` | ❌ `500` con cualquier formato de `center`; en el Swagger está marcado como `deprecated` |

- **La API oficial hoy no da ETA**: los tiempos de arribo siguen saliendo de `transporteRest` (§2.2).
- **Cruce con `transporteRest`**: `idEmpresa` (10 COETC, 20 COME, 50 CUTCSA, 70 UCOT) + `idBus` =
  `company` + `busId`. Los 18 ómnibus con GPS probados aparecieron en la instantánea de la flota. Así se
  agregan al ETA el aire acondicionado y «cero emisiones». `variante` = `lineVariantId` vale solo en parte:
  en las capturas del contrato el ómnibus 139 de CUTCSA está en la variante 628 en la flota de la IM
  (`im_buses.json`) y en la 630 en `transporteRest` (`arrivals_574.json`). Por eso el proxy cruza el confort
  solo por empresa y ómnibus, nunca por variante, y las variantes de la IM se usan solo para buscar el destino
  de una variante del WFS (§2.5).
- **El confort es una propiedad del vehículo**: en 842 ómnibus que aparecieron en dos instantáneas con 15 min
  de diferencia no cambió ni `thermalConfort`, ni `emissions`, ni `access`. En la instantánea de las 19:52:
  aire acondicionado en 409 de 979, «Cero emisiones» en 151, «PISO BAJO» en 441, «PLATAFORMA ELEVADORA» en 87.
  «Sin datos» no es «no»: la aplicación muestra solo un «sí» confirmado.
- **GTFS**: `trips.shape_id` = `lineVariantId`, `stops.stop_code` = el número de parada del STM (el de la URL de
  Cómo Ir), `shapes.txt` = la geometría de los recorridos, `stop_times.txt` = 88 MB descomprimido (no se puede
  procesar en el Worker; solo de antemano, con un script aparte). El feed vale un mes y se vuelve a publicar
  (`feed_end_date` 20261119).
- Otros servicios del portal (según el manual): «Playas» (banderas en las playas), «Eco» (de prueba).

### 2.4 Conjuntos de datos abiertos (catalogodatos.gub.uy, Licencia de Datos Abiertos – Uruguay)

- «Horarios de ómnibus urbanos por parada STM» — `datos-abiertos.montevideo.gub.uy/uptu_pasada_variante.zip`
- «Transporte colectivo: paradas, puntos de control y recorridos de ómnibus» — shapefiles
- «Viajes realizados en los ómnibus del STM» — actualizado el 2026-09-19

### 2.5 El proxy `/v1` (Backend-for-Frontend)

Con `--dart-define=MVD_PROXY_URL=…` la app le habla solo al Worker de Cloudflare de `proxy/`
(`proxy/src/index.js`): rutas fijas, solo `GET` y sin query string, y cada respuesta es JSON con la forma que
necesita una pantalla. Las formas, los errores y las reglas de derivación están en
[design/contrato-v1.md](design/contrato-v1.md); los casos y las respuestas esperadas, en `proxy/contract/v1/`, que
corren tanto las pruebas del proxy como las de la app. Sin desplegar todavía.

| Ruta | Fuentes | Caché en el borde | Unidades de la API oficial |
|---|---|---|---|
| `/v1/stops/{id}` | `transporteRest/lineas/{id}` (nombre y líneas) + `ImGateway` `/stops/{id}/meta` (destinos, del índice de paradas), esperado como mucho 2 s | 24 h; 5 min si los destinos fallaron, tardaron o están incompletos | 0 |
| `/v1/stops/{id}/arrivals` | `transporteRest/siguientesParada/{id}` + `ImGateway` `/vehicles` (confort por empresa y ómnibus, de la flota), esperado como mucho 2 s | 15 s | 0 por pedido (la flota, abajo) |
| `/v1/stops/{id}/schedule/{day}/{H:MM}` | `transporteRest/siguientesParada/{id}/{HABIL\|SABADO\|DOMINGO}/{H:MM}` | 6 h | 0 |
| `/v1/catalog/stops` | `ImGateway` `/catalog/stops`: `GET /buses/busstops` + las líneas del índice de paradas | 24 h; 15 min sin líneas (`linesAvailable:false`) | 1 (paradas), salvo que `ImGateway` tenga la copia en memoria |
| `/v1/news` | `notificacion/mensajes?idApp=1&fromIdMessage=N`, con el salto desde 0 de §6 (como mucho 8 pedidos) | 5 min | 0 |
| `/v1/status/gps` | `pci.montevideo.gub.uy/buses/control` | 1 min | 0 |

- `/v1/lines/{line}/buses` y `/v1/catalog/lines` ya no son rutas públicas (404 `not_found`): la app nunca las
  usó. `ImGateway` las conserva como rutas internas.
- Plazos de las fuentes: transporteRest 8 s, notificacion 5 s por página, pci 5 s, API oficial 10 s, geoserver
  20 s. Un error de una fuente nunca llega como lista vacía: es 502 `upstream_error` o 504 `upstream_timeout`.
- La caché del borde (Workers Caching) es la misma para todos: mil personas en la misma parada dan un pedido a
  `transporteRest` cada 15 s por centro de datos. Por eso no hay ruta batch: una URL por parada, y la app pide
  las paradas en paralelo.
- Límite por IP: 300 pedidos por minuto por ubicación de Cloudflare, contados solo cuando no hay caché
  (`IP_LIMITER` en `proxy/wrangler.jsonc`). Pasado el límite, 429 `rate_limited` con `Retry-After: 60`.

**Qué pide la app y cuándo** (build con proxy):

- «Mis paradas»: `MvdApiService.getBoards` pide `/arrivals` de cada parada una sola vez, todas en paralelo; cada
  30 s solo mientras «Mis paradas» está en pantalla (la pestaña elegida y ninguna página encima, `StopsPage.active`),
  y una vez al volver a ella o a la app. Una tarjeta de ruta usa el tablero de su parada de origen
  (`RouteAlert.accepts`) y no pide nada propio. Al abrir, las paradas guardadas sin conexión, que quedaron como
  «Parada N» sin líneas, piden `/v1/stops/{id}` una vez (`MvdApiService.healPlaceholderStops`).
- Segundo plano: `BackgroundWorker` (WorkManager, cada ≥15 min) hace un solo `getBoards` con las paradas de los
  avisos y los orígenes de las rutas dentro de su horario, más el origen de la ruta del widget. «Estoy
  esperando» en Android: `/arrivals` de esa parada cada 30 s.
- «Agregar parada» con un número escrito: `/v1/stops/{id}`. Una parada elegida del catálogo o de las cercanas se
  guarda sin pedir nada. «Agregar ruta»: `/v1/stops/{id}` y `/arrivals` en paralelo; `directions` da los chips
  HACIA y los arribos son el respaldo de una línea sin destinos conocidos.
- «Paradas cercanas» y «Buscar por calles»: `/v1/catalog/stops`, como mucho una vez por día (unos 660 KB, en la
  caja Hive `catalog`). Las cercanas (400 m) se calculan en el teléfono (`NearbyStopsService.nearbyFrom`):
  ninguna coordenada sale del dispositivo.
- «Horarios»: `/schedule/…`, con caché en memoria de 6 h.
- «Novedades»: `/v1/news` como mucho cada 10 min (cada 30 s con pull-to-refresh), mezclado en la caché Hive de
  30 novedades.
- «Datos GPS parciales»: `/v1/status/gps` como mucho una vez por minuto.
- Después de un 429 del proxy la app no pide nada hasta que pasa el `Retry-After` (`ApiFailure.busy`).

**Presupuesto de la API oficial** (`ImGateway`, `proxy/src/im_gateway.js`):

- 12 pedidos por minuto de los 14 de la clave (`BUDGET_PER_MINUTE`), con la ventana fija desde :00 como la de la
  IM; quedan 2 para que el dueño pruebe a mano con la misma clave. El contador se guarda en el almacenamiento
  del Durable Object. Los pedidos de token no cuentan.
- La flota (`GET /buses`) se considera fresca 15 s. Los arribos no la esperan: el confort ya conocido (de hasta
  24 h, guardado también en el almacenamiento, porque el objeto hiberna a los 10 s sin pedidos y pierde la
  memoria) se contesta en el momento, y una flota más vieja se recarga en segundo plano. Son unas 4 cargas por
  minuto como mucho, y solo mientras llegan pedidos de arribos.
- Las paradas (`GET /buses/busstops`) y las variantes (`GET /buses/linevariants`) duran 24 h, pero solo en
  memoria: una copia más vieja, de hasta 7 días, se sirve mientras se carga otra, y si esa carga falla se sigue
  sirviendo. Las paradas cuestan 1 unidad cada vez que el catálogo no está en la caché del borde y el objeto
  ya no tiene la copia en memoria; las variantes, 1 por armado del índice de paradas (abajo).
- Lo esperado en el peor minuto: 4 (flota) + 1 (paradas) + 1 (variantes) = 6 unidades, debajo de las 12.
- Sin presupuesto, o después de un 429 de la IM, el catálogo sin copia en memoria contesta 503 `upstream_busy`
  con `Retry-After`. Los arribos nunca fallan por eso: salen con el confort en `null`.
- geoserver no pasa por la clave: no usa token ni gasta presupuesto.

**Índice de paradas** (`ImGateway` y `proxy/src/geoserver.js`):

- Sale del CSV de la capa WFS entera (§2.2): las líneas (`desc_linea`) y las variantes (`cod_variante`) de cada
  parada. Con las variantes de la API oficial (1 unidad) arma `directions`: un elemento por línea y destino, con
  sus `variantIds`. Las variantes que la IM no conoce o que no tienen destino quedan afuera; las `special`,
  adentro.
- Se arma como mucho una vez por día, una sola vez aunque lleguen muchos pedidos juntos; se sirve hasta 7 días
  y, pasadas 24 h, se rearma en segundo plano. Si el armado falla, o si fallaron solo las variantes (el índice
  queda incompleto, sin `directions`), se reintenta a los 15 min.
- Se guarda en 64 partes (`stopmeta:{id % 64}`) más `stopmeta:info`: unas 65 escrituras por armado. Después de
  hibernar, los datos de una parada son como mucho dos lecturas del almacenamiento (`stopmeta:info` y la parte de
  esa parada), sin pedidos.
- En `/v1/stops/{id}`, `directions` se queda solo con las líneas que lista transporteRest. `/v1/catalog/stops`
  espera hasta 20 s el primer armado; si no hay índice, contesta `linesAvailable:false` con `lines: []` en cada
  parada, y el Worker lo guarda 15 min.
- Los ids de variante coinciden solo en parte entre fuentes: en la parada 574, 5 de las 6 variantes de
  transporteRest estaban en el WFS, y el cruce con la flota también falla (§2.3). Por eso una ruta guarda
  destinos y variantes (`preferredVariantIds`) y coincide por cualquiera de los dos.

**Modo directo** (sin `MVD_PROXY_URL`). La app pide transporteRest, notificacion, pci y el WFS (con la posición
redondeada, §2.2) y convierte las respuestas a JSON `/v1` en el teléfono (`DirectSource` y
`lib/services/api/direct/`), así las lee el mismo `V1Parser`. No hay confort, ni `directions`, ni catálogo, ni
búsqueda por calles. El modo se elige al compilar: no hay paso automático de uno al otro. Queda hasta que el
proxy esté desplegado.

**Privacidad y logs.** Una build con proxy no contacta ningún host de la ciudad ni manda coordenadas
(`test/proxy_privacy_test.dart`, `test/proxy_bff_test.dart`). Los logs de Workers están apagados: `wrangler.jsonc`
no tiene bloque `observability`. Lo que escribe el Worker son textos fijos `<fuente>: <tipo>`, sin la URL que
pidió la app, sin número de parada y sin IP; algunas líneas viejas de `ImGateway` todavía nombran el recurso de
la IM (`im-gateway /buses: HTTP 500`). Ningún encabezado de las fuentes llega al cliente. Detalle en
[proxy/README.md](../proxy/README.md).

---

## 3. Marco legal

**API oficial.** Condiciones del portal: el servicio «se ofrece de forma gratuita para el público
en general», requiere un registro gratuito, «un número razonable de consultas por segundo»,
dudas a `pci@imm.gub.uy`. Es el único canal con permiso explícito.

**`transporteRest` (se usa actualmente).** Técnicamente está abierto, pero es el backend interno de Cómo Ir
sin condiciones publicadas. Acceso técnico ≠ permiso; el endpoint puede desaparecer igual
que `stmonlineRest`. No es peor que la situación inicial (la aplicación ya consultaba endpoints no documentados),
pero a largo plazo es un riesgo.

**Licencia de Datos Abiertos – Uruguay v0.1** (Directrices técnicas AGESIC, aprobadas por el Decreto 54/017):
permite el uso comercial y no comercial, la transformación y la incorporación en aplicaciones.
La «Nota de Origen» es obligatoria y debe incluir: el proveedor, el enlace a la licencia, **el enlace al
conjunto de datos concreto** y **la mención de los cambios** ✔︎. Actualmente la aplicación no usa conjuntos de datos
abiertos, por eso en Info figura la fuente sin enlace a la licencia. Al incorporar GTFS o conjuntos de datos,
agregar la Nota de Origen completa.

**Políticas de las tiendas (principal riesgo para la publicación)** ✔︎
- Google Play, Spam: se prohíbe una app que sea «a webview of a website without
  permission from the website owner or administrator». 4 de las 5 pestañas son WebView de sitios de la IM.
- Google Play, Government/Misleading Claims: hace falta una aclaración explícita de no afiliación
  y un enlace a la fuente en la descripción de la tienda. La aclaración está en Info; **el ícono —un escudo con sol y
  franjas— se parece a los símbolos oficiales de Uruguay** → riesgo de rechazo.
- Apple 4.2 (Minimum Functionality, «repackaged website») y 5.2.2 (se requiere permiso
  para usar un servicio de terceros).

**Privacidad (Ley 18.331).** Se necesita una política de privacidad (obligatoria para las tiendas):
geolocalización (Cómo Ir), almacenamiento local del saldo, inicio de sesión en Mi STM. El inicio de sesión pasa por SAML SSO
`ih.montevideo.gub.uy` **dentro del WebView de la aplicación**, y la aplicación inyecta JS en las páginas: aunque
el código sea honesto, el usuario no puede verificarlo. La mejor práctica (RFC 8252) es usar
Custom Tabs / SFSafariViewController para el inicio de sesión. El widget muestra el saldo incluso con el
bloqueo biométrico activado.

---

## 4. Corregido en este cambio

| # | Gravedad | Dónde | Problema → corrección |
|---|---|---|---|
| 1 | P0 | `mvd_api_service.dart` | ETA: `nextETA` muerto → `siguientesParada`; un error de red ahora da `null` y no «no hay ómnibus» |
| 2 | P0 | `mvd_api_service.dart` | nombre de la parada: `variantes` muerto → `lineas`; `StopNotFoundException` |
| 3 | P0 | `background_worker.dart`, `stops_page.dart` | la tarea en segundo plano no se registraba al activar las alertas ni para las rutas → `BackgroundWorker.sync()` después de cada cambio |
| 4 | P0 | `stops_page.dart` | `Dismissible` eliminaba el elemento después de un `await` → eliminación sincrónica |
| 5 | P0 | `webview_page.dart` | biometría fail-open ante cualquier excepción (incluida `LockedOut`) → fail-closed; abrir solo si el dispositivo no tiene bloqueo |
| 6 | P0 | `test/` | los dos tests fallaban → plataforma WebView falsa, Hive en temp, 18 tests con fixtures reales |
| 7 | P1 | `background_worker.dart` | alerta «llegando» por horario → solo `isRealTime` |
| 8 | P1 | `background_worker.dart` | una excepción del widget (iOS sin App Group) silenciaba las notificaciones → try aparte ✔︎ |
| 9 | P1 | `webview_page.dart` | el WebView de Android por defecto deniega la geolocalización (`// default don't allow` en el plugin) → callback que pide el permiso, solo para dominios de la IM |
| 10 | P1 | `webview_page.dart` | bucle de bloqueo: la pantalla de PIN del sistema provoca pause/resume → protección `_isAuthenticating` + 2 s de gracia |
| 11 | P1 | `info_page.dart` | `StatelessWidget`: el interruptor no cambiaba → stateful, el callback devuelve el estado final |
| 12 | P1 | `MVDTransporteWidgetProvider.kt`, `webview_page.dart` | botones del widget: nadie leía `putExtra("tab")` → `HomeWidgetLaunchIntent` + URI `mvdtransporte://tab?index=N` ✔︎ |
| 13 | P1 | `comoir_scraper.dart` | `[class*="to"]` capturaba `toolbar`/`button`/`bottom`, `[data-id]`, cualquier cosa; se ejecutaba en cualquier URL con «comoir» → selectores acotados, verificación del host |
| 14 | P1 | `balance_scraper.dart` | se ejecutaba en cualquier URL con `principal.xhtml`; al widget podía llegar el texto del contenedor → verificación del host, extracción del monto |
| 15 | P1 | `AndroidManifest.xml` | `SCHEDULE_EXACT_ALARM` no se usa (restringido por Google Play), `usesCleartextTraffic="true"` → eliminado/`false` ✔︎ |
| 16 | P2 | `route_alert.dart` | las líneas se comparaban distinguiendo mayúsculas y minúsculas ✔︎ |
| 17 | P2 | widget | «5 min» queda desactualizado hasta 15 min → hora de arribo `~08:14`; la fila de la ruta se vacía si no hay datos |
| 18 | P2 | `webview_page.dart` | la navegación de la SPA no actualizaba «atrás» → `onUrlChange`; `setState` después de `dispose` → chequeos de `mounted` |
| 19 | P2 | `cache_service.dart` | doble registro de adaptadores de Hive (hot restart) → guard |
| 20 | P2 | `webview_page.dart` | geolocalización en cada inicio, notificaciones sin alertas → pedido en contexto |
| 21 | P2 | `info_page.dart` | enlace a un repositorio inexistente `mi_Transporte_MVD`; no figuraba la fuente de los datos |
| 22 | P0 | `ios/Podfile`, `project.pbxproj` | iOS no compilaba: `workmanager_apple` requiere 14.0, Xcode 27 ≥ 15.0 (algunos pods tenían 9.0/11.0) → target 15.0 + `post_install` |
| 23 | P1 | `webview_page.dart` | caída del proceso WebContent (`WKErrorWebContentProcessTerminated`, código 2) → `onPageFinished` no llega, «Cargando...» para siempre → 1 reinicio automático y después pantalla de error con «Reintentar»; encontrado en el simulador, el test lo reproduce |

---

## 5. Sin corregir — requiere una decisión del dueño

| Tema | Por qué no se tocó | Recomendación |
|---|---|---|
| `applicationId`/`namespace` = `com.example.stm_app`; el release está firmado con la clave de debug ✔︎ | Google Play no acepta `com.example`; cambiar el ID = una app nueva para las copias ya instaladas | elegir el ID (en iOS ya es `com.liberontech.stmapp`), crear un keystore |
| ~~Envoltorio WebView de los sitios de la IM (políticas de las tiendas)~~ | — | **resuelto:** navegador del sistema en lugar de WebView, ver §5.1 |
| ~~Ícono con símbolos oficiales~~ | **hecho** en `chore/store-compliance`: el anterior tenía el escudo de Montevideo (así lo dice `assets/README.md`) | — |
| ~~Inicio de sesión en Mi STM dentro del WebView + `BalanceScraper`~~ | — | **resuelto:** Custom Tabs/SFSafariViewController; se eliminaron el scraping y el saldo en el widget, §5.1 |
| ~~`ComoIrScraper` en la práctica no funciona~~ ✔︎ | — | **resuelto:** eliminado (en el navegador no se puede inyectar JS); en su lugar, el deep link «Ver en Cómo Ir», §5.1 |
| Política de privacidad en la aplicación | Google Play exige el enlace tanto en la consola como dentro de la aplicación | el texto está listo (`docs/privacy-policy.md`); publicarlo (GitHub Pages) y agregar el enlace en Info (`url_launcher` ya está) |
| Licencia del repositorio | el repositorio es público pero no tiene `LICENSE`: eso es «código visible», no open source | elegir una licencia (MIT/Apache-2.0/GPL) o dejar explícito «todos los derechos reservados» |
| Hive abierto a la vez en el isolate de la UI y en el de WorkManager ✔︎ (desde el proxy `/v1`, también la caja del catálogo `catalog`) | migración del almacenamiento | Hive 2.x no es multi-isolate → `hive_ce` con `IsolatedHive` o `shared_preferences` para los datos en segundo plano |
| iOS: segundo plano y widget sin configurar ✔︎ | hacen falta Xcode, App Group, BGTask | `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`, registro en AppDelegate, App Group para home_widget |
| WorkManager ≥ 15 min | limitación de Android | el umbral de alerta de 5 min muchas veces se saltea: ver «modo espera» en §6 |
| ~~Un solo `WebViewController` para 4 pestañas~~ ✔︎ | — | **resuelto:** no hay WebView, dos pestañas nativas en `IndexedStack`, §5.1 |
| Dependencias desactualizadas | actualizarlas rompe la API | `local_auth` 3.x eliminó `AuthenticationOptions` ✔︎, `workmanager` 0.10, `hive_flutter` abandonado; `geolocator` y `shared_preferences` no se usan |
| ~~UA «Android 10 / Chrome 120» también en iOS~~ ✔︎ | — | **resuelto:** no hay sustitución, el navegador envía su propio UA |
| Bloqueo biométrico después de pasar Mi STM al navegador | decisión de producto | ver §5.1 «Bloqueo biométrico» |
| Permisos de geolocalización en los manifiestos | los necesita la rama «Paradas cercanas» | en `feat/custom-tabs` nadie pide la geolocalización; si `claude/nearby-stops-comoir` no se fusiona, eliminar `ACCESS_*_LOCATION` y `NSLocation*` |
| Datos viejos de saldo en los dispositivos | inofensivo | Hive `cached_card_balance`, `last_detected_route`, `last_active_time` y `card_balance` en los datos del widget quedan después de actualizar; si se quiere, una limpieza única al iniciar |
| «colectivo» → «ómnibus» ✔︎ | textos | en Uruguay se dice «ómnibus» |
| `NSLocationAlwaysAndWhenInUseUsageDescription` ✔︎ | no hace falta | eliminar de Info.plist |

### 5.1 Resuelto: navegador del sistema en lugar de WebView (rama `feat/custom-tabs`)

**Qué se hizo.** La aplicación ya no tiene WebView integrado (`webview_flutter*` y
`permission_handler` se eliminaron de las dependencias).

| Antes | Ahora |
|---|---|
| Pestañas Inicio, Recarga, Cómo Ir, Avisos: WebView con inyección de JS | pestaña «Servicios» con mosaicos Mi STM, Recarga, Cómo Ir, Avisos; cada uno abre el sitio oficial en **Chrome Custom Tabs** (Android) / **SFSafariViewController** (iOS) |
| Pantalla principal: WebView de Mi STM | pantalla principal: «Mis paradas» nativa; navegación inferior con dos pestañas nativas (`IndexedStack`, se conserva el estado de las pestañas) |
| Cómo Ir: pestaña con WebView | mosaico + «Ver en Cómo Ir» en la ficha de la parada: deep link `/comoir/parada?numero=N` en el mismo navegador |
| `BalanceScraper` → saldo en el widget de Android | eliminado; en el widget quedan la fila del próximo ómnibus y los botones «Mi STM»/«Recarga», que abren el sitio en el navegador |
| `ComoIrScraper` → banner «Ruta detectada» en la pestaña «Rutas» | eliminado junto con el banner; la ruta se agrega con el botón «+» |
| Borrado de la caché del WebView tras 2 h de inactividad | eliminado (la sesión la maneja el navegador) |

**Por qué `url_launcher` y no `flutter_custom_tabs`.** `url_launcher` es un paquete del equipo de Flutter:
`LaunchMode.inAppBrowserView` = `CustomTabsIntent` en Android y `SFSafariViewController` en iOS;
con eso alcanza. `flutter_custom_tabs` ofrece color de la barra de herramientas, animaciones, partial tabs: no los necesitamos,
y es una dependencia de terceros de más. Un detalle de `url_launcher`: si en Android no hay un navegador con
Custom Tabs, abre en silencio **su propia activity con WebView**. Por eso `SystemBrowser.open`
primero verifica `supportsLaunchMode(inAppBrowserView)` y, si no, abre el navegador completo;
para que esa verificación funcione en Android 11+ se agregó al manifiesto `<queries>` con `CustomTabsService`.

**Qué pierde el usuario.**
- **El saldo de la tarjeta en el widget y en la aplicación.** En Custom Tabs/Safari no se puede ejecutar JS, y no hay una
  API abierta de saldo: el catálogo de `api.montevideo.gub.uy` solo tiene `transporte` y `playas`.
  Ahora el saldo está a un toque de «Mi STM» (en la aplicación o en el widget).
- **El inicio de sesión «dentro de la aplicación»**: Mi STM se abre sobre la aplicación en una ventana del navegador
  (en Android la sesión se comparte con Chrome: se inicia sesión una vez y después también queda abierta en Chrome).
- **El banner «Ruta detectada en Cómo Ir»**: de todos modos no funcionaba (SPA en Ionic).
- **La pestaña Cómo Ir** como parte de la aplicación: ahora es una ventana del navegador con el botón de cerrar del sistema (×).

**Qué gana el usuario.**
- Cumplimiento de la Spam policy de Google Play («webview of a website without permission») y menos
  riesgo con Apple 4.2: la aplicación ya no es un envoltorio de sitios de la IM; su núcleo son las paradas y alertas nativas.
- Las credenciales de ID Uruguay se ingresan en el navegador, que la aplicación no puede leer ni en el que puede
  inyectar código (RFC 8252); se ve la barra de direcciones real y funcionan los gestores de contraseñas y el autofill.
- La geolocalización para Cómo Ir la pide el navegador, no la aplicación, sin un callback hecho a mano
  (no verificado en un dispositivo).
- Menos código y dependencias: −2 scrapers, −plugins de WebView, −`permission_handler`.

**Bloqueo biométrico — se necesita una decisión.** Antes protegía el WebView con la sesión activa de Mi STM.
Ahora la sesión vive en el navegador (Chrome/Safari) y el bloqueo no la protege, así que solo protege
las paradas y rutas guardadas (a partir de ellas se puede deducir dónde vive y trabaja la persona).
Hecho: el texto en Info se corrigió a «Protege tus paradas y rutas guardadas»; volver del
navegador ya no vuelve a bloquear la aplicación (la Custom Tab es una activity aparte, y en iOS mostrar
SFSafariViewController también produce `inactive → hidden → paused`; solo se ignora la pausa
que empieza en los primeros 3 s después de abrir el navegador, y un test lo verifica). Opciones: (a) mantenerlo como protección de la privacidad de los datos guardados (estado actual);
(b) quitar el bloqueo, `local_auth` y `USE_BIOMETRIC`/`NSFaceIDUsageDescription`: más simple, menos
preguntas en la revisión de las tiendas. Recomendación: (a); viene desactivado por defecto y no cuesta nada.

**Verificado.** `flutter analyze`: limpio; `flutter test`: 20/20 (tests nuevos: dos pestañas nativas,
mosaicos, Mi STM → `inAppBrowserView`, sin Custom Tabs → `externalApplication`, error al abrir →
SnackBar, «Ver en Cómo Ir» → `/comoir/parada?numero=1234`, volver del navegador no bloquea, pero
el siguiente paso a segundo plano sí; el último test falla si se quita esa verificación). Simulador de iOS
(iPhone 17 Pro, iOS 26.2): la aplicación abre en «Mis paradas»; un toque real en «Servicios» →
«Mi STM» (integration test temporal, no está en el repositorio) abre SFSafariViewController con el dominio
`stm.gub.uy`; la aplicación pasa a `inactive` 18 ms después del toque y a `paused` a los 0,6 s.
El contenido de la página está vacío: en este simulador WebKit no renderiza páginas (ver §7).
`flutter build apk --debug`: compila (widget en Kotlin, `<queries>`).
**No verificado:** Android en vivo (Custom Tabs, botones del widget), porque el emulador no arranca; inicio de sesión en Mi STM
y saldo en un dispositivo real.

---

## 6. Propuestas (basadas en la API y las licencias)

1. **API oficial a través de un proxy propio.** Registrarse en `api.montevideo.gub.uy`,
   guardar el `client_secret` en un backend pequeño (Cloudflare Worker o similar) con caché del token
   y de las respuestas. Es el canal legal con condiciones explícitas y una protección contra roturas como la de `stmonlineRest`.
   🟡 Hecho, sin desplegar. Empezó en la rama `feat/official-api` y en `feat/timbre-bff` pasó a ser el
   Backend-for-Frontend `/v1` (§2.5): la app pide todo al proxy —arribos, paradas con sus destinos, horarios,
   catálogo, novedades y estado del GPS— y el proxy decide de qué fuente sale cada dato. El Durable Object
   `ImGateway` guarda el token, el presupuesto de 12 de las 14 solicitudes por minuto, una instantánea
   compartida de la flota cada ≥15 s y el índice de paradas. El ETA sigue saliendo de `transporteRest`
   (`upcomingbuses` está vacío, §2.3); se le agregan el aire acondicionado y «cero emisiones». El catálogo de
   paradas `/v1/catalog/stops` es la base del punto 2. `/v1/lines/{line}/buses` y `/v1/catalog/lines` ya no son
   rutas públicas, porque la app no las usaba; el Durable Object las conserva para uso interno (base posible del
   punto 9). La aplicación usa el proxy si se compila con `--dart-define=MVD_PROXY_URL=…`.
   Orden de despliegue: primero el proxy y `node scripts/smoke.js <url>` contra el Worker desplegado; recién
   después las builds con `MVD_PROXY_URL`. La prueba de humo es lo que muestra si un F5/BigIP delante de
   geoserver, notificacion o pci bloquea las IP de Cloudflare: en ese caso las novedades y el GPS dan 502, el
   catálogo sale sin líneas y las paradas sin `directions`.
2. **Búsqueda de paradas sin el número.** WFS `imm:v_uptu_paradas` (`srsName=EPSG:4326`) o
   `/buses/busstops` → «paradas cercanas» por geolocalización y búsqueda por calle.
   ✅ «Paradas cercanas» está hecho: con proxy se calcula en el teléfono con el catálogo `/v1/catalog/stops`, sin
   mandar coordenadas (§2.5); sin proxy, con el WFS y la posición redondeada (§2.2). 🟡 La búsqueda por calles
   («Buscar por calles») usa el mismo catálogo, solo en la build con proxy.
3. **«Ver en Cómo Ir»** en la ficha de la parada — deep link `/comoir/parada?numero={id}`:
   integración oficial sin scraping. ✅ Hecho.
4. ✅ **Noticias del transporte.** `notificacion/mensajes`: los desvíos y cambios de líneas que
   publica la propia IM, en una lista nativa.
5. ✅ **Indicador de calidad de los datos.** `pci.../buses/control`: «datos GPS de CUTCSA ahora al 40%»,
   para que el usuario entienda por qué el ETA no es preciso.
6. ✅ **Accesibilidad.** Los campos `accesibilidad`/`tipoAccesibilidad` (y `access` en la API oficial):
   ícono de ómnibus de piso bajo.
7. **Horarios sin conexión.** GTFS (`google_transit.zip`) o el conjunto «Horarios por parada»:
   funciona sin red. Requiere la Nota de Origen (§3).
8. ✅ **Modo espera.** Mientras el usuario espera el ómnibus, consulta cada 20–30 s con una
   notificación persistente (servicio en primer plano, tipo `shortService`/`dataSync` según las reglas de Play)
   en lugar del WorkManager de 15 minutos. Hecho como «Estoy esperando»: se toca una pasada; Android:
   `flutter_foreground_task`, tipo `dataSync` (`shortService` está limitado a ~3 min), consulta cada 30 s;
   iOS: un recordatorio para la hora prevista, que se reprograma con cada actualización dentro de la aplicación.
   Hace falta la declaración del tipo y un video en Play Console (`docs/store-listing.md`).
9. **Mapa del ómnibus.** Con `real:true` vienen `coordinates`: mostrar dónde está el ómnibus ahora.
   Los arribos de `/v1` no llevan esa posición (se sacó `location` de las formas: el diseño no usa mapas); haría
   falta agregarla al contrato como campo nuevo.

**Hecho en la rama `feat/open-data-features` (4, 5, 6 y horarios por tipo de día):**
pestaña «Novedades» en «Mis paradas» (badge de no leídas, texto HTML sin WebView/JS, el enlace se abre
en el navegador del sistema), ♿ en el chip de la pasada, pantalla «Horarios» en la ficha de la parada
(Hábiles/Sábados/Domingos + hora), advertencia «Datos GPS parciales» cuando `valor < 70`.
Solo en primer plano, sin consultas en segundo plano: noticias como mucho una vez cada 10 min (caché en Hive),
estado del GPS una vez por minuto, horarios con caché de 6 h. Hallazgo: paginar `notificacion/mensajes`
por el id máximo (como hace Cómo Ir) pierde mensajes: el 17/10/2026, después del id 148 llegó una página
que incluía el 171, y los 161…170 no se mostraban; la aplicación sube `fromIdMessage` según `count` hasta que lo restante
entre en una sola página (desde cero, 4 solicitudes; después, 1). Con el proxy, ese salto lo hace
`proxy/src/notificacion.js` (`fetchNewest`) desde 0 cada vez que arma la respuesta, como mucho 8 solicitudes, y
la app hace un solo pedido a `/v1/news`, que se guarda 5 min en la caché del borde. Verificado: tests con
respuestas en vivo guardadas (`test/fixtures/`), simulador de iOS con la API en vivo (noticias, detalle, «Ver más» → Safari,
horarios y cambio de día, ♿ en la parada 4018; el banner de GPS, con un estado simulado: ahora
todas las empresas están al 100 %).

---

## 7. Cómo se verificó

- `flutter analyze`: sin observaciones; `flutter test`: 20/20 (el test de la caída de WebContent
  falla sin la corrección n.º 23 y pasa con ella).
- Se llamó al nuevo `MvdApiService` contra la API en vivo: parada 3140 → «AV RAMON ANADOR y
  TIBURCIO GOMEZ», 3 pasadas (1 por GPS, 2 por horario), id 999999 → `StopNotFoundException`.
- `flutter build apk --debug`: compila (el widget en Kotlin y el manifiesto compilan).
- **Simulador de iOS** (iPhone 17 Pro Max, iOS 26.2, Xcode 27.1), verificado en vivo:
  agregar la parada 3140 — nombre real, la pasada por GPS resaltada, las pasadas por horario
  con la hora; la inexistente 31409 — «No existe la parada»; campanita — el sistema pide permiso de
  notificaciones al activarla, `BackgroundWorker.sync()` sin errores; Info — texto y enlace nuevos;
  activar el bloqueo — el sistema pide el código (no se ingresó); los datos sobreviven
  al reinicio; `HomeWidget` sin App Group en iOS — el error se captura y la aplicación funciona.
- Observación: el inicio de sesión de Mi STM es la cadena `stm.gub.uy` → `ih.montevideo.gub.uy/samlsso` →
  `auth.iduruguay.gub.uy` → `mi.iduruguay.gub.uy/login`, es decir, **ID Uruguay** dentro del WebView integrado.
- **No se pudo verificar:** las páginas del WebView, porque en este simulador el proceso de WebKit se cae
  en todas las apps, Safari incluido (problema del entorno, no de la aplicación); el emulador de Android no arranca
  (imagen `android-36.1` incompleta). Manualmente en un dispositivo: geolocalización en Cómo Ir, botones
  del widget, biometría, alertas en segundo plano.
- Toolchain: Flutter 3.41.1 + Xcode 27 — `flutter build ios --simulator` falla
  (`lipo -verify_arch` en Xcode 27 acepta una sola arquitectura y Flutter le pasa dos);
  `flutter run -d <simulador>` funciona. Actualizar Flutter.

## Fuentes

- [Montevideo API — catálogo](https://api.montevideo.gub.uy/docs), [documentación de transporte público](https://api.montevideo.gub.uy/apidocs/publictransport), [manual de conexión](https://api.montevideo.gub.uy/docs/manualdeconexion.pdf)
- [Cómo Ir (web)](https://m.montevideo.gub.uy/comoir/)
- [Catálogo Nacional de Datos Abiertos](https://catalogodatos.gub.uy/), [términos](https://catalogodatos.gub.uy/terminos-catalogodatos.pdf)
- [Decreto 54/017 (IMPO)](https://impo.com.uy/bases/decretos/54-2017), [Normativa de Datos Abiertos, AGESIC](https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/2020-09/Normativa%20de%20Datos%20Abiertos.pdf) — §4.4, texto de la licencia v0.1
- [Google Play — Spam and Minimum Functionality](https://support.google.com/googleplay/android-developer/answer/9899034), [Misleading Claims](https://support.google.com/googleplay/android-developer/answer/9888077)
- [App Store Review Guidelines 4.2, 5.2](https://developer.apple.com/app-store/review/guidelines/)
