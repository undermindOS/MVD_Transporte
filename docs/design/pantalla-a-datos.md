# De la pantalla a los datos

Qué dato muestra cada parte de la app y de dónde sale. Cada fila de estas
tablas se lee de izquierda a derecha, desde lo que ve la persona hasta la
fuente de la Intendencia:

```
componente  ←  campo del modelo  ←  campo /v1  ←  campo de la fuente
```

Por ejemplo, la hora de una fila sin GPS: `ArrivalRow` muestra
`BusArrival.etaLabel`, que en ese estado es `clockTime`, que sale de
`arrivals[].clockTime`, que el proxy arma con `horaDesc` de transporteRest.

**El código manda.** Todo lo de esta página está verificado en `lib/ui/*`,
`lib/models/*`, `lib/services/*` y `proxy/src/*`. Si algo no coincide, vale el
código: corregí esta página.

Ver también:
- [contrato-v1.md](contrato-v1.md): la regla exacta de cada campo /v1
  (recortes, órdenes, valores por defecto, errores);
- [08-componentes.md](08-componentes.md): cómo se ve cada componente;
- [09-pantallas.md](09-pantallas.md): los estados de cada pantalla y cuándo se
  refresca;
- [07-textos.md](07-textos.md): todos los textos;
- [10-superficies.md](10-superficies.md): el widget y las notificaciones.

## Cómo leer las tablas

- **Fuente** es lo que contesta la Intendencia. Salvo que la fila diga otra
  cosa, es la misma en las dos versiones de la app: el proxy y el modo directo
  leen los mismos campos de transporteRest, notificacion y pci, con las mismas
  reglas ([contrato-v1.md](contrato-v1.md), sección 5).
- Donde el modo directo (sin `MVD_PROXY_URL`) es distinto, la fila lo dice.
  Las diferencias son siempre las mismas cinco: sin confort, sin
  `directions`, sin catálogo, «Paradas cercanas» con una caja de geoserver, y
  la ubicación de las paradas del Mapa pedida a geoserver por número
  ([contrato-v1.md](contrato-v1.md), sección 2).
- **IM** es la API oficial de la Intendencia
  (`api.montevideo.gub.uy/api/transportepublico`). Solo la llama `ImGateway`,
  dentro del proxy.
- **Guardado** quiere decir que la pantalla no muestra una respuesta /v1 sino
  lo que la app guardó en el teléfono (Hive) cuando se agregó la parada o la
  ruta. La última sección dice cuándo se actualiza.

## Mis paradas: tarjeta de parada

