# Contrato /v1

Qué le contesta el proxy a la app y cómo lo lee la app. Este es el texto
para leer. El contrato en forma de datos (goldens, capturas, vectores y casos)
está en [`proxy/contract/v1/`](../../proxy/contract/v1/README.md), que explica
la mecánica de las pruebas.

**El código manda.** Los valores de este documento salen de `proxy/src/*.js`,
`lib/services/api/*.dart` y `proxy/contract/v1/*`. Si este texto y el código
no dicen lo mismo, vale el código: corregí este texto.

Ver también:
- [pantalla-a-datos.md](pantalla-a-datos.md): qué campo muestra cada componente;
- [13-en-el-codigo.md](13-en-el-codigo.md): el mapa de archivos;
- [07-textos.md](07-textos.md): los textos de error en pantalla;
- [README.md](README.md): el índice de esta guía.

## Índice

1. [Arquitectura](#1-arquitectura)
2. [Modo directo y máscaras](#2-modo-directo-y-máscaras)
3. [Reglas generales](#3-reglas-generales)
4. [Rutas y formas](#4-rutas-y-formas)
5. [Reglas de derivación](#5-reglas-de-derivación)
6. [Caché y presupuesto de la API oficial](#6-caché-y-presupuesto-de-la-api-oficial)
7. [Errores](#7-errores)
8. [Privacidad y logs](#8-privacidad-y-logs)
9. [Evolución](#9-evolución)
10. [Para cambiar el contrato](#10-para-cambiar-el-contrato)
11. [El triángulo de pruebas](#11-el-triángulo-de-pruebas)
12. [Orden de despliegue](#12-orden-de-despliegue)
13. [Pendientes conocidos](#13-pendientes-conocidos)

## 1. Arquitectura

La app tiene una sola dirección de backend: el proxy, un Worker de Cloudflare
(`proxy/`). La app solo conoce las rutas `/v1`, y de dónde sale cada dato lo
decide el proxy. Si una fuente de la Intendencia cambia o se cae, se arregla
el proxy y no hace falta sacar otra versión en las tiendas.

```
pantallas (lib/ui)
  │
  ▼
MvdApiService, TransportNewsService, BusStatusService, NearbyStopsService   (lib/services)
  │
  ▼
V1Source ──▶ JSON /v1 ──▶ V1Parser ──▶ modelos (lib/models)
  │
  ├── ProxySource            con MVD_PROXY_URL
  │     │ GET /v1/…
  │     ▼
  │   Worker  proxy/src/index.js         caché de borde, límite por IP
  │     ├──▶ transporteRest              arribos, nombre y líneas, horarios
  │     ├──▶ notificacion                novedades
  │     ├──▶ pci                         estado GPS por empresa
  │     └──▶ ImGateway                   Durable Object, una sola instancia
  │            ├──▶ API oficial IM        flota (confort), paradas, variantes   OAuth2, presupuesto
  │            └──▶ geoserver WFS         líneas y variantes de cada parada     CSV diario, sin clave
  │
  └── DirectSource           sin MVD_PROXY_URL
        ├──▶ transporteRest              adaptadores de lib/services/api/direct/
        ├──▶ notificacion
        └──▶ pci
      además, solo en modo directo:
        NearbyStopsService   ──▶ geoserver WFS   caja alrededor de la posición redondeada
        TransportNewsService ──▶ notificacion    paginado desde el último inicio guardado
```

### En el proxy

- `proxy/src/index.js`: el Worker. Aplica el límite por IP, valida el pedido,
  llama a las fuentes y arma la respuesta /v1 con su `Cache-Control`.
  `respond()` convierte cualquier error en una respuesta JSON.
- `proxy/src/im_gateway.js`: `ImGateway`, el Durable Object. Hay una sola
  instancia para todo el proxy (`idFromName('global')`), venga de donde venga
  el pedido. Es el único que llama a la API oficial de la IM, porque la clave
  es una sola para todos los usuarios. También arma el índice de paradas con
  el CSV de geoserver. Sus rutas son internas: el Worker las llama con
  `https://im-gateway/…`, la app nunca.
- Un cliente por fuente, cada uno con su lectura a la forma /v1:
  `transporte_rest.js`, `notificacion.js`, `pci.js`, `geoserver.js` e
  `im_api.js`.
- `proxy/src/rules.js`: las reglas de derivación (sección 5).
- `proxy/src/errors.js` (`UpstreamError`, `StopNotFoundError`) y
  `proxy/src/http.js` (`fetchUpstream`: un User-Agent, un tiempo máximo y
  errores con textos fijos).

### En la app

- `lib/services/mvd_api_service.dart`: `MvdApiService`, la fachada. En cada
  llamada decide de dónde sale el JSON: con `--dart-define=MVD_PROXY_URL=…`
  usa `ProxySource`; sin eso, `DirectSource`. No hay cambio en tiempo de
  ejecución: una versión con proxy nunca llama a la Intendencia, aunque el
  proxy falle.
- `lib/services/api/v1_source.dart`: la interfaz `V1Source`, con un método
  por ruta. Cada uno devuelve el JSON /v1, o un `ApiFailure` con su
  `retryAfter`.
- `lib/services/api/proxy_source.dart`: `ProxySource`. Pide `/v1/…` al proxy
  (le saca la `/` final a la URL configurada) y traduce el status y el
  `{"error": …}` a `ApiFailure`.
- `lib/services/api/direct_source.dart` y `lib/services/api/direct/*`:
  `DirectSource` y sus adaptadores. Llaman a la Intendencia desde el teléfono
  y convierten la respuesta en el mismo JSON /v1 (sección 2).
- `lib/services/api/v1_parser.dart`: `V1Parser`, el único lector de cada
  forma, venga el JSON del proxy o de un adaptador.
- `lib/services/api/contract_rules.dart`: `ContractRules`, el espejo en Dart
  de `rules.js`.
- `lib/services/api/api_result.dart`: `ApiResult` (`ApiOk` o `ApiError`) y
  `ApiFailure`.

La fachada ofrece `getBoard`, `getBoards` (cada parada una vez, todas en
paralelo, y una parada que ya se está pidiendo comparte ese pedido),
`getStopDetails`, `getSchedule`, `getStopCatalog`, `getNews`,
`getGpsStatus`, `healPlaceholderStops`, `isValidStopId` y
`montevideoClock`. Quedan dos envoltorios viejos: `getNextArrivals`, que
todavía usa `bus_wait_task.dart`, y `resolveStop`, que ya solo usan las
pruebas.

### Fuentes

| Fuente | Dirección | Qué da | Credencial | Quién la llama | Tiempo máximo |
|---|---|---|---|---|---|
| transporteRest | `api.montevideo.gub.uy/transporteRest`: `lineas/{id}`, `siguientesParada/{id}`, `siguientesParada/{id}/{HABIL\|SABADO\|DOMINGO}/{H:MM}` | nombre y líneas de la parada, próximos ómnibus, horario teórico | ninguna | Worker (`transporte_rest.js`); app en modo directo (`TransporteRestAdapter`) | 8 s en el Worker, 10 s en la app |
| notificacion | `api.montevideo.gub.uy/notificacion/mensajes?idApp=1&fromIdMessage=N` | novedades de Cómo Ir | ninguna | Worker (`notificacion.js`); app en modo directo | 5 s por página en el Worker, 10 s en la app |
| pci | `pci.montevideo.gub.uy/buses/control` | qué parte de los ómnibus de cada empresa manda GPS | ninguna | Worker (`pci.js`); app en modo directo (`PciAdapter`) | 5 s en el Worker, 10 s en la app |
| API oficial IM | `api.montevideo.gub.uy/api/transportepublico`: `/buses`, `/buses/busstops`, `/buses/linevariants`; token en `mvdapi-auth.montevideo.gub.uy` | flota con confort, catálogo de paradas, variantes de línea | OAuth2 (`IM_CLIENT_ID`, `IM_CLIENT_SECRET`) | solo `ImGateway` (`im_api.js`) | 10 s |
| geoserver WFS | `geoserver.montevideo.gub.uy/geoserver/ows`, capa `imm:v_uptu_paradas` | proxy: CSV de toda la capa (`cod_ubic_parada,desc_linea,cod_variante`); app en modo directo: GeoJSON de una caja | ninguna | `ImGateway` (`geoserver.js`), una vez por día (a los 15 min si el armado falló); app en modo directo (`NearbyStopsService`) | 20 s en el DO, 15 s en la app |

La API oficial hoy no da tiempos de arribo (`upcomingbuses` viene vacío): por
eso los arribos salen de transporteRest y la API oficial solo agrega el
confort ([docs/REVIEW.md](../REVIEW.md) §2.3).

## 2. Modo directo y máscaras

Sin `MVD_PROXY_URL` la app llama sola a los servicios abiertos de la
Intendencia. Este modo queda hasta que el proxy esté desplegado. Cada
adaptador convierte la respuesta de la fuente en JSON /v1, y `V1Parser` la lee
igual que si viniera del proxy.

| Forma | Fuente y adaptador | Máscara frente al golden |
|---|---|---|
| parada | `transporteRest/lineas/{id}` → `TransporteRestAdapter.stopToV1` | `directions` |
| arribos | `transporteRest/siguientesParada/{id}` → `TransporteRestAdapter.arrivalsToV1` (`fetchedAt` = cuando llegó la respuesta) | `arrivals[].airConditioning`, `arrivals[].zeroEmission` |
| horario | `transporteRest/siguientesParada/{id}/{HABIL\|SABADO\|DOMINGO}/{H:MM}` → `TransporteRestAdapter.scheduleToV1` | ninguna |
| catálogo | ninguna: `DirectSource.catalogStops()` contesta `ApiFailure.unavailable` | – |
| cercanas | caja WFS (sección 8) → `WfsAdapter.featuresToCatalogItems` → los elementos del catálogo | – |
| novedades | paginado por saltos sobre `notificacion/mensajes` → `NewsAdapter.messagesToV1` | ninguna en un arranque en frío |
| GPS | `pci/buses/control` → `PciAdapter.controlToV1` (`[]` o ningún elemento válido → falla) | ninguna |

Qué cambia para la persona que usa una versión sin proxy:

- Las filas no muestran aire acondicionado ni cero emisiones.
- «Agregar ruta» arma los destinos (HACIA) con los próximos ómnibus de la
  parada, porque `directions` viene vacío.
- El campo «Buscar por calles» no aparece (`_AddStopDialog` lo muestra solo
  con `MvdApiService.usesProxy`).
- «Paradas cercanas» pide a geoserver una caja alrededor de la posición
  redondeada (sección 8).
- Novedades pagina desde el último inicio guardado (`news_from_id`), con su
  propio pedido (`TransportNewsService._fetchPage`). `DirectSource.news()`
  empieza siempre en 0: es lo que comparan las pruebas del contrato con el
  proxy, y da la misma lista que el proxy en un arranque en frío.

### Máscaras

`proxy/contract/v1/direct_masks.json` lista las únicas máscaras permitidas:

```json
["arrivals[].airConditioning", "arrivals[].zeroEmission", "directions"]
```

- `arrivals[].airConditioning` y `arrivals[].zeroEmission`: el confort sale de
  la flota de la API oficial, que necesita la clave. En modo directo van
  siempre en `null`.
- `directions`: los destinos por parada salen del índice de paradas de
  `ImGateway` (WFS cruzado con las variantes de la API oficial). En modo
  directo van siempre en `[]`.

Cómo se aplica una máscara: `arrivals[].campo` pone ese campo en `null` en
cada elemento de `arrivals`; `campo` lo pone en `[]` si en el golden es una
lista, y en `null` si no. Las dos suites verifican que las máscaras de cada
caso estén en esa lista. Una máscara nueva va en ese archivo y su motivo, en
esta sección.

## 3. Reglas generales

- **Solo `GET`.** Otro método da `405 method_not_allowed` con `Allow: GET`.
- **Sin query string.** Un pedido con `?…` da `400 bad_request`. Así cada URL
  es una sola clave de caché.
- **El límite por IP va primero**, antes de mirar la ruta: `429 rate_limited`
  con `Retry-After: 60`. Solo cuenta los pedidos que no están en la caché de
  borde (sección 6).
- **Todo es JSON** con `Content-Type: application/json; charset=utf-8`.
- **Los errores son `{"error":"<código>"}`** con `Cache-Control: no-store`.
  La única excepción es `stop_not_found`, que se guarda 3600 s.
- **No hay campos opcionales.** Cada campo de una forma viene siempre, aunque
  sea `null`. El productor es estricto: el cuerpo tiene que ser igual al
  golden, salvo `fetchedAt`.
- **El lector es tolerante** (`V1Parser`):
  - ignora las claves que no conoce;
  - un `fetchedAt` que falta o no se puede leer pasa a ser «ahora»;
  - `directions` y `lines` que faltan pasan a `[]`, y `linesAvailable` a
    `false`;
  - un elemento al que le falta un campo obligatorio se saltea;
  - un cuerpo con la forma de arriba equivocada es una falla (`failed`), nunca
    una lista vacía.
- **Un error de una fuente nunca se devuelve como una lista vacía.** Por eso
  pci con `[]` da 502 y un índice de paradas vacío cuenta como falla.
- **`fetchedAt`** es una hora ISO en UTC con milisegundos
  (`2026-10-19T22:52:10.000Z`). Qué hora es depende de la ruta:
  - arribos: cuando contestó transporteRest (en el Worker, o en el teléfono en
    modo directo). Desde la caché de borde puede tener hasta 15 s más;
  - novedades y GPS: el reloj del Worker al armar la respuesta;
  - catálogo: cuando `ImGateway` cargó las paradas de la API oficial. Esa
    copia vive solo en la memoria del objeto: se renueva al día, o antes si
    el objeto se durmió, y si la API falla se sirve hasta con 7 días.

  Las dos suites sacan `fetchedAt` de los dos cuerpos antes de comparar, y
  aparte verifican el formato `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`.
- **Ningún encabezado de las fuentes llega a la app.** El Worker arma cada
  respuesta con sus propios encabezados.

## 4. Rutas y formas

`ROUTES` en `proxy/src/index.js`:

| Ruta | Cuerpo 200 | Quién la usa en la app | `Cache-Control` en 200 | Errores propios |
|---|---|---|---|---|
| `GET /v1/stops/{id}` | `StopResponse` | «Agregar parada» con un número escrito, «Agregar ruta», `healPlaceholderStops` | `public, max-age=86400`; `public, max-age=300` si la metadata de `ImGateway` falló, tardó más de 2 s o está incompleta | 404 `stop_not_found` (3600 s), 404 `not_found`, 502, 504 |
| `GET /v1/stops/{id}/arrivals` | `ArrivalsResponse` | tarjetas de Mis paradas y Rutas, «Estoy esperando», avisos de fondo, widget, HACIA de respaldo en «Agregar ruta» | `public, max-age=15` | 404 `stop_not_found` (3600 s), 404 `not_found`, 502, 504 |
| `GET /v1/stops/{id}/schedule/{day}/{H:MM}` | `ScheduleResponse` | Horarios | `public, max-age=21600` | 400 `bad_request`, 404 `not_found`, 404 `stop_not_found`, 502, 504 |
| `GET /v1/catalog/stops` | `CatalogStopsResponse` | «Buscar por calles», «Paradas cercanas» | `public, max-age=86400`; `public, max-age=900` con `linesAvailable: false` | 503 `not_configured`, 503 `upstream_busy` con `Retry-After`, 502, 504 |
| `GET /v1/news` | `NewsResponse` | Novedades | `public, max-age=300` | 502, 504 |
| `GET /v1/status/gps` | `GpsStatusResponse` | aviso «Datos GPS parciales» | `public, max-age=60` | 502 (también con `[]`, algo que no es lista o ningún elemento válido), 504 |
| cualquiera | – | – | – | 400 `bad_request` (query string), 405, 429, 404 `not_found`, 500 `internal_error` |

Parámetros:

- `{id}`: `[1-9]\d{0,6}`, de 1 a 9 999 999 y sin ceros adelante, así cada
  parada es una sola clave de caché. `0`, `0574` o `10000000` no coinciden con
  ninguna ruta: 404 `not_found`.
- `{day}`: `weekday`, `saturday` o `sunday`. Otro día da 400 `bad_request`.
- `{H:MM}`: `(0|[1-9]\d?):([0-5]\d)`, la hora sin cero adelante y los minutos
  con dos cifras: `8:05`. `08:05`, `8:5` y `8:60` no coinciden: 404
  `not_found`. Una hora mayor que 23 (`24:00`) da 400 `bad_request`.

`/v1/lines/{line}/buses` y `/v1/catalog/lines` ya no son públicas: dan 404
`not_found`. La app nunca las usó. `ImGateway` las mantiene como rutas
internas.

### StopResponse

Para «Agregar parada» y «Agregar ruta». Golden `responses/stop_574.json`:

```json
{
  "id": 574,
  "name": "SAN JOSE y ANDES",
  "lines": ["116", "117", "121", "141", "142", "144", "538"],
  "directions": [{"line": "116", "destination": "POCITOS", "variantIds": [630]}]
}
```

`responses/stop_574_degraded.json` es la misma parada con `"directions": []`
(la metadata contestó 503), servida con `max-age=300`.

| Campo | Tipo | Regla |
|---|---|---|
| `id` | entero | el `{id}` del pedido. `V1Parser` usa el id pedido, no el del cuerpo. |
| `name` | texto o `null` | `descripcion` de transporteRest recortado con `trimText`; `null` si queda vacío. Solo Dart pone «Parada N» (`StopDetails.displayName`). |
| `lines` | lista de textos | `lineas[].descripcion`, sin recortar, sin vacíos ni repetidos, ordenadas con `compareLines`. |
| `directions` | lista | Pares distintos de línea y destino con sus variantes, del índice de paradas de `ImGateway` (sección 6). |

Cómo se arma `directions`:

- `ImGateway` cruza los `cod_variante` del WFS de esa parada con
  `linevariants` de la API oficial (`lineVariantId` → `line`, `destination`).
- Se descartan las variantes que la API oficial no conoce y las que no tienen
  destino. Las `special` quedan.
- `variantIds` va en orden ascendente. La lista se ordena por `compareLines`
  de la línea y después por destino, en orden de unidades de código
  (`compareDirections` en `im_gateway.js`).
- El Worker deja solo los pares cuya línea está en `lines`.
- `[]` quiere decir «no se sabe» o «ninguna»: la app arma HACIA con los
  arribos. En modo directo es siempre `[]`. Sin el binding `IM_GATEWAY` el
  Worker contesta `[]` con los 86 400 s normales, porque no hay nada que
  esperar.

`variantIds` son códigos de variante de la Intendencia: `cod_variante` del WFS,
el mismo número que `lineVariantId` de la API oficial. `RouteAlert` los guarda
en `preferredVariantIds` y los compara con `variantId` de los arribos
(`variante` de transporteRest), que usa la misma numeración. No siempre
coinciden: en las capturas, el ómnibus 139 figura en la variante 628 en la
flota de la API oficial y en la 630 en transporteRest. Por eso una ruta acepta
un ómnibus por variante **o** por destino (`RouteAlert.accepts`), y los
arribos nunca se cruzan con la flota por variante: el confort se cruza por
empresa y número de ómnibus.

### ArrivalsResponse

Para las tarjetas, «Estoy esperando», los avisos de fondo y el widget. Golden
`responses/arrivals_574.json`, recortado a 2 de sus 6 elementos:

```json
{
  "id": 574,
  "fetchedAt": "2026-10-19T22:52:10.000Z",
  "arrivals": [
    {
      "tripId": "bus-50-111",
      "variantId": 2779,
      "line": "117",
      "destination": "PUNTA CARRETAS",
      "state": "live",
      "etaMinutes": 4,
      "expectedAt": "2026-10-19T22:56:00.000Z",
      "clockTime": "19:56",
      "accessible": true,
      "airConditioning": true,
      "zeroEmission": false
    },
    {
      "tripId": "sched-883-2001",
      "variantId": 883,
      "line": "144",
      "destination": "CEMENTERIO DEL NORTE",
      "state": "scheduled",
      "etaMinutes": 9,
      "expectedAt": "2026-10-19T23:01:00.000Z",
      "clockTime": "20:01",
      "accessible": false,
      "airConditioning": null,
      "zeroEmission": null
    }
  ]
}
```

La fila cruda de transporteRest del primer elemento
(`upstream/transporte_rest/arrivals_574.json`), sin los campos que la regla no
lee (`coordinates`, `parada_actual`, `tipoAccesibilidad`, `dia_anterior`):

```json
{"time": 1792450560000, "destino": "PUNTA CARRETAS", "linea": "117", "accesibilidad": true,
 "hora": 1956, "variante": 2779, "minutos": 4, "real": true, "idBus": 111, "idEmpresa": 50,
 "horaDesc": "19:56"}
```

| Campo | Tipo | Regla (detalle en la regla `arrival`, sección 5) |
|---|---|---|
| `id` | entero | el `{id}` del pedido |
| `fetchedAt` | ISO | cuando contestó transporteRest |
| `tripId` | texto | `bus-{idEmpresa}-{idBus}` para un ómnibus con GPS; si no, `sched-{variante ?? 0}-{hora ?? dígitos de clockTime}` |
| `variantId` | entero o `null` | `toIntLoose(variante)` |
| `line` | texto | `linea` |
| `destination` | texto | `destino` tal cual, sin recortar (`null` pasa a `""`) |
| `state` | `arriving`, `live` o `scheduled` | `real === true` y `minutos <= 0` → `arriving`; `real === true` → `live`; si no, `scheduled` |
| `etaMinutes` | entero ≥ 0 | `max(0, minutos)` |
| `expectedAt` | ISO | `time` (ms) si es un número; si no, `fetchedAt + etaMinutes`, redondeado hacia abajo al minuto |
| `clockTime` | texto `H:MM` | `horaDesc` recortado y sin el cero de la hora; si está vacío, `expectedAt` en hora de Montevideo |
| `accessible` | booleano | `accesibilidad === true` |
| `airConditioning` | `true` o `null` | flota de la API oficial: `thermalConfort` igual a `"Aire Acondicionado"`. La API no distingue «sin aire» de «sin datos», así que nunca viene `false`. |
| `zeroEmission` | booleano o `null` | flota de la API oficial: `"Cero emisiones"` → `true`; otro valor que no sea vacío ni `"Sin datos"` → `false`; si no, `null` |

- Se descarta la fila sin `linea` o cuyo `minutos` no es entero.
- También se descarta la fila cuya hora esperada (`time`, o `fetchedAt` más
  los minutos) cae fuera de `±8.64e15` ms, lo más lejos que llegan un `Date`
  de JS y un `DateTime` de Dart. Es una fila menos, no un error para toda la
  parada (ni un 500 del proxy ni un `failed` en modo directo).
- Orden: por `etaMinutes`, estable (con los mismos minutos queda el orden de
  transporteRest).
- **Confort.** Solo para los ómnibus con GPS (`real` y con `idEmpresa` e
  `idBus`). El Worker le pide a `ImGateway` `/vehicles?ids=50:111,50:1118,…` y
  espera como mucho 2 s. Si falla, tarda o no hay binding, el confort va en
  `null` y la respuesta sale igual.
- No están en la forma pública: `realTime`, `scheduledTime`, `companyId`,
  `location`, `accessibilityType` ni `vehicle`.

### ScheduleResponse

Para Horarios. Golden `responses/schedule_3140_weekday_8-05.json`, 50 pasadas
a partir de las 8:05; las dos primeras:

```json
{"passes": [
  {"line": "143", "destination": "CIUDADELA", "time": "8:09", "hhmm": 809},
  {"line": "145", "destination": "PLAZA ESPAÑA", "time": "8:10", "hhmm": 810}
]}
```

| Campo | Regla |
|---|---|
| `line` | `linea` |
| `destination` | `destino` tal cual |
| `time` | `horaDesc` recortado y sin el cero de la hora; si está vacío, `H:MM` armado con `hora` |
| `hhmm` | entero de 0 a 2359, nunca `null`: `toIntLoose(hora)`; si falta, los dígitos de `time` |

- Se descarta la fila sin línea, sin hora o sin `hhmm`. `hora` no se controla
  contra un rango.
- Las filas quedan en el orden de transporteRest, que sigue después de
  medianoche. Horarios marca el salto cuando `hhmm` baja.

### CatalogStopsResponse

Para «Buscar por calles» y «Paradas cercanas». Golden
`responses/catalog_sample.json`, 4 paradas; dos de ellas:

```json
{
  "fetchedAt": "2026-10-27T13:22:26.000Z",
  "linesAvailable": true,
  "stops": [
    {"id": 574, "name": "SAN JOSE y ANDES",
     "location": {"lat": -34.90739436, "lng": -56.198255},
     "lines": ["116", "117", "121", "141", "142", "144", "538"]},
    {"id": 6325, "name": "MATAOJO",
     "location": {"lat": -34.88287335, "lng": -56.11962915},
     "lines": ["21", "427"]}
  ]
}
```

| Campo | Regla |
|---|---|
| `fetchedAt` | cuando `ImGateway` cargó las paradas de la API oficial |
| `linesAvailable` | `true` si había índice de paradas; `false` si no lo hubo después de esperar hasta 20 s |
| `stops[].id` | `busstopId` de la API oficial |
| `stops[].name` | `street1` y `street2` recortados y unidos con `" y "`; `null` si los dos están vacíos. Dart pone «Parada N» y le deja la clave de búsqueda vacía, así ninguna búsqueda la encuentra. |
| `stops[].location` | `location.coordinates` de la API oficial (`[lng, lat]`) como `{lat, lng}`. Una parada sin ubicación no entra. |
| `stops[].lines` | las líneas de esa parada en el índice (`desc_linea` del WFS), sin repetidos, ordenadas con `compareLines`. `[]` con `linesAvailable: false` o si la parada no está en el índice. |

- Son unas 4970 paradas (unos 660 KB). La app las guarda un día; un
  catálogo con `linesAvailable: false`, solo 15 min (ver abajo).
- Con `linesAvailable: false`, `ImGateway` le avisa al Worker con el
  encabezado interno `X-Lines: 0`. El Worker guarda la respuesta 900 s y no
  pasa ese encabezado. Golden: `responses/catalog_nolines.json`.
- Los nombres de línea del WFS pueden diferir de los de transporteRest
  (`M-A`, `PA`, `124 SD`): una parada del catálogo puede listar más líneas que
  la tarjeta guardada.
- En la app, `linesAvailable` decide solo qué se guarda
  (`MvdApiService.getStopCatalog`). Un catálogo sin líneas nunca reemplaza
  una copia del teléfono que tiene líneas: la app sigue con esa copia. Si no
  hay una copia con líneas, lo guarda con la fecha corrida hacia atrás, así
  vence a los 15 min, como en el borde. Ninguna pantalla lo lee: con `lines`
  vacío, la fila de una parada cercana termina en la distancia.

### NewsResponse

Para Novedades. Golden `responses/news_cold.json`, ids 182 a 173; el primero,
con el cuerpo recortado:

```json
{
  "fetchedAt": "2026-10-27T13:23:00.000Z",
  "news": [
    {"id": 182, "title": "Traslado definitivo de cuatro paradas",
     "summary": "Sobre Av. Rondeau, Paraguay y Gral. Aguilar",
     "body": "Por obras viales y futura ciclovía se trasladaron definitivamente cuatro paradas: …",
     "link": "https://montevideo.gub.uy/node/99018",
     "publishedAt": "2026-10-26T18:28:02.591Z"}
  ]
}
```

| Campo | Regla |
|---|---|
| `id` | `toIntLoose(idMensaje)` |
| `title`, `summary`, `body` | `titulo`, `mensajeCorto`, `mensajeCompleto`, recortados con `trimText`. `body` es HTML o texto tal como se publicó, sin convertir; puede ser `""`. La app lo muestra con `SafeHtml`. |
| `link` | regla `newsLink` sobre `dataLink` |
| `publishedAt` | `fecha` (ms) como ISO |

- Se saltea el mensaje sin id o sin fecha válida. `idUsuario` y `topicId` no
  pasan.
- **Paginado.** `idApp=1`, se empieza en `fromIdMessage=0`. La fuente
  devuelve como mucho 10 mensajes con id mayor que `fromIdMessage`, en el
  orden en que los guarda, más `count` (cuántos hay en total arriba de ese
  id). Si `count` es mayor que lo recibido, `from` sube en la diferencia y se
  pide de nuevo. Como mucho 8 pedidos, uno después del otro, de 5 s cada uno.
  En la captura: 0 → 136 → 168 → 172.
- La respuesta trae los mensajes de la **última página alcanzada**: como
  mucho 10, ordenados por `publishedAt` y después por `id`, de más nuevo a más
  viejo.
- Si una página falla, la ruta entera da 502 (caso `news.page_fails`).
- La app mezcla lo recibido con su propia copia en Hive, de hasta 30
  novedades.

### GpsStatusResponse

Para el aviso «Datos GPS parciales». Golden `responses/gps_ok.json`:

```json
{
  "fetchedAt": "2026-10-27T13:23:30.000Z",
  "operators": [
    {"company": "COETC", "percent": 100, "partial": false},
    {"company": "COME", "percent": 100, "partial": false},
    {"company": "CUTCSA", "percent": 100, "partial": false},
    {"company": "UCOT", "percent": 100, "partial": false}
  ]
}
```

| Campo | Regla |
|---|---|
| `company` | `empresa` recortado con `trimText` |
| `percent` | `clamp(round(valor), 0, 100)` |
| `partial` | `percent < 70` |

- Se saltea el elemento sin empresa o cuyo `valor` no es un número JSON finito
  (un texto como `"80"` tampoco sirve).
- Queda el orden de pci.
- `[]`, algo que no es lista o ningún elemento válido: 502.
- El texto del aviso vive en la app (`BusStatusService.partialWarning`). Si
  falta `partial`, la app lo calcula con `OperatorGpsStatus.partialThreshold`
  (70).

## 5. Reglas de derivación

Cada regla está dos veces, en `proxy/src/rules.js` y en
`lib/services/api/contract_rules.dart`. Las dos suites corren todos los
archivos de `proxy/contract/v1/vectors/` (9 archivos, 148 casos).

| Regla | Definición | Vectores |
|---|---|---|
| `toIntLoose` | Número → truncado hacia el cero. Texto que, recortado, es `^-?\d+$` → entero (`"007"` → 7). Cualquier otra cosa → `null` (`"5.0"`, `"+5"`, `true`, `""`). Un entero fuera de ±(2^53 − 1) también → `null` (`1e20`, `"99999999999999999999"`): ahí JS ya redondea y Dart se desborda, así que ninguno tiene el valor. | `int_coercion.json` |
| `trimText` | Quita `^[\s\u0085]+\|[\s\u0085]+$`. U+0085 se agrega porque el `trim` de JS lo deja y el de Dart lo saca. Los espacios del medio no se tocan. | `text_trim.json` |
| `compareLines` | Primero el número inicial como entero; una línea con número va antes que una sin número; los empates, por unidades de código UTF-16 (`<` y `>` en JS, `compareTo` en Dart), nunca `localeCompare`. `["124 SD","124","CE1","21","D10","D9","104","M-A","PA"]` → `["21","104","124","124 SD","CE1","D10","D9","M-A","PA"]`. | `line_order.json` |
| `stopName` | `[calle, esquina]` recortados con `trimText`, sin las partes vacías, unidos con `" y "`; `null` si no queda ninguna. | `stop_name.json` |
| `arrival` | Una fila de `siguientesParada` → un elemento de `arrivals`, o `null`. Ver la tabla de ArrivalsResponse. `real` cuenta solo si es exactamente `true`; `time` cuenta solo si es un número JSON. Una hora esperada fuera de `±8.64e15` ms → `null`. `destino` nunca se recorta. `airConditioning` y `zeroEmission` salen en `null`: el confort lo agrega el Worker después. | `arrival.json` |
| `newsLink` | Sobre el texto recortado, `^(https?)://([^/?#]+)(.*)$` sin distinguir mayúsculas: esquema y host en minúsculas, el resto igual. Cualquier otra cosa (`""`, `"null"`, `ftp:`, sin host) → `null`. | `news_link.json` |
| `gpsOperator` | `percent = clamp(round(valor), 0, 100)`, `partial = percent < 70` (69,5 → 70 → `false`). | `gps_status.json` |
| `stopId` | Válido si y solo si `1 ≤ id ≤ 9999999`. Un id inválido no genera ningún pedido. | `stop_id.json` |
| `schedulePath` | `weekday`, `saturday`, `sunday` ↔ `HABIL`, `SABADO`, `DOMINGO`. La hora va `H:MM`. Da la ruta del proxy y la URL de transporteRest. | `schedule_path.json` |

La hora de Montevideo (`montevideoClock`) es UTC−3 fijo en los dos lados:
Uruguay no tiene horario de verano desde 2015. Si vuelve, cambian las dos
implementaciones y los vectores.

Lecturas que ningún vector fija, y que el modo directo copia leyendo el código
del proxy:

- **Parada**: los nombres de línea no se recortan; se sacan los repetidos y se
  ordenan con `compareLines`.
- **Horario**: `time` y `hhmm` como en la tabla de ScheduleResponse.
- **Novedades**: `id = toIntLoose(idMensaje)` y la fecha `toIntLoose(fecha)`.
  Una fecha fuera de `±8.64e15` ms no es fecha y el mensaje se saltea: en el
  proxy lo descarta el control de `Date`; en Dart, `ContractRules.maxDateMs`.
  `count` cuenta solo si es un número JSON; si no, vale la cantidad de
  mensajes usables.
- **Catálogo**: solo existe en el proxy (`toStops` en `im_api.js`), así que no
  tiene gemela en Dart.
- **WFS de «Paradas cercanas»**: solo existe en Dart
  (`WfsAdapter.featuresToCatalogItems`).
- **`compareDirections`**: solo existe en el proxy (`im_gateway.js`).

## 6. Caché y presupuesto de la API oficial

### Caché

| Ruta | Caché de borde (200) | En la app | Pedidos a fuentes cuando no hay caché | Unidades del presupuesto IM |
|---|---|---|---|---|
| arribos | 15 s | ninguna. Mis paradas pide cada 30 s solo mientras está a la vista (`StopsPage.autoRefreshInterval`); «Estoy esperando» en Android, cada 30 s (`BusWaitTaskHandler.pollInterval`); la tarea de fondo, cada 15 min o más | 1 a transporteRest, más `/vehicles` a `ImGateway` si hay ómnibus con GPS | 0 directas. `/vehicles` contesta de memoria o del almacenamiento y recarga la flota en segundo plano si tiene más de 15 s: como mucho 4 flotas por minuto en total |
| parada | 86 400 s; 300 s sin `directions` | la parada guardada en Hive (`BusStop`) | 1 a transporteRest, más `/stops/{id}/meta` a `ImGateway` (lee una de las 64 partes del índice) | 0 |
| horario | 21 600 s | memoria, 6 h, por parada, día y hora | 1 a transporteRest | 0 |
| catálogo | 86 400 s; 900 s con `linesAvailable: false` | caja perezosa de Hive `catalog`, 1 día; sin líneas, 15 min, y nunca encima de una copia con líneas; si el proxy no contesta, sirve la copia vieja | `ImGateway`: las paradas de la API oficial (de memoria o de la API) y las líneas del índice | como mucho 1 cada vez que `ImGateway` se despierta, por las paradas (la copia vive solo en memoria). Con 24 h de caché de borde, en la práctica una por día y por centro de datos de Cloudflare |
| novedades | 300 s | Hive, 30 novedades (`news_cache`); se pide como mucho cada 10 min, o cada 30 s al deslizar | 1 a 8 páginas de notificacion | 0 |
| GPS | 60 s | memoria, 60 s (`BusStatusService.minInterval`) | 1 a pci | 0 |
| índice de paradas | – | almacenamiento de `ImGateway`, 64 partes | CSV de geoserver (sin clave; nunca pasa por `spend()`) y `linevariants` de la API oficial | como mucho 1 por armado, por las variantes; un CSV que falla no gasta ninguna. Un armado bueno dura 24 h; uno incompleto o fallido se reintenta a los 15 min, también después de hibernar |

- **Caché de borde.** Workers Caching (`"cache": {"enabled": true}` en
  `proxy/wrangler.jsonc`). Ante un acierto, Cloudflare contesta sin correr el
  Worker: no cuenta para el límite por IP ni llega a las fuentes. Cada versión
  del Worker tiene su propia caché, así que después de un deploy arranca
  vacía.
- **No hay ruta por lotes.** Una URL por parada hace que toda la gente que
  mira una parada popular comparta la misma entrada de la caché. La app saca
  los repetidos y pide en paralelo (`MvdApiService.getBoards`).
- **Límite por IP.** `IP_LIMITER`: 300 pedidos por minuto, contado en cada
  ubicación de Cloudflare por separado y solo para pedidos sin caché. La IP no
  se guarda.

### Índice de paradas

- Lo arma `ImGateway` con el CSV de toda la capa WFS (unos 2,5 MB) y las
  variantes de línea de la API oficial.
- Se arma como mucho una vez por día y una sola vez aunque lleguen muchos
  pedidos juntos. Se sirve hasta 7 días; pasadas 24 h se rearma en segundo
  plano.
- Si `linevariants` falla, el índice se guarda como incompleto
  (`complete: false`) y sin `directions`.
- Se guarda en 64 partes (`stopmeta:{id % 64}`) más `stopmeta:info`. Después
  de dormirse, la metadata de una parada se lee de una parte, sin ningún
  pedido.
- Si un armado falla, su hora queda en `stopmeta:failedAt`, que se lee en la
  misma lectura que `stopmeta:info`. Así la espera de 15 min se cumple
  aunque el objeto se duerma en el medio; si no, cada vez que se despertara
  volvería a bajar la capa entera.
- `/v1/catalog/stops` espera hasta 20 s el primer armado. `/stops/{id}/meta`
  no espera: sin índice arranca un armado y contesta 503 `upstream_busy` con
  `Retry-After: 30`, y el Worker sirve la parada sin `directions`.

### Presupuesto

- La clave de la API oficial admite **14 pedidos por minuto** para todos los
  usuarios juntos. `ImGateway` se fija un presupuesto de
  `BUDGET_PER_MINUTE = 12`, con la ventana desde el segundo :00 como la de la
  IM. Quedan 2 para que el dueño pruebe a mano con la misma clave.
- Cada pedido a la API pasa por `spend()`. Pasado el presupuesto, o después de
  un 429 de la IM, `ImGateway` no llama a la API hasta que termine la espera y
  contesta 503 `upstream_busy` con `Retry-After`. El contador se guarda en el
  almacenamiento, porque la memoria no sobrevive a la hibernación.
- El token dura 5 minutos y se reutiliza. Su pedido no pasa por `spend()`.
- Peor caso: 4 (flota) + 1 (paradas) + 1 (variantes) = **6 unidades por
  minuto**, debajo de 12.
- Sacar `/v1/lines/{line}/buses` de las rutas públicas sacó la única ruta que
  podía disparar cargas de la flota a pedido.

## 7. Errores

### Códigos del proxy

| Status | `error` | Cuándo | Caché |
|---|---|---|---|
| 400 | `bad_request` | query string, `day` desconocido, hora mayor que 23 | `no-store` |
| 404 | `not_found` | ruta desconocida, `{id}` inválido, hora no canónica, rutas quitadas | `no-store` |
| 404 | `stop_not_found` | transporteRest contestó un error cuyo cuerpo empieza con `No existe` (por ejemplo `No existe la ubicación de parada con código '99999'.`) | `public, max-age=3600` |
| 405 | `method_not_allowed` | no es `GET`; con `Allow: GET` | `no-store` |
| 429 | `rate_limited` | se pasó el límite por IP; con `Retry-After: 60` | `no-store` |
| 500 | `internal_error` | cualquier excepción inesperada (`respond()`) | `no-store` |
| 502 | `upstream_error` | la fuente contestó un error, JSON inválido o una forma inesperada; la API oficial rechazó el secreto; el stub de `ImGateway` falló | `no-store` |
| 503 | `upstream_busy` | sin presupuesto o la IM pidió esperar; con `Retry-After` | `no-store` |
| 503 | `not_configured` | faltan `IM_CLIENT_ID`/`IM_CLIENT_SECRET` o el binding `IM_GATEWAY` | `no-store` |
| 504 | `upstream_timeout` | la fuente no contestó a tiempo | `no-store` |

Un error de transporteRest que dice `NoExisteTransporteException` en un
`BadRequestException` no es «parada inexistente»: da 502 (caso
`arrivals.upstream_500`).

### Del status a `ApiFailure`

`ProxySource.failureOf` en `lib/services/api/proxy_source.dart`:

| Respuesta del proxy | `ApiFailure` |
|---|---|
| 404 `stop_not_found` | `notFound` |
| 429 | `busy` |
| 503 `upstream_busy` | `busy` |
| 503 `not_configured` | `unavailable` |
| 504 | `timeout` |
| otro 400 o 404 (la app armó un pedido que el proxy no conoce: un bug, se anota con `debugPrint`) | `failed` |
| 500, 502 y cualquier otro status | `failed` |
| 200 que no es JSON, o JSON con la forma equivocada | `failed` |
| `TimeoutException` (10 s; catálogo 30 s; novedades 20 s) | `timeout` |
| `SocketException`, `ClientException` | `offline` |

`retryAfter` viene solo con `busy`: los segundos de `Retry-After`, o 60 s si
falta o no se puede leer (`ProxySource.defaultRetryAfter`).

En modo directo (`DirectSource._get`):

- una respuesta que no es 200 de transporteRest cuyo cuerpo empieza con
  `No existe` → `notFound`;
- un 429 de un servidor de la Intendencia → `busy` con su `Retry-After`;
- cualquier otro status, JSON inválido o una forma que el adaptador no
  entiende → `failed`;
- un dato que hace fallar la conversión (`DirectSource._converted`) →
  `failed` solo para ese pedido: `getBoards` sigue con las otras paradas;
- `TimeoutException` → `timeout`; `SocketException` y `ClientException` →
  `offline`;
- el catálogo → siempre `unavailable`.

En los dos modos, un `{id}` que no pasa `isValidStopId` da `notFound` sin
ningún pedido (`MvdApiService._call`).

### Esperar después de `busy`

- Si arribos, parada, horario, novedades o GPS contestan `busy`,
  `MvdApiService` no manda ningún pedido durante `retryAfter`, en todas las
  rutas: contesta `busy` sin pedir. En esas rutas solo puede ser el 429 del
  proxy, que es un límite por teléfono y vale para todas las rutas.
- El 503 `upstream_busy` del catálogo no frena las demás rutas: es solo del
  catálogo.
- Mis paradas, ante `busy`, no cambia lo que muestra, no escribe nada y
  saltea los ticks hasta el `retryAfter` más largo (60 s si no vino).

### Qué ve la persona

| Situación | Dónde | Texto |
|---|---|---|
| `notFound` | «Agregar parada» con un número escrito (aviso abajo); «Agregar ruta», debajo del campo al buscar la parada, o como aviso abajo si se guardó sin buscarla | «No existe la parada N. Revisá el número.» |
| `notFound` | tarjeta guardada en Mis paradas o en Rutas | «Esta parada ya no existe. Deslizá la tarjeta para borrarla.» |
| `failed`, `timeout`, `offline` | tarjeta, sin un tablero de menos de 5 min | «No se pudo actualizar. Deslizá para reintentar» |
| `failed`, `timeout`, `offline` | tarjeta, con un tablero de menos de 5 min | «No se pudo actualizar. Datos de las H:MM. Deslizá para reintentar.» y debajo las filas viejas como estimado («~H:MM») |
| `busy` | tarjetas | nada: siguen igual |
| ningún fallo, pero el tablero llegó hace 1 min o más | tarjeta | ningún texto: las filas pasan a estimado («~H:MM»); desde los 5 min, o si no queda ninguna fila, el indicador de carga |
| cualquier falla menos `notFound` | «Agregar parada» con un número escrito | se guarda igual como «Parada N»; al abrir la app, `healPlaceholderStops` le completa nombre y líneas |
| cualquier falla menos `notFound` | «Agregar ruta» | «No se pudieron cargar las líneas. Revisá la conexión.» |
| cualquier falla | Horarios | «No se pudo cargar el horario. Revisá la conexión.» y «Reintentar» |
| cualquier falla, también `busy` | Novedades | panel `avisoNoche`: «No se pudo actualizar. Deslizá para reintentar»; la lista guardada queda |
| cualquier falla | aviso GPS | nada: queda el último estado bueno |
| cualquier falla, también `unavailable` con proxy | «Buscar por calles» | «No se pudo cargar la lista de paradas. Revisá la conexión.» |
| sin proxy | «Buscar por calles» | el campo no aparece |
| cualquier falla del catálogo o del WFS | «Paradas cercanas» | «No se pudieron cargar las paradas cercanas. Revisá la conexión.» |
| cualquier falla | avisos de fondo | ningún aviso: «no se pudo consultar» no es «no viene ningún ómnibus» |
| cualquier falla | widget | estado `offline`; la fila queda mientras su ómnibus no haya pasado |
| cualquier falla | aviso fijo de «Estoy esperando» (Android) | «Sin conexión, reintentando… · PARADA» |

El catálogo completo de textos está en [07-textos.md](07-textos.md); dónde
aparece cada uno, en [09-pantallas.md](09-pantallas.md).

## 8. Privacidad y logs

- **Una versión con proxy no manda coordenadas a ningún lado.** «Paradas
  cercanas» se calcula en el teléfono con el catálogo
  (`NearbyStopsService.nearbyFrom`). Lo verifican
  `test/proxy_privacy_test.dart` y `test/nearby_stops_service_test.dart`.
- **Una versión con proxy no llama a ningún servidor de la Intendencia.**
  `api.montevideo.gub.uy`, `pci.montevideo.gub.uy` y
  `geoserver.montevideo.gub.uy` nunca se piden. Lo verifican
  `test/proxy_privacy_test.dart` (cada servicio) y `test/proxy_bff_test.dart`
  (la interfaz). Los enlaces que se abren en el navegador (Cómo Ir, Mi STM,
  Recarga) no son pedidos de la app.
- **Una versión sin proxy** pide a geoserver una caja centrada en la posición
  **redondeada a 3 decimales**, con medio lado de 472 m: el radio de 400 m más
  72 m, la mitad de la diagonal de una celda de 0,001°. Así la caja contiene
  todo el círculo alrededor de la posición exacta. El teléfono después filtra
  con la posición exacta (`NearbyStopsService.buildUri`,
  `boxHalfSideMeters`). Eso hace verdadera la frase «área aproximada» de
  [docs/privacy-policy.md](../privacy-policy.md).
- Los demás pedidos llevan solo números de parada. Las paradas, las rutas, lo
  leído en Novedades y los avisos guardados no salen del teléfono.
- **Logs del proxy apagados.** `proxy/wrangler.jsonc` no tiene bloque
  `observability`, y la regla es no agregarlo: Workers Logs guardaría cada
  pedido con la ruta (que lleva el número de parada) y la IP.
- Lo único que se escribe (`console.error`) son textos fijos
  `<fuente>: <tipo>`, por ejemplo `transporteRest: HTTP 500`,
  `geoserver: TimeoutError`, `imApi: HTTP 500`, `imApi: token refused`,
  `internal: TypeError` o `im-gateway: no line variants`. Sin URL, sin ruta y
  sin IP.
  `proxy/test/index.test.js` lo verifica, y `proxy/test/im_gateway.test.js`
  para las líneas de `ImGateway`.
- La IP solo sirve de clave para el límite y no se guarda. A `ImGateway` no
  llega: ahí van solo números de ómnibus y de parada.
- Ningún encabezado de las fuentes llega a la app (por ejemplo, las cookies
  de F5).

## 9. Evolución

- Mientras no haya una versión pública de la app, `/v1` puede cambiar en el
  lugar.
- Desde la primera versión pública, `/v1` solo suma: campos nuevos o rutas
  nuevas. Una versión de la app ya instalada sigue pidiendo `/v1` y no se
  actualiza sola, así que `/v1` no se puede romper.
- Lo que rompa (sacar o renombrar un campo, cambiar su tipo o su significado,
  cambiar un código de error) va a `/v2`.
- Por qué sumar es seguro: el lector ignora las claves que no conoce
  (sección 3). Pero el lector saltea un elemento al que le falta un campo
  obligatorio: una app que empieza a exigir un campo nuevo necesita que el
  proxy ya lo mande. Por eso, siempre, primero el proxy (sección 12).

## 10. Para cambiar el contrato

1. Escribí el cambio primero en este documento.
2. Escribí a mano el golden en `proxy/contract/v1/responses/` y verificalo
   contra las capturas de `upstream/`. Si hace falta una captura nueva, va con
   fecha y sin encabezados de la fuente.
3. Si cambia una regla: sus vectores en `vectors/`, `proxy/src/rules.js` y
   `lib/services/api/contract_rules.dart`, en el mismo commit.
4. Proxy: el código en `proxy/src/`. Un código de error nuevo se escribe como
   `error(NNN, 'código'` en `index.js` o `{ error: 'código' }` en
   `im_gateway.js`: así lo encuentra la prueba de cobertura.
5. App: el adaptador del modo directo en `lib/services/api/direct/` (o una
   máscara nueva en `direct_masks.json`, con su motivo en la sección 2),
   `V1Parser`, el modelo en `lib/models/` y la escritura del modelo como /v1 en
   `test/contract/contract_test.dart` (`_stopToV1`, `_boardToV1`, etc.).
6. Casos en `cases.json`: al menos uno por ruta nueva y uno por código de error
   nuevo. El formato está en [proxy/contract/v1/README.md](../../proxy/contract/v1/README.md).
7. Corré los dos lados: `cd proxy && npm test`, y `flutter test` desde la raíz
   del repo (las pruebas de Dart leen el contrato por ruta relativa).
8. Si cambia lo que muestra una pantalla, actualizá
   [pantalla-a-datos.md](pantalla-a-datos.md).
9. Anotá el cambio en `CHANGELOG.md`, en `[Unreleased]`.
10. Desplegá en el orden de la sección 12.

## 11. El triángulo de pruebas

Cada caso de `cases.json` se prueba por tres lados, contra el mismo golden:

```
                upstream/  (capturas de las fuentes)
                  │                       │
   (1) proxy      ▼                       ▼     (2) app, modo directo
      Worker + fuentes simuladas     DirectSource + adaptadores
                  │                       │
                  ▼                       ▼
                responses/  (golden)  ◀── máscara de direct_masks.json
                            │
                            ▼  (3) app, modo proxy
                 ProxySource + V1Parser → modelo → de vuelta a /v1
```

1. **Proxy** (`proxy/test/contract.test.js`): las fuentes simuladas con las
   entradas de `upstream` dan, a través del Worker, un cuerpo igual al golden
   (sin `fetchedAt`). Además: el status, el `Cache-Control` y el
   `Content-Type` exactos, los encabezados del caso y las URLs pedidas
   exactas. También verifica que cada expresión de `ROUTES` tenga un caso y
   que cada código de error lo tenga (menos `internal_error`,
   `method_not_allowed` y `rate_limited`, que prueba
   `proxy/test/index.test.js`).
2. **App en modo directo** (`test/contract/contract_test.dart`, grupo
   `direct mode`): las mismas capturas dan, a través de `DirectSource`, un
   JSON /v1 igual al golden con la máscara aplicada; las URLs pedidas son las
   de `direct.upstream`, y un caso de error da `direct.failure`.
3. **App en modo proxy** (el mismo archivo, grupo `proxy mode`): el golden
   servido en `https://proxy.test{request}` da, a través de `MvdApiService` y
   `V1Parser`, un modelo que, escrito de vuelta como /v1, es igual al golden.
   O da el `ApiFailure` y el `retryAfter` esperados. Exactamente un pedido, o
   ninguno si el caso dice `request: false`.

Si un cambio del contrato se olvida de un lado, ese lado se pone en rojo. Hay
24 casos; 19 corren en Dart y 5 son solo del proxy (rutas quitadas, hora no
canónica, día desconocido, hora mayor que 23). Los vectores los corren
`proxy/test/rules.test.js` y `test/contract/rules_test.dart`.

Las pruebas comparan valores exactos, pero no prueban nada sobre las fuentes en
vivo: para eso está `proxy/scripts/smoke.js` (sección 12).

## 12. Orden de despliegue

**Primero el proxy, después la app.** Una versión con `MVD_PROXY_URL` nunca
vuelve al modo directo: sin proxy, solo muestra errores.

1. Las dos suites en verde: `cd proxy && npm test` y `flutter test` desde la
   raíz.
2. Desplegá el proxy (`npm run deploy` en `proxy/`; los secretos y los pasos
   están en [proxy/README.md](../../proxy/README.md)).
3. Corré la prueba de humo contra el Worker desplegado:

   ```bash
   node scripts/smoke.js https://mvd-transporte-proxy.<subdominio>.workers.dev
   ```

   Pide la ruta de cada caso que contesta 200 y verifica el status, el
   `Cache-Control`, el `Content-Type` y las claves del cuerpo contra los
   goldens (los valores no, porque son datos en vivo). Al lado de cada ruta
   muestra con qué caso coincidió: `stop.574.degraded` o `catalog.nolines`
   quieren decir que el proxy anda, pero sin `directions` o sin líneas.
   Solo contra el Worker desplegado las fuentes ven las direcciones de
   Cloudflare: si un F5/BigIP delante de geoserver, notificacion o pci las
   bloquea, acá se ve (novedades y GPS dan 502, el catálogo sale sin líneas y
   las paradas sin `directions`). Contra `wrangler dev` no prueba eso.
4. Recién entonces compilá la app con
   `--dart-define=MVD_PROXY_URL=https://mvd-transporte-proxy.<subdominio>.workers.dev`.

Después de cada deploy, la caché de borde arranca vacía; el primer pedido de
arribos puede venir sin confort, y hasta que termine el primer armado del
índice, `/v1/stops/{id}` sale sin `directions` y con 300 s de caché.

## 13. Pendientes conocidos

- **Parada 6325.** El caso `arrivals.empty` usa la parada 6325, y el
  2026-10-27 transporteRest contestaba HTTP 500 para `siguientesParada/6325`.
  Mientras siga así, `smoke.js` marca esa ruta como FAIL: es un problema de la
  fuente, no del proxy. Cambiar de parada pide una captura y un golden nuevos
  para las dos suites.
- **Reloj del modo directo.** `DirectSource` no permite inyectar el reloj. Los
  goldens directos de arribos coinciden porque todas las filas capturadas
  traen `time`; una captura con filas sin `time` dependería del reloj de la
  prueba.
- **Sin medir en Cloudflare.** El tiempo de CPU del armado del índice dentro
  del Durable Object (unos 50 ms en Node para el CSV de 2,5 MB) y el bloqueo
  posible del F5/BigIP se ven recién con el Worker desplegado.
- **`directUrl` en versiones con proxy.** `ContractRules.schedulePath` arma
  igual la URL de transporteRest junto a la ruta del proxy, porque los
  vectores fijan las dos. Esa URL nunca se pide.