`_buildStopCard` en `lib/ui/stops_page.dart`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Nombre («SAN JOSE y ANDES») | `BusStop.name` (guardado) | según cómo se agregó: `name` de `/v1/stops/{id}`, `stops[].name` del catálogo, o ninguno («Parada N») | `descripcion` de transporteRest `lineas/{id}`; IM `busstops`: `street1` y `street2`; modo directo, en «Paradas cercanas»: `calle` y `esquina` del WFS |
| Número («#574») | `BusStop.id` | – | lo que escribió o eligió la persona |
| Filas de ómnibus | `ArrivalsBoard.arrivals`, de `MvdApiService.getBoards` | `arrivals` de `/v1/stops/{id}/arrivals` | transporteRest `siguientesParada/{id}` (ver la sección siguiente) |
| «Sin ómnibus próximos» | `arrivals` vacío | `"arrivals": []` | transporteRest contestó `[]` |
| «Ver las N» y «Ver menos» | cantidad de filas: se ven 3 y se abren hasta 6 | – | – |
| Línea de aviso («Aviso 5 min antes · …») | `BusStop.etaAlertMinutes`, `BusStop.schedule` | – | ajuste guardado en el teléfono |
| «Ver en Cómo Ir» | `BusStop.id` | – | abre `OfficialSite.comoIrStop(id)` en el navegador |

`BusStop.lines` también se guarda, pero hoy ninguna pantalla lo muestra:
solo sirve para que `healPlaceholderStops` reconozca una parada guardada sin
datos.

## Fila de ómnibus: `ArrivalRow`

`lib/ui/widgets/arrival_row.dart`. La misma fila se usa en las tarjetas de
parada y de ruta, y en la hoja de una parada del Mapa. Cada fila es un `BusArrival` (`lib/models/bus_arrival.dart`),
que es un elemento de `arrivals`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Número de línea (`LineBadge`) | `line` | `line` | `linea` |
| Badge encendido (ámbar lleno) o en contorno | `isRealTime`, y que la fila no sea estimada | `state`: `live` o `arriving` → encendido; `scheduled` → contorno | `real === true` |
| Destino | `destination`; si está vacío, «Línea N» | `destination` | `destino`, tal cual, sin recortar (`null` → `""`) |
| Marca accesible | `accessible` | `accessible` | `accesibilidad === true` |
| Marca aire acondicionado | `airConditioning == true` | `airConditioning` | IM `/buses`: `thermalConfort` igual a `"Aire Acondicionado"`, cruzado por empresa y número de ómnibus (`idEmpresa`, `idBus`). Modo directo: siempre `null`, la marca no aparece |
| Marca cero emisiones | `zeroEmission == true` | `zeroEmission` | IM `/buses`: `emissions` igual a `"Cero emisiones"`. Modo directo: siempre `null` |
| Minutos encendidos (`MinutosEnVivo`) | `etaMinutes` | `etaMinutes` | `max(0, minutos)` |
| LLEGANDO (`LlegandoChip`) | `etaMinutes <= 0` en una fila con GPS | `state: "arriving"`, `etaMinutes: 0` | `real === true` y `minutos <= 0` |
| Hora con reloj («20:01») | `etaLabel`, que en `scheduled` es `clockTime` | `clockTime` | `horaDesc` recortado y sin el cero de la hora; si viene vacío, `time` en hora de Montevideo |
| Hora estimada («~20:01») | `clockTime` del último tablero bueno | `clockTime` | igual que la anterior |
| Marca de espera (campana, fila en `tintaAlta`) | `BusWait.follows(fila, tablero, ahora)` | `tripId`, `variantId`, `expectedAt` | `idEmpresa` e `idBus`, o `variante` y `hora`; `variante`; `time` |
| Orden de las filas | el de la lista, sin reordenar | orden de `arrivals` | por `etaMinutes`, estable: con los mismos minutos queda el orden de transporteRest |

`tripId` no se ve, pero identifica el viaje entre un pedido y el siguiente:
`bus-{idEmpresa}-{idBus}` para un ómnibus con GPS, `sched-{variante}-{hora}`
para uno de horario ([contrato-v1.md](contrato-v1.md), regla `arrival`).

### Los cinco estados de una fila

| Estado | Cuándo | Qué se ve | Campos que decide |
|---|---|---|---|
| Vivo | `state: "live"` | badge encendido, punto, minutos en Doto y «min» | `state`, `etaMinutes` (1 o más) |
| Llegando | `etaMinutes` en 0 con GPS | badge encendido y LLEGANDO | `state`, `etaMinutes` |
| Horario | `state: "scheduled"` | badge en contorno, reloj y `clockTime` | `state`, `clockTime` |
| Estimado | el último pedido falló y el último tablero bueno tiene menos de 5 min; o no falló, pero ese tablero llegó al teléfono hace 1 min o más y menos de 5 | badge en contorno, reloj y «~`clockTime`»; nunca ámbar y no se puede tocar | la hora en que el tablero llegó al teléfono (con fallo o sin él), `expectedAt` (quedan las filas con `expectedAt` desde hace 1 min o después, en el reloj de la fuente: `fetchedAt` más lo que el tablero lleva en el teléfono), `clockTime` |
| Esperado | `BusWait.follows` da esta fila | además de vivo, llegando u horario: fila levantada en `tintaAlta` y campana ámbar | `tripId`; si no está, el mismo `variantId` (o la misma línea y destino) con el `expectedAt` más cercano, a menos de 10 min |

Una fila estimada nunca se marca como esperada.

### La frase para lectores de pantalla

`ArrivalRow._sentence` arma una sola frase con los mismos campos:

```
Línea {line} a {spokenName(destination)}, {cuándo}[, accesible][, aire acondicionado][, cero emisiones][, estás esperando este ómnibus]
```

`{cuándo}` es «llega en N minutos, con GPS», «llegando, con GPS», «horario
{clockTime}, sin GPS» o «alrededor de las {clockTime}, estimado». Si
`destination` está vacío, la frase empieza «Línea N, …», sin «a».

## Nota de error y datos viejos

`_buildArrivals` en `lib/ui/stops_page.dart`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| «No se pudo actualizar. Datos de las 19:52. Deslizá para reintentar.» | `MvdApiService.montevideoClock(ArrivalsBoard.fetchedAt)` | `fetchedAt` | el reloj del Worker cuando contestó transporteRest; modo directo: el reloj del teléfono cuando llegó la respuesta |
| Filas estimadas debajo de esa nota | `BusArrival.expectedAt` desde hace 1 min o después | `arrivals[].expectedAt` | `time` (ms); si no viene, `fetchedAt` más los minutos |
| Solo «No se pudo actualizar. Deslizá para reintentar» | no hay tablero bueno, o llegó al teléfono hace 5 min o más | – (la hora en que llegó al teléfono) | – |
| Filas estimadas sin nota (no hubo fallo) | el tablero llegó hace 1 min o más (`_BoardView.receivedAt`); quedan las de `expectedAt` desde hace 1 min o después. Desde los 5 min, o sin filas, el indicador de carga | `arrivals[].expectedAt` | – |
| «Esta parada ya no existe. Deslizá la tarjeta para borrarla.» | `ApiFailure.notFound` | 404 `stop_not_found` | transporteRest contestó un error que empieza con `No existe` |

`fetchedAt` es la hora en que contestó la fuente, no la del pedido: desde la
caché del proxy puede tener hasta 15 s más. Por eso «Datos de las…» dice de
cuándo son los minutos. La edad, con fallo o sin él, no sale de `fetchedAt`
sino de la hora en que el tablero llegó, según el reloj del teléfono
(`StopsPage.clock`): el reloj del servidor puede estar corrido. Para la edad
`fetchedAt` no cuenta; además de «Datos de las…», da el «ahora» de la fuente
para cortar las filas estimadas vencidas.

## Rutas: tarjeta de ruta

`_buildRouteCard` en `lib/ui/stops_page.dart`. La tarjeta no hace su propio
pedido: lee el tablero de su parada de origen, el mismo que usa una tarjeta
de parada con ese número.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Parada de origen | `RouteAlert.originName` (guardado) | `name` de `/v1/stops/{id}` al guardar (`StopDetails.displayName`); «Parada N» si no se pudo buscar | `descripcion` |
| «→ Trabajo» | `RouteAlert.destinationName` | – | lo que escribió la persona |
| «Líneas: 116, 121» | `RouteAlert.preferredLines` | `lines` al guardar | `lineas[].descripcion` |
| «Hacia: POCITOS» | `RouteAlert.preferredDestinations` | `directions[].destination` al guardar, o `arrivals[].destination` (respaldo) | IM `linevariants`: `destination` de cada `cod_variante` del WFS de la parada; o `destino` |
| Filas | el tablero de `originStopId`, filtrado por `RouteAlert.accepts` | `arrivals[].line`, `variantId`, `destination` | `linea`, `variante`, `destino` |

`RouteAlert.accepts` deja pasar un ómnibus si su línea está en
`preferredLines` (sin distinguir mayúsculas; vacía = todas) y además no hay
filtro de dirección, o su `variantId` está en `preferredVariantIds`, o su
`destination` está en `preferredDestinations`. Por eso una ruta sigue andando
aunque transporteRest escriba el destino distinto que la API oficial.

## Aviso «Datos GPS parciales»

`_buildGpsWarning` en `lib/ui/stops_page.dart`, arriba de Mis paradas y de
Rutas.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| El aviso aparece | alguna `OperatorGpsStatus.isPartial` | `operators[].partial`; si falta, `percent < 70` | pci `buses/control`: `valor` redondeado menor que 70 |
| «COME 55 %» | `OperatorGpsStatus.company`, `percent` | `company`, `percent` | `empresa` recortado; `valor` redondeado y llevado a 0–100 |
| El resto del texto | `BusStatusService.partialWarning` | – | fijo en la app |

Se pide como mucho una vez por minuto (`BusStatusService.minInterval`), con
cada refresco de las tarjetas. Si falla, queda el último estado bueno.

## Novedades

`lib/ui/news_list.dart`. La lista que se ve es la copia guardada en el
teléfono (`news_cache`, hasta 30 novedades, en la forma de la API:
`TransportNews.toJson`). Cada refresco suma lo nuevo por `id`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Cuadro de fecha («26 OCT») | `TransportNews.date`, en la hora del teléfono | `publishedAt` | `fecha` (ms) |
| Título | `title` | `title` | `titulo`, recortado |
| Resumen | `summary` | `summary` | `mensajeCorto`, recortado |
| NUEVA y cuadro de fecha lleno | `id` mayor que el último leído al abrir la pestaña | `id` | `idMensaje` |
| Número sobre la pestaña | `TransportNewsService.unreadCount` | `id` | `idMensaje` |
| Detalle: fecha («26/10/2026») | `date` (`formatNewsDate`) | `publishedAt` | `fecha` |
| Detalle: texto | `body` con `SafeHtml`; si está vacío, `summary` | `body` | `mensajeCompleto`, recortado, HTML sin convertir |
| Detalle: «Ver más» | `link`; sin botón si es `null` | `link` | `dataLink`, con la regla `newsLink` |

El último leído (`news_last_read_id`) se guarda solo en el teléfono. En modo
directo la app pagina sola desde `news_from_id`; con el proxy recibe la última
página de una vez.

## Mapa

`MapaPage` en `lib/ui/map/mapa_page.dart`. Los ómnibus salen de
`MapBuses.from` (`lib/ui/map/map_buses.dart`), con los tableros de las
paradas guardadas que quedaron en `MvdApiService.latestBoards`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Parada guardada (`stop` sobre el mapa) | `BusStop.latitude`, `longitude` (guardado); 0, 0 es «sin ubicación» y no se dibuja (`hasLocation`) | `stops[].location` del catálogo: al elegirla en «Buscar por calles» o «Paradas cercanas», o la que busca `StopLocationsService` con proxy | IM `busstops`: `location.coordinates`; modo directo: `geometry.coordinates` del WFS, de «Paradas cercanas» o de un pedido por `cod_ubic_parada` (`CQL_FILTER`) |
| Ómnibus con GPS (píldora o punto) | `BusArrival.location`; un ómnibus por `tripId` `bus-…`, aunque esté en dos tableros | `arrivals[].location`, `tripId` | `coordinates` `[lng, lat]` de una fila con `real: true`; `idEmpresa`, `idBus` |
| Número de línea de la píldora | `BusArrival.line` | `line` | `linea` |
| Encendido o estimado | `MapBuses.liveness`: encendido si su tablero llegó al teléfono hace menos de 1 min y su parada no falló; desde los 5 min no se dibuja. La edad sale de `ReceivedBoard.receivedAt`, el reloj del teléfono, con o sin fallo: un teléfono con la hora corrida no apaga los ómnibus. Un estimado que debía llegar hace más de 1 min se saca con el reloj de la fuente (`MapBuses.overdue`: el `fetchedAt` del tablero más lo que lleva en el teléfono) | – (la hora en que llegó al teléfono) | – |
| Hoja de un ómnibus: destino | `BusArrival.destination`; si está vacío, «Línea N» | `destination` | `destino` |
| Hoja de un ómnibus: «a la parada 574 · SAN JOSE y ANDES» | `BusStop.id` y `name` (guardado) de cada parada guardada a la que va | – | – |
| Hoja de un ómnibus: minutos o «~19:56» | `etaMinutes`, `clockTime` del tablero de esa parada | `etaMinutes`, `clockTime` | `minutos`, `horaDesc` |
| Hoja de una parada | `ArrivalsBoard.arrivals`, hasta 6, como `ArrivalRow` | `arrivals` | transporteRest `siguientesParada/{id}` |
| «© OpenStreetMap» | `Basemap.attribution` | – | `attribution` de la fuente del estilo (`assets/map/style_noche.json`) |
| El mapa base | `Basemap` (`lib/services/map/basemap.dart`) | – | `assets/map/mvd-20261028.pmtiles`, dentro de la app ([assets/map/README.md](../../assets/map/README.md)) |

## Horarios

`lib/ui/schedule_page.dart`. Se abre desde el reloj de una tarjeta de parada.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Subtítulo («SAN JOSE y ANDES · 574») | `BusStop.name` y `BusStop.id` (guardado) | – | – |
| Hábiles, Sábados, Domingos | `DayType` | `{day}` de la ruta: `weekday`, `saturday`, `sunday` | `HABIL`, `SABADO`, `DOMINGO` |
| «Desde 8:05» | la hora elegida; al abrir, la de ahora redondeada hacia abajo a 5 min | `{H:MM}` de la ruta | `{H:MM}` de la URL de transporteRest |
| Hora de la pasada | `ScheduledPass.time` | `passes[].time` | `horaDesc` sin el cero de la hora; si viene vacío, `hora` como `H:MM` |
| Línea (badge compacto en contorno) | `ScheduledPass.line` | `passes[].line` | `linea` |
| Destino | `ScheduledPass.destination` | `passes[].destination` | `destino` |
| Encabezado de hora («8 h») | `hhmm ~/ 100` | `passes[].hhmm` | `hora`; si falta, los dígitos de `time` |
| «Después de medianoche» | un `hhmm` menor que el anterior | el orden de `passes` | el orden de transporteRest |

## Agregar parada

`_AddStopDialog` en `lib/ui/stops_page.dart`.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Número escrito, guardado | `StopDetails.toBusStop()`: `displayName` y `lines` | `name`, `lines` de `/v1/stops/{id}` | `descripcion`, `lineas[].descripcion` |
| «Buscar por calles»: nombre de cada resultado | `CatalogStop.name` («Parada N» si no tiene calles) | `stops[].name` | IM `busstops`: `street1` y `street2` |
| «Buscar por calles»: «#574» | `CatalogStop.id` | `stops[].id` | IM `busstopId` |
| «Paradas cercanas»: nombre | `NearbyStop.name`, que es `CatalogStop.name` | `stops[].name` | proxy: IM `street1` y `street2`; modo directo: `calle` y `esquina` del WFS |
| «Paradas cercanas»: «· 230 m» | `NearbyStop.distanceMeters`, calculada en el teléfono | `stops[].location` | IM `location.coordinates`; modo directo: `geometry.coordinates` del WFS |
| «Paradas cercanas»: «· 116, 117, …» | `NearbyStop.lines` | `stops[].lines` | `desc_linea` del WFS (del índice del proxy, o de la caja en modo directo) |
| Una parada elegida de una lista, guardada | `BusStop(id, name, lines, latitude, longitude)`, sin otro pedido | – | – |

- «Buscar por calles» busca en `CatalogStop.searchKey` (el nombre en
  minúsculas, sin tildes ni signos). Una parada sin calles tiene la clave
  vacía y ninguna búsqueda la encuentra.
- Con `linesAvailable: false` en el catálogo, `lines` viene vacío y la fila
  de una parada cercana termina en la distancia. Ninguna pantalla lee
  `linesAvailable`; `MvdApiService.getStopCatalog` sí: ese catálogo no
  reemplaza una copia guardada con líneas y, si se guarda, vence a los
  15 min.
- Los nombres de línea del WFS («M-A», «PA», «124 SD») pueden no ser los de
  transporteRest. Como `BusStop.lines` no se muestra, hoy no se ve la
  diferencia.
- En modo directo no hay catálogo: «Buscar por calles» no aparece y
  «Paradas cercanas» pide a geoserver una caja alrededor de la posición
  redondeada.

## Agregar ruta

`_AddRouteDialog` en `lib/ui/stops_page.dart`. Al buscar la parada, la app
pide `/v1/stops/{id}` y, en paralelo, sus arribos.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Nombre de la parada | `StopDetails.displayName` | `name` | `descripcion` |
| Chips LÍNEAS | `StopDetails.lines` | `lines` | `lineas[].descripcion` |
| Chips HACIA | los destinos de `StopDetails.directions` de las líneas elegidas, cada uno con la unión de sus `variantIds` | `directions[].destination`, `directions[].variantIds` | IM `linevariants`: `destination` y `lineVariantId` de cada `cod_variante` del WFS |
| Chips HACIA de respaldo, para una línea sin `directions` | `BusArrival.destination` y `variantId` de los arribos de ese momento | `arrivals[].destination`, `arrivals[].variantId` | `destino`, `variante` |
| Al guardar | `RouteAlert.originName`, `preferredLines`, `preferredDestinations`, `preferredVariantIds` | – | – |

- Los chips HACIA van ordenados por destino, en orden de unidades de código.
- En modo directo `directions` viene siempre vacío, así que todos los chips
  HACIA salen de los ómnibus que vienen en ese momento.

## Estoy esperando

### La hoja

`_showWaitSheet` en `lib/ui/stops_page.dart`, al tocar una fila que no es
estimada.

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| `CartelTira` (fila con GPS): línea, destino, minutos o LLEGANDO | `BusArrival.line`, `destination`, `etaMinutes` | `line`, `destination`, `etaMinutes` | `linea`, `destino`, `minutos` |
| Fila sin GPS: «116 → POCITOS» | `line`, `destination` | `line`, `destination` | `linea`, `destino` |
| «SAN JOSE y ANDES · con GPS» | nombre de la tarjeta: `BusStop.name` o `RouteAlert.originName` (guardado) | – | – |
| «Según horario 20:01, sin GPS todavía · SAN JOSE y ANDES» | `etaLabel` (`clockTime`) y el nombre de la tarjeta | `clockTime` | `horaDesc` |

### El seguimiento

`BusWait.forTrip` (`lib/models/bus_wait.dart`) guarda del viaje elegido
`tripId`, `variantId`, `line`, `destination` y `expectedAt`. En cada consulta,
`BusWait.check` lo busca por `tripId`; si no está (un viaje de horario cambia
de `sched-…` a `bus-…` cuando aparece su GPS), toma el del mismo `variantId`
(o, si falta, de la misma línea y destino) con el `expectedAt` más cercano, a
menos de 10 min, y adopta su `tripId` y su `expectedAt`.

`expectedAt` queda en el reloj de la fuente, para compararlo con el de los
arribos. Para «ya pasó» y el recordatorio de iOS se usa
`BusWait.expectedOnPhone`: `expectedAt` más `clockOffset`, la hora del
teléfono menos el `fetchedAt` del tablero, que `check` mide con cada tablero
(al empezar, `_showWaitSheet` le pasa la del tablero de la fila). Así un
teléfono con la hora corrida no termina la espera ni avisa antes de tiempo.

### Aviso fijo (Android) y recordatorio (iOS)

| Qué se ve | Modelo | Campo /v1 | Fuente |
|---|---|---|---|
| Android, título: «Esperando el 116 → POCITOS» | `BusWait.title`: `line`, `destination` | `line`, `destination` del viaje elegido | `linea`, `destino` |
| Android, texto: «Llega en 4 min · SAN JOSE y ANDES» | `BusWait.statusText`: `etaMinutes` y `stopName` | `etaMinutes` | `minutos` |
| Android, texto: «Llegando · …» | `etaMinutes <= 0` con GPS | `etaMinutes` | `minutos` |
| Android, texto: «Según horario 20:01, sin GPS todavía · …» | `etaLabel` | `clockTime` | `horaDesc` |
| Android, texto: «Sin datos del ómnibus por ahora · …» | el viaje no está en la respuesta | – | – |
| Android, texto: «Sin conexión, reintentando… · …» | el pedido falló | – | – |
| iOS: recordatorio «Línea 116 — ~5 min» | `BusWait.expectedOnPhone` menos `alertMinutes` | `expectedAt`, `fetchedAt` | `time` |

En Android, `BusWaitTaskHandler` pide los arribos cada 30 s
(`pollInterval`). En iOS no hay consultas de fondo: el recordatorio se
programa para `expectedOnPhone − alertMinutes` y se mueve cada vez que la
app recibe un tablero nuevo de esa parada. Cuando el ómnibus está cerca sale
el aviso de parada de la sección siguiente.

## Avisos de fondo

`BackgroundWorker.checkAlerts` (`lib/services/background_worker.dart`), cada
15 min o más, con un solo `getBoards` para todas las paradas y rutas que están
en su horario. Solo avisa por ómnibus con GPS (`isRealTime`) cuyo
`etaMinutes` es igual o menor que el umbral del aviso. Una parada que no se
pudo consultar no da ningún aviso.

| Aviso | Título | Texto | De dónde sale |
|---|---|---|---|
| Parada | «Línea 116 — 4 min»; con 0 min, «Línea 116 — llegando» | «Tu ómnibus llega en 4 min a SAN JOSE y ANDES»; con 1 min o menos, «Tu ómnibus está llegando a SAN JOSE y ANDES» | `line` ← `linea`; `etaMinutes` ← `minutos`; nombre ← `BusStop.name` (guardado) |
| Ruta | «Línea 116 → Trabajo» | «Sale en 4 min desde SAN JOSE y ANDES»; con 1 min o menos, «Tu ómnibus está llegando a SAN JOSE y ANDES» | `line`, `etaMinutes`; `RouteAlert.destinationName` y `originName` (guardados); además `RouteAlert.accepts` |

## Widget de Android

`WidgetFeed` (`lib/services/home_widget_feed.dart`) escribe las claves y
`MVDTransporteWidgetProvider.kt` las lee. Muestra la primera ruta activa, a
cualquier hora, con el primer ómnibus de su parada de origen que pasa
`RouteAlert.accepts`, tenga GPS o no. Lo escriben la tarea de fondo (cada
15 min o más) y la app después de cada refresco que incluye esa parada.
Cuando no queda ninguna ruta activa, `BackgroundWorker.sync()` lo vacía en el
acto, aunque quede una alerta de parada.

| Qué se ve | Clave | Modelo | Campo /v1 | Fuente |
|---|---|---|---|---|
| Línea | `route_line` | `BusArrival.line` | `line` | `linea` |
| Destino | `route_dest` | `destination`; si está vacío, `RouteAlert.destinationName` | `destination` | `destino` |
| «~20:01» | `route_eta_at` | `clockTime` | `clockTime` | `horaDesc` |
| La fila se oculta 2 min después de esa hora, en el reloj del teléfono | `route_expected_at_ms` | `expectedAt` más la hora del teléfono al consultar, menos `fetchedAt` | `expectedAt`, `fetchedAt` | `time` |
| – (compatibilidad) | `route_eta_min` | `etaMinutes` | `etaMinutes` | `minutos` |
| – (Kotlin no la lee) | `route_checked_at_ms`, `route_status` | hora del tablero; `ok`, `none`, `offline` u `off` | – | – |

Sin fila, el widget muestra «Sin próximos ómnibus en tus rutas». Los estados
y la caducidad están en [10-superficies.md](10-superficies.md).

## Pantallas sin datos de /v1

- **Servicios**: enlaces fijos que se abren en el navegador
  (`lib/services/official_sites.dart`).
- **Info**: textos fijos; «FUENTE DE DATOS» depende del modo: el párrafo del confort y el del
  servidor del proyecto aparecen solo con proxy (`MvdApiService.usesProxy`).
- **Privacidad**: el texto de `docs/privacy-policy.md`, que viene dentro de la app.
- **Bloqueo**: no muestra datos.

Los enlaces del navegador (Cómo Ir, Mi STM, Recarga) no son pedidos de la
app.

## Campos /v1 que no se ven

| Campo | Para qué lo usa la app |
|---|---|
| `arrivals[].tripId` | seguir el viaje de «Estoy esperando» y marcar la fila esperada; en el Mapa, reconocer un ómnibus que va a dos paradas |
| `arrivals[].variantId` | filtro de rutas (`preferredVariantIds`), seguimiento, chips HACIA de respaldo |
| `arrivals[].expectedAt` | filas estimadas, seguimiento, recordatorio de iOS, caducidad del widget |
| `fetchedAt` de los arribos | «Datos de las H:MM» y, en Mis paradas y en el Mapa, el «ahora» de la fuente para sacar filas estimadas vencidas (las edades, 1 y 5 min, se cuentan desde que el tablero llegó al teléfono). En el widget y en «Estoy esperando», la diferencia entre el reloj del teléfono y el de la fuente, para pasar `expectedAt` al reloj del teléfono. En el Mapa, además: cuál de dos tableros de una parada es el más nuevo y de qué tablero sale la posición de un ómnibus que va a dos paradas; el «tablero de menos de 30 s» también se cuenta desde que llegó al teléfono |
| `id` de la parada y de los arribos | ninguno: `V1Parser` usa el número pedido |
| `directions[].variantIds` | se guardan en `RouteAlert.preferredVariantIds` |
| `stops[].location` | la distancia en «Paradas cercanas»; se guarda en la parada elegida (`BusStop.latitude`, `longitude`) y, con proxy, completa la de una parada guardada sin ubicación: es su lugar en el Mapa |
| `linesAvailable` | ninguna pantalla lo usa; `MvdApiService.getStopCatalog` no deja que un catálogo sin líneas reemplace una copia con líneas, y lo guarda solo 15 min |
| `fetchedAt` del catálogo, de novedades y de GPS | ninguno: el catálogo se guarda con la hora del teléfono (corrida hacia atrás si vino sin líneas, para que venza a los 15 min) |
| `passes[].hhmm` | encabezados de hora y «Después de medianoche» |
| `operators[].partial` | decide si aparece el aviso de GPS |
| `news[].id` | NUEVA, el número sobre la pestaña y la mezcla con la copia guardada |

## Lo que queda guardado en el teléfono

| Qué | Dónde | De dónde sale | Cuándo cambia |
|---|---|---|---|
| Nombre, líneas y ubicación de una parada | `BusStop` (caja `stops`) | `/v1/stops/{id}` al escribir el número (sin ubicación), o la fila del catálogo o de «Paradas cercanas» (con ubicación) | Una parada guardada sin conexión como «Parada N», sin líneas: `healPlaceholderStops` la completa al abrir Mis paradas. Una parada sin ubicación: `StopLocationsService` se la busca al abrir el Mapa, del catálogo con proxy o de geoserver sin proxy |
| Origen, líneas y direcciones de una ruta | `RouteAlert` (caja `routes`) | `/v1/stops/{id}` y, de respaldo, `/v1/stops/{id}/arrivals` al guardar | Nunca. Una ruta guardada sin conexión queda con «Parada N» de origen |
| El viaje esperado | `BusWait` | el elemento de `arrivals` elegido | En cada consulta adopta el `tripId` y el `expectedAt` del viaje encontrado |
| Novedades | `news_cache` (caja `settings`) | `/v1/news` | En cada refresco (cada 10 min como mucho; 30 s al deslizar) |
| Catálogo | caja perezosa `catalog` | `/v1/catalog/stops`, el cuerpo tal como llegó | Una vez por día, cuando se usa; uno sin líneas, a los 15 min, y nunca encima de una copia con líneas |
| Fila del widget | claves de `home_widget` | `/v1/stops/{id}/arrivals` del origen de la primera ruta | En cada tarea de fondo y en cada refresco de la app que incluye esa parada; se borra apenas no queda ninguna ruta activa |
