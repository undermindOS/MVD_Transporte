# Pantallas

Cada pantalla de la app: qué muestra, en qué estados puede estar (cargando, error, vacío, datos
viejos, con datos), de dónde sale cada dato y cuándo se vuelve a pedir. Todo está revisado
contra el código; donde el código todavía no hace lo que debería, la sección final lo dice.

Ver también:
- [07-textos.md](07-textos.md): el texto exacto de cada estado y cada error.
- [08-componentes.md](08-componentes.md): las piezas de cada pantalla y qué campo muestra cada una.
- [pantalla-a-datos.md](pantalla-a-datos.md): de cada dato en pantalla hasta su campo en la fuente.
- [contrato-v1.md](contrato-v1.md): las rutas `/v1`, la caché del proxy, los errores y el modo
  directo.
- [10-superficies.md](10-superficies.md): widget, notificaciones y el aviso fijo de «Estoy
  esperando».
- [11-accesibilidad.md](11-accesibilidad.md): lo que escucha el lector de pantalla en cada una.

## Árbol de pantallas

```
Bloqueo (AppLock, LockScreen) tapa toda la app mientras falta autenticar
HomePage                      barra buildTimbreAppBar + botón «Info»
├── Mis paradas (StopsPage)   pestaña inferior 1
│   ├── Paradas               subpestaña; botón + → Agregar parada
│   ├── Rutas                 subpestaña; botón + → Agregar ruta
│   └── Novedades             subpestaña; el detalle se abre en una hoja
├── Mapa (MapaPage)           pestaña inferior 2; se arma la primera vez que se elige
└── Servicios (ServicesPage)  pestaña inferior 3

Páginas que se abren encima:  Horarios (SchedulePage), Info (InfoPage) → Privacidad
                              (PrivacyPolicyPage)
Diálogos:                     Agregar parada, Agregar ruta
Hojas:                        Estoy esperando, Ajustes de aviso, detalle de novedad,
                              un ómnibus y una parada del Mapa
```

- `HomePage` (`lib/ui/home_page.dart`) tiene tres pestañas en la `NavigationBar`: «Mis paradas»
  (ícono `bus`), «Mapa» (ícono `streets`) y «Servicios» (ícono `grid`). La elegida lleva el ícono
  encendido (`glow`). Un `IndexedStack` guarda el estado de las tres: cambiar de pestaña no borra
  los arribos cargados, la subpestaña elegida ni la cámara del Mapa.
- Mi STM, Recarga, Avisos y Cómo Ir no son pestañas: son sitios oficiales y se abren en el
  navegador (`OfficialSite` en `lib/services/official_sites.dart`). La pestaña Mapa es propia: no
  abre Cómo Ir.
- La barra de todas las pantallas, menos la de bloqueo, es `buildTimbreAppBar` (ver
  [08-componentes.md](08-componentes.md)).
  En `HomePage` lleva el botón «Info»; Horarios, Info y Privacidad llevan la flecha para volver.
- Mis paradas tiene tres subpestañas en un `TabBar` (íconos `stop`, `route` y `news`, de 22 px).
  La de Novedades lleva un contador de novedades sin leer. El botón + dice «Agregar parada» en
  Paradas y «Agregar ruta» en Rutas; en Novedades no aparece.

## Cuándo se pide cada dato

| Dato | Cuándo se pide | Dónde queda | En el código |
|---|---|---|---|
| Arribos de una parada (`GET /v1/stops/{id}/arrivals`) | al arrancar la app; cada 30 s mientras Mis paradas está a la vista; al volver a estar a la vista; al deslizar para actualizar; al agregar una parada o una ruta (solo esa parada). Las paradas guardadas, también cada 30 s mientras el Mapa está a la vista y al abrirlo o volver a él, salvo que todas tengan un tablero de menos de 30 s | memoria: el último tablero bueno, cuándo llegó según el reloj del teléfono y el último fallo de cada parada (`_BoardView`); además, el tablero más nuevo de cada parada, venga de donde venga, que lee el Mapa (`MvdApiService.latestBoards`) | `StopsPage.autoRefreshInterval`, `_refresh`; `MapaPage._refresh` |
| Estado del GPS (`GET /v1/status/gps`) | junto con los arribos: al arrancar la app, en cada vuelta de 30 s y al deslizar; como mucho una vez por minuto | memoria; después de un fallo queda el último estado bueno | `BusStatusService.minInterval` |
| Novedades (`GET /v1/news`) | al arrancar la app, si pasaron 10 min desde la última vez; al deslizar en Novedades, si pasaron 30 s | Hive, hasta 30 novedades | `TransportNewsService.minInterval`, `forcedMinInterval` |
| Horario (`GET /v1/stops/{id}/schedule/{day}/{H:MM}`) | al abrir Horarios y con cada cambio de día o de hora | memoria, 6 h por parada, día y hora | `MvdApiService._scheduleTtl` |
| Datos de una parada (`GET /v1/stops/{id}`) | al agregar una parada por número; al buscar la parada en Agregar ruta; al arrancar la app, para las paradas guardadas como «Parada N» | Hive, dentro de la parada o la ruta guardada | `MvdApiService.getStopDetails`, `healPlaceholderStops` |
| Catálogo de paradas (`GET /v1/catalog/stops`, solo con proxy) | en Agregar parada: con la primera letra en «Buscar por calles» o al tocar «Paradas cercanas»; al abrir el Mapa con una parada guardada sin ubicación | Hive (caja `catalog`), 1 día; uno sin líneas, 15 min, y nunca reemplaza una copia con líneas; sin red se usa la copia vieja, tenga la edad que tenga | `MvdApiService._catalogTtl`, `getStopCatalog` |
| Ubicación de una parada guardada que no la tiene (con proxy, del catálogo; sin proxy, un pedido a geoserver por parada, por su número) | al abrir el Mapa o volver a él; como mucho una vez cada 10 min por parada, la encuentre o no | Hive, dentro de la parada guardada (`BusStop.latitude`, `longitude`) | `StopLocationsService.fillMissing`, `retryInterval` |

«Al arrancar la app» es cuando se arma `StopsPage`: al abrir la app o, con el bloqueo encendido,
después del primer desbloqueo (ver «Bloqueo»). Los desbloqueos siguientes no la vuelven a armar. El
`IndexedStack` la arma aunque la pestaña elegida sea otra. El Mapa, en cambio, se arma recién la
primera vez que elegís su pestaña, y después queda armado: antes no carga ni pide nada.

Sin proxy las mismas llamadas van a los servicios de la Intendencia y el teléfono convierte la
respuesta a /v1. No hay catálogo, y las paradas cercanas y la ubicación de las paradas del Mapa
salen de geoserver. El detalle está en [contrato-v1.md](contrato-v1.md).

### Los 30 s: solo con Mis paradas o el Mapa a la vista

El temporizador de `StopsPage` corre solo si se cumplen las cuatro cosas:

- la pestaña inferior elegida es Mis paradas. Cualquiera de sus subpestañas sirve: en Rutas y en
  Novedades también se refrescan todos los tableros;
- no hay una página encima. `HomePage.routeObserver` (registrado en `lib/main.dart`) avisa
  cuando se abre Horarios o Info, y `HomePage` le pasa `active: false` a `StopsPage`;
- la app no está bloqueada: `HomePage` lee `AppLock.of(context).locked`;
- la app está en primer plano.

El del Mapa (`MapaPage`) pide las mismas cuatro cosas, con la pestaña Mapa en lugar de Mis
paradas, y además que haya alguna parada guardada. `HomePage` también lo envuelve en
`TickerMode`: fuera de la vista no se anima nada, porque el `IndexedStack` deja andar las
animaciones de una pestaña escondida.

| Situación | Mis paradas | Mapa |
|---|---|---|
| Otra pestaña elegida | se pausan | se pausan; antes de elegirla por primera vez, `MapaPage` todavía no existe |
| Horarios o Info abiertos | se pausan | se pausan |
| App en segundo plano (`hidden`, `paused`) | se pausan | se pausan |
| App bloqueada | se pausan; antes del primer desbloqueo `StopsPage` todavía no existe | se pausan |
| Diálogo u hoja abiertos (en Mis paradas: Agregar parada, Agregar ruta, Estoy esperando, Ajustes de aviso, detalle de novedad; en el Mapa: un ómnibus o una parada) | siguen: el tablero queda a la vista y solo cuentan las páginas enteras | siguen, y la hoja abierta se actualiza con cada tablero |
| Un diálogo del sistema que deja la app `inactive` (por ejemplo, un pedido de permiso) | siguen | siguen |
| Vuelve a estar a la vista | un refresco enseguida y después cada 30 s (`_resumeAutoRefresh`) | lee de nuevo las paradas guardadas, busca la ubicación de las que no la tienen y pide los tableros enseguida, salvo que todas las paradas tengan uno de menos de 30 s (por ejemplo, recién actualizadas en Mis paradas); después, cada 30 s (`_resume`) |
| La vuelta anterior todavía no terminó (red lenta) | esa vuelta se saltea (`_autoRefreshing`) | esa vuelta se saltea (`_refreshing`) |
| Sin paradas guardadas | — | no hay temporizador ni mapa base |

Al volver del segundo plano, además, `BusWaitService.sync()` revisa si «Estoy esperando»
terminó mientras tanto. El refresco de esa vuelta espera al primer cuadro
(`WidgetsBinding.endOfFrame`), en Mis paradas y en el Mapa: si la app se bloquea al volver, ese
cuadro ya deja la pantalla fuera de la vista y no se pide nada.

### Un pedido por parada

`MvdApiService.getBoards` pide cada parada una sola vez y todas en paralelo. Si una parada
guardada es también el origen de una ruta, las dos tarjetas leen el mismo tablero. Si una
parada ya se está pidiendo, el pedido nuevo espera ese mismo resultado. Una parada que falla no
frena a las demás, tampoco sin proxy cuando su respuesta no se puede convertir. Deslizar para
actualizar pide solo las paradas de su subpestaña: las paradas guardadas en Paradas, los orígenes
en Rutas. Cada tablero que llega bien queda en `MvdApiService.latestBoards`, el más nuevo por
parada: el Mapa dibuja también los que pidió Mis paradas.

### Demasiados pedidos: `Retry-After`

- Ante un 429 del proxy, la capa de datos devuelve `ApiFailure.busy` con `retryAfter`, que sale
  del encabezado `Retry-After` (60 s si no viene).
- `StopsPage` saltea las vueltas del temporizador hasta que pasa el `retryAfter` más largo de
  esa tanda (`_skipTicksUntil`). No muestra ningún mensaje y la tarjeta queda como estaba. El
  Mapa hace lo mismo, con su propio `_skipTicksUntil`.
- `MvdApiService` además deja de mandar pedidos, en todas las rutas menos el catálogo, hasta que
  pasa ese tiempo (`_busyUntil`): contesta `busy` sin tocar la red. Deslizar para actualizar y
  volver a la pantalla no esperan el salto de vueltas, pero sí este freno.
- El 503 `upstream_busy` del catálogo también llega como `busy`, pero no frena las otras rutas
  (`backOff: false`). El catálogo usa entonces la copia guardada.

### Fuera de la pantalla

Lo que se pide con la app cerrada está en [10-superficies.md](10-superficies.md). En resumen:

- **Estoy esperando.** En Android, un servicio en primer plano pide los arribos cada 30 s,
  también con la pantalla apagada. En iOS, un recordatorio a la hora estimada que se corre con
  cada refresco de la app abierta (`BusWaitService.onArrivals`).
- **Avisos de parada y de ruta.** WorkManager cada 15 min o más (`BackgroundWorker`, con red y
  batería no baja), solo mientras haya algún aviso encendido.
- **Widget.** Lo actualizan la revisión en segundo plano y cada refresco de la app que incluye el
  origen de la primera ruta encendida. Se vacía apenas no queda ninguna ruta encendida.

El proxy guarda los arribos 15 s en su caché, así que un tablero puede llegar hasta 15 s más
viejo que el pedido. Los tiempos de caché de cada ruta están en [contrato-v1.md](contrato-v1.md).

## Estados en común

- **Cargando.** Un indicador de progreso ámbar, sin texto. El único texto de espera es «Buscando
  parada…».
- **Error.** Dice qué falló y qué hacer ([07-textos.md](07-textos.md)). Dentro de una tarjeta,
  de una hoja o debajo de un campo va en `rojoLed`; sobre una lista o un mapa que se siguen
  viendo, en el panel `avisoNoche`; después de una acción, en un snack bar.
- **Vacío.** Un cartel de `TimbreEmptyState` («SIN PARADAS», «SIN RUTAS», «SIN NOVEDADES»,
  «SIN PASADAS») con una frase que dice qué hacer.
- **Datos viejos.** Los marcan Mis paradas y el Mapa. Mis paradas, después de un fallo, deja hasta
  5 min las últimas filas como estimados «~H:MM», nunca en ámbar. Sin fallo, un tablero que llegó
  hace 1 min o más también pasa a estimados, y desde los 5 min la tarjeta vuelve al indicador de
  carga. El Mapa deja sus ómnibus sin encender con las mismas edades y los saca a los 5 min.
  Novedades muestra lo guardado debajo del panel de error. Horarios, el catálogo y el estado del
  GPS usan su copia guardada sin decirlo.

## Mis paradas: Paradas

Código: `_buildStopsTab`, `_buildStopCard`, `_buildArrivals` y `_buildRows` en
`lib/ui/stops_page.dart`.

Una lista de tarjetas, una por parada guardada, en orden de número de parada (la clave de la caja
Hive). Si algún operador manda GPS de menos del 70 % de sus ómnibus, arriba de todo va el aviso de
GPS parcial. Cada tarjeta es un tablero chico: nombre y número, el botón de Horarios, la campana,
la fila del aviso si está encendido, los próximos ómnibus y «Ver en Cómo Ir».

| Estado | Qué se ve |
|---|---|
| Ninguna parada guardada | el cartel «SIN PARADAS» con «Tocá + para agregar una parada y recibir un aviso cuando llegue el ómnibus.»; sin aviso de GPS y sin deslizar para actualizar |
| Cargando | el encabezado de la tarjeta ya se ve; donde van las filas, un indicador de 18 px. Pasa mientras la tarjeta no tiene ningún tablero y, sin fallo, cuando el último tablero llegó hace 5 min o más o ya no le queda ninguna fila estimada |
| Con datos | hasta 3 filas `ArrivalRow`; con más, «Ver las N» muestra hasta 6 y «Ver menos» las vuelve a ocultar |
| Ningún ómnibus | «Sin ómnibus próximos» en `tenue`, con el ícono del ómnibus |
| Falló y no hay datos de menos de 5 min | nota roja «No se pudo actualizar. Deslizá para reintentar» |
| Datos viejos: falló y hay un tablero de menos de 5 min | nota roja «No se pudo actualizar. Datos de las 19:52. Deslizá para reintentar.» y debajo las filas estimadas «~H:MM». Las que debían pasar hace más de 1 min no aparecen. No se pueden tocar |
| Datos viejos sin fallo: el último tablero llegó hace 1 min o más, y menos de 5 | sin nota, las filas estimadas «~H:MM», también sin las que debían pasar hace más de 1 min. No se pueden tocar. Pasa al volver de Horarios, Info o Servicios hasta que llega el tablero nuevo, o mientras el proxy contesta 429 |
| La parada ya no existe (`notFound`) | nota roja «Esta parada ya no existe. Deslizá la tarjeta para borrarla.», sin filas |
| Demasiados pedidos (`busy`) | nada cambia; si todavía no había tablero, sigue el indicador. El tablero que queda envejece: a 1 min pasa a estimados y a 5 min, al indicador |
| GPS parcial | el panel `avisoNoche` arriba de la lista |

Después de un fallo, la edad del tablero se mide con `ArrivalsBoard.fetchedAt` contra el reloj del
teléfono. Sin fallo se mide desde que llegó al teléfono (`_BoardView.receivedAt`, con
`StopsPage.clock`): `fetchedAt` es la hora del servidor, que puede estar corrida o venir de la
caché del borde.

| En pantalla | Modelo | De dónde sale |
|---|---|---|
| nombre y número | `BusStop.name`, `BusStop.id` | Hive (caja `stops`); el nombre se guardó desde /v1 `name` o desde el catálogo |
| campana y fila del aviso | `notificationsEnabled`, `etaAlertMinutes`, `schedule` | Hive; solo en el teléfono |
| filas | `ArrivalsBoard` de esa parada | `GET /v1/stops/{id}/arrivals` |
| fila del ómnibus que esperás | `BusWaitService.current` y `BusWait.follows` | el viaje que elegiste en «Estoy esperando», seguido por `tripId` |
| aviso de GPS parcial | `List<OperatorGpsStatus>` | `GET /v1/status/gps` |

Qué se puede hacer:

- **+** abre Agregar parada.
- **Reloj** abre Horarios de esa parada.
- **Campana** enciende o apaga el aviso. Al encenderlo, la app pide permiso de notificaciones y
  registra la revisión en segundo plano; al apagar el último aviso, la cancela (`_syncAlerts`).
- **Fila del aviso** («Aviso 5 min antes · Siempre») abre los Ajustes de aviso.
- **Fila de un ómnibus** abre Estoy esperando. Las filas estimadas no se pueden tocar.
- **«Ver en Cómo Ir»** abre la parada en el navegador.
- **Deslizar a la izquierda**, o la acción «Borrar» del lector de pantalla, borra la tarjeta sin
  pedir confirmación.

## Mis paradas: Rutas

Código: `_buildRoutesTab` y `_buildRouteCard` en `lib/ui/stops_page.dart`.

Una ruta es un viaje guardado: una parada de origen, un destino con el nombre que vos le diste y,
si querés, algunas líneas y direcciones. La tarjeta muestra los próximos ómnibus del origen que
sirven para ese viaje (`RouteAlert.accepts`). No hace un pedido propio: lee el tablero del origen.
Las rutas van en el orden en que las creaste.

Los estados son los de Paradas, con estas diferencias:

- Vacío: el cartel «SIN RUTAS» con «Tocá + para guardar una alerta de salida.».
- «Sin ómnibus próximos» aparece también cuando vienen ómnibus pero ninguno pasa el filtro de la
  ruta.
- Si el origen ya no existe, la tarjeta muestra la misma nota de `notFound`.
- La tarjeta no tiene Horarios ni «Ver en Cómo Ir».
- Una ruta nueva se guarda con el aviso encendido, así que al crearla la app pide permiso de
  notificaciones.

| En pantalla | Modelo (`RouteAlert`, Hive) | De dónde sale |
|---|---|---|
| origen | `originName`, `originStopId` | /v1 `name` al crear la ruta; «Parada N» si no había conexión |
| «→ Trabajo» | `destinationName` | lo que escribiste |
| «Líneas: …» y «Hacia: …» | `preferredLines`, `preferredDestinations` | los chips que elegiste en Agregar ruta |
| filtro por variante (no se ve) | `preferredVariantIds` | /v1 `directions[].variantIds` o `variantId` de los arribos |
| campana y fila del aviso | `enabled`, `alertMinutes`, `schedule` | Hive |
| filas | el tablero de `originStopId`, filtrado | `GET /v1/stops/{id}/arrivals` |

## Mis paradas: Novedades

Código: `lib/ui/news_list.dart` (`NewsList`, `showNewsDetail`) y `_loadNews` en
`lib/ui/stops_page.dart`.

Los desvíos y cambios de recorrido que publica la Intendencia, de la más nueva a la más vieja.

| Estado | Qué se ve |
|---|---|
| Cargando, sin nada guardado | un indicador de progreso |
| Cargando, con novedades guardadas | la lista guardada, sin indicador |
| Con datos | una fila por novedad y al pie «Publicadas por la Intendencia de Montevideo (Cómo Ir).» |
| Falló el pedido | el panel `avisoNoche` «No se pudo actualizar. Deslizá para reintentar» y debajo lo guardado; si no hay nada guardado, solo el panel |
| Ninguna novedad | el cartel «SIN NOVEDADES» con «Los desvíos y cambios de recorrido aparecen acá.» (solo si no está cargando y no falló) |

**Sin leer.** Una novedad está sin leer si su `id` es mayor que el último leído
(`TransportNewsService.lastReadId`). Si nunca abriste Novedades, todas están sin leer. El
contador de la subpestaña cuenta las sin leer. Al abrir la subpestaña, la app guarda el `id` más
alto como leído y el contador baja a cero. Las filas siguen marcadas («NUEVA», fondo `tinta`,
fecha encendida) hasta que salís de la subpestaña y volvés, porque la marca se calcula con el
último leído del momento en que la abriste (`_newsReadBefore`).

**Detalle.** Tocar una fila abre una hoja que empieza al 60 % de la pantalla y crece hasta el
90 %: título, fecha «27/10/2026», el texto (HTML seguro con `SafeHtml`, o el resumen si el texto
viene vacío) y, si hay enlace, «Ver más», que lo abre fuera de la app.

| En pantalla | Modelo (`TransportNews`) | De dónde sale |
|---|---|---|
| título, resumen, texto | `title`, `summary`, `body` | `GET /v1/news` → `news[]` |
| fecha | `date`, en la hora del teléfono | `news[].publishedAt` |
| «Ver más» | `link` | `news[].link` |
| sin leer | `id` | `news[].id` contra el último leído, guardado en el teléfono |

Cada respuesta se junta con lo guardado en Hive (hasta 30). Con proxy llegan como mucho 10 por
pedido; sin proxy, la app recorre las páginas de la Intendencia ella misma.

Refresco: al arrancar la app, si pasaron 10 min desde el último pedido; al deslizar, si pasaron
30 s. Si no pasó ese tiempo, la app muestra lo guardado sin pedir nada. El temporizador de 30 s
no pide novedades.

## Horarios

Código: `lib/ui/schedule_page.dart` (`SchedulePage`, `_HourHeader`, `_PassRow`).

Se abre con el reloj de una tarjeta de parada. Muestra el horario teórico de esa parada: unas 50
pasadas desde la hora elegida, sin GPS. Es lo mismo que «Elegir horario» de Cómo Ir.

- **Barra:** «HORARIOS» y debajo el nombre de la parada con « · 574» al final. Un nombre largo
  sigue en las líneas siguientes, hasta cuatro; el número nunca se corta.
- **Tipo de día:** «Hábiles», «Sábados», «Domingos». Arranca en el de hoy (`DayType.of`, que no
  tiene en cuenta los feriados).
- **«Desde H:MM»:** arranca en la hora actual redondeada hacia abajo a 5 min. El selector de hora
  fuerza 24 horas.
- **Nota fija:** «Horarios teóricos, sin ubicación GPS».

| Estado | Qué se ve |
|---|---|
| Cargando | un indicador de progreso en el centro |
| Falló | ícono `warning` en `rojoLed`, «No se pudo cargar el horario. Revisá la conexión.» y el botón «Reintentar» |
| Ninguna pasada | el cartel «SIN PASADAS» con «Probá con otro día o con una hora más temprano.» |
| Con datos | encabezados de hora («20 h»), las filas («23:31», línea, destino) y, si la lista pasa la medianoche, «Después de medianoche» |
| Datos viejos | una respuesta guardada de hasta 6 h se muestra sin indicarlo: el horario teórico casi no cambia |

| En pantalla | Modelo (`ScheduledPass`) | De dónde sale |
|---|---|---|
| hora | `time` | `GET /v1/stops/{id}/schedule/{day}/{H:MM}` → `passes[].time` |
| línea y destino | `line`, `destination` | `passes[].line`, `passes[].destination` |
| encabezados y medianoche | `hhmm` | `passes[].hhmm` |
| nombre y número de la parada | `BusStop.name`, `BusStop.id` | la parada guardada |

Refresco: al abrir y con cada cambio de día o de hora. Si cambiás rápido, la app descarta las
respuestas de pedidos anteriores (`_request`). No hay refresco automático. Mientras Horarios está
abierto, Mis paradas no se refresca.

Sin proxy el pedido va a `transporteRest/siguientesParada/{id}/{HABIL|SABADO|DOMINGO}/{H:MM}`.

## Agregar parada

Código: `_AddStopDialog` y `_addStop` en `lib/ui/stops_page.dart`.

Un diálogo con tres caminos: escribir el número, buscar por calles (solo con proxy) o elegir una
de las paradas cercanas. Se ve una sola lista a la vez: escribir en «Buscar por calles» borra las
cercanas, y tocar «Paradas cercanas» borra la búsqueda.

**Número.** El campo acepta solo cifras, hasta 7. Al tocar «Agregar», el diálogo se cierra y la
app sigue así:

| Situación | Qué pasa |
|---|---|
| El número no puede existir (0 o solo ceros) | snack bar «No existe la parada 0. Revisá el número.», sin pedido |
| La parada ya está guardada | snack bar «La parada 574 ya está guardada» |
| Se está buscando | snack bar «Buscando parada…» |
| La encontró | se guarda con nombre y líneas, y se pide su tablero |
| No existe (`notFound`) | snack bar «No existe la parada 574. Revisá el número.» |
| Cualquier otro fallo (sin red, `busy`, `timeout`) | se guarda como «Parada 574», sin mensaje; un arranque posterior le pone el nombre (`healPlaceholderStops`) |

**Buscar por calles** (solo si la app tiene `MVD_PROXY_URL`):

| Estado | Qué se ve |
|---|---|
| Cargando el catálogo | un indicador de progreso debajo del campo |
| No se pudo cargar | «No se pudo cargar la lista de paradas. Revisá la conexión.» en `rojoLed` |
| Ninguna coincide | «Ninguna parada coincide» |
| Coincidencias | hasta 50 filas («#574» debajo del nombre); con más, «Hay más de 50: agregá la otra calle» |

**Paradas cercanas:**

| Estado | Qué se ve |
|---|---|
| Buscando | el botón desactivado y un indicador de progreso |
| Ubicación apagada, permiso negado, permiso negado para siempre, sin posición, sin red | el mensaje de cada caso en `rojoLed` ([07-textos.md](07-textos.md)); con el permiso negado para siempre, el botón «Abrir ajustes» |
| Ninguna a menos de 400 m | «No hay paradas a menos de 400 m» |
| Con datos | las paradas a menos de 400 m, de la más cerca a la más lejos («#5109 · 48 m · 124, 125») |

Elegir una parada de cualquiera de las dos listas la guarda en el acto con el nombre, las líneas
y la ubicación de la lista, sin otro pedido, y después se pide su tablero.

| Dato | Con proxy | Sin proxy |
|---|---|---|
| nombre y líneas de un número escrito | `GET /v1/stops/{id}` | `transporteRest/lineas/{id}`, convertido a /v1 en el teléfono |
| búsqueda por calles | el catálogo `GET /v1/catalog/stops`, filtrado en el teléfono (`MvdApiService.searchStops`) | no existe: el campo no aparece |
| paradas cercanas | el mismo catálogo; la distancia se calcula en el teléfono y la ubicación no sale de él | la capa WFS de geoserver, pedida para un cuadrado alrededor de la posición redondeada a 3 decimales (472 m de medio lado) y filtrada en el teléfono con la posición exacta |

Si el proxy contesta el catálogo con `linesAvailable: false`, ese catálogo nunca reemplaza una
copia guardada que tiene líneas: la app sigue con esa copia. Sin una copia con líneas, las filas
salen sin líneas y el catálogo nuevo se guarda solo 15 min, como en el proxy: después se vuelve a
pedir.

## Agregar ruta

Código: `_AddRouteDialog` y `_addRouteManually` en `lib/ui/stops_page.dart`.

Un diálogo con dos campos obligatorios, «Parada de origen *» y «Destino *» (lo que escribas,
por ejemplo «Trabajo»), y debajo los chips para elegir líneas y direcciones.

| Estado | Qué se ve |
|---|---|
| Antes de buscar | «Buscá la parada para elegir sus líneas» |
| Buscando (lupa «Ver líneas» o la tecla de buscar) | un indicador de progreso |
| La parada no existe | «No existe la parada 574. Revisá el número.» en `rojoLed` |
| Otro fallo | «No se pudieron cargar las líneas. Revisá la conexión.» en `rojoLed` |
| Encontrada | el nombre de la parada, los chips «LÍNEAS», los chips «HACIA» (si hay direcciones) y «Si no elegís ninguna, se incluyen todas.» |

- Cambiar el número borra los chips: eran de la parada anterior (`_reset`).
- Si llega la respuesta de un número que ya cambiaste, se descarta.
- «Guardar» necesita número y destino; si falta alguno, no hace nada.
- Si guardás sin haber buscado, la app busca la parada al cerrar («Buscando parada…»). Si no
  existe, avisa con un snack bar; si falla la red, el origen queda como «Parada 574».
- Después de guardar se pide el tablero del origen y se registra la revisión en segundo plano.

| Dato | Modelo | De dónde sale |
|---|---|---|
| nombre del origen | `StopDetails.displayName` → `RouteAlert.originName` | `GET /v1/stops/{id}` → `name` |
| chips LÍNEAS | `StopDetails.lines` → `preferredLines` | `lines` |
| chips HACIA | `StopDetails.directions`, agrupadas por destino → `preferredDestinations` y `preferredVariantIds` | `directions[]`; para una línea sin direcciones, `destination` y `variantId` de `GET /v1/stops/{id}/arrivals` |

Los dos pedidos salen en paralelo: así el diálogo espera una sola vuelta, aunque las direcciones ya
cubran todas las líneas. Sin proxy `directions` viene siempre vacío y los chips HACIA salen de los
arribos.

## Estoy esperando

Código: `_showWaitSheet` en `lib/ui/stops_page.dart`; `BusWaitService` en
`lib/services/bus_wait_service.dart`; `BusWait` en `lib/models/bus_wait.dart`.

Se abre al tocar una fila de un tablero. Sirve para que la app te avise cuando el ómnibus que vas
a tomar está cerca.

- **Ómnibus con GPS:** el cartel `CartelTira` con línea, destino y minutos, y debajo «SAN JOSE y
  ANDES · con GPS».
- **Ómnibus sin GPS:** «121 → PUNTA CARRETAS» como texto, y debajo «Según horario 20:17, sin GPS
  todavía · SAN JOSE y ANDES».
- «Avisarme cuando falten», el selector «3 min», «5 min», «10 min» (5 por defecto) y el botón
  «Avisarme cuando llegue».
- Una nota según la plataforma: en Android, el aviso fijo que sigue al ómnibus con la pantalla
  apagada; en iOS, el aviso a la hora estimada que se ajusta si abrís la app.
- Si tocaste la fila del ómnibus que ya estás esperando, la hoja muestra solo «Dejar de esperar».

| Resultado | Qué se ve |
|---|---|
| El aviso empezó | snack bar «Te avisamos cuando el 121 esté a 5 min»; la fila se levanta con fondo `tintaAlta` y la campana |
| El ómnibus ya está dentro del margen elegido | snack bar «El 121 ya está a 3 min» |
| No se pudo empezar | snack bar «No se pudo activar el aviso. Revisá que las notificaciones estén permitidas y probá de nuevo.» |
| «Dejar de esperar» | se termina la espera |

Los datos son los del `BusArrival` que tocaste en ese momento (`line`, `destination`,
`etaMinutes`, `clockTime`, `tripId`, `expectedAt`). La hoja no se actualiza mientras está
abierta. La espera sigue al viaje por `tripId` y termina sola a los 60 min
(`BusWait.maxDuration`). Una espera nueva reemplaza a la anterior.

## Ajustes de aviso

Código: `_AlertSettingsSheet` y `_showAlertSettings` en `lib/ui/stops_page.dart`.

Se abre desde la fila «Aviso N min antes · …», que solo aparece con el aviso encendido. Arriba va
el nombre de la parada, o «origen → destino» para una ruta.

- En Android, la nota «Se revisa cada 15 min aprox. y avisa solo por ómnibus con GPS.»; en iOS no
  aparece.
- «Avisarme cuando falten»: «3 min», «5 min» o «10 min».
- «DÍAS»: un chip por día, de «Lu» a «Do».
- «Todo el día» encendido, o «Desde» y «Hasta». Si el aviso era de todo el día y apagás la
  llave, la app propone 7:00 a 9:00.
- «Guardar».

| Estado | Qué se ve |
|---|---|
| Ningún día elegido | «Elegí al menos un día» en `rojoLed` y «Guardar» desactivado |
| «Desde» igual a «Hasta» | «Elegí horas distintas» en `rojoLed` y «Guardar» desactivado |

No pide nada a la red. Lee y guarda en Hive `etaAlertMinutes` y `schedule` de la parada, o
`alertMinutes` y `schedule` de la ruta. Una ventana como 22:00–1:00 pasa la medianoche y cuenta
para el día en que empezó (`AlertSchedule.allows`).

## Mapa

Código: `lib/ui/map/mapa_page.dart` (`MapaPage`), `lib/ui/map/bus_layer.dart` (`BusLayer`),
`lib/ui/map/map_buses.dart` (`MapBuses`), `lib/ui/map/map_sheets.dart` (`BusSheet`,
`StopSheet`) y el mapa base en `lib/services/map/` (`Basemap`).

Un mapa nocturno de Montevideo y alrededores con tus paradas guardadas y los ómnibus con GPS que
vienen a ellas. La barra dice «Mapa», sin subtítulo: el lugar queda para el mapa.

- **Se arma la primera vez que elegís la pestaña** y después queda armada, con la cámara donde la
  dejaste. Antes no carga ni pide nada. La primera vez que se abre en el teléfono, la app copia el
  mapa base a su caché (`Basemap.load`); las siguientes lo abre de ahí.
- **El mapa base viene dentro de la app** (`assets/map/`): moverlo o acercarlo no le pide nada a
  ningún servidor. Va del zoom 10 al 18 del estilo y no gira; el centro de la cámara no sale del
  recorte (`Basemap.bounds`). Apenas hay paradas ubicadas, la cámara las encuadra (margen de 48,
  como mucho el zoom 15, para que se vean las calles por donde llegan los ómnibus); antes, muestra
  el centro (-34.9058, -56.1913) en el zoom 14. Las paradas se ubican de a una, así que cada
  parada que aparece después vuelve a encuadrarlas todas, hasta que movés el mapa: desde ahí la
  cámara es tuya.
- **No usa la ubicación del teléfono.**
- **Las paradas guardadas** que tienen ubicación son el glifo `stop` sobre una baldosa `tinta` de
  26 px con borde `etiquetaCartel`, sin encender, en un área táctil de 44. Tocar una abre su hoja.
- **Los ómnibus con GPS** salen de `arrivals[].location` de los tableros de las paradas guardadas.
  Un ómnibus que viene a dos de tus paradas es uno solo (por su `tripId`,
  `bus-{idEmpresa}-{idBus}`), en la posición de su tablero más nuevo; una fila con GPS sin número
  de ómnibus queda una por parada. Una posición fuera del recorte no se dibuja. Desde el zoom 14
  del estilo cada ómnibus es una píldora con el ómnibus de píxeles y el número de línea; más lejos,
  un punto. Encendido, en `ambar` como `LineBadge(live: true)`; estimado, sin ámbar. Tocar uno
  abre su hoja.
- **Entre un tablero y el siguiente** cada ómnibus se desliza a su posición nueva en 1 s. Con
  «reducir movimiento», o si el Mapa no está a la vista, salta. Un ómnibus nuevo aparece en su
  lugar; uno que ya no está desaparece.
- **«© OpenStreetMap»** abajo a la izquierda, dentro del área segura, siempre a la vista: la
  licencia ODbL lo pide. Tocarlo abre `https://www.openstreetmap.org/copyright` en el navegador
  (`SystemBrowser.open`); si no se puede, el snack bar «No se pudo abrir el navegador. Revisá que
  tengas uno activado.».
- **Con poca memoria** (`didHaveMemoryPressure`) suelta las teselas que tenía decodificadas
  (`Basemap.clearMemoryCache`).

Los datos:

- **Arribos.** Los mismos tableros que Mis paradas (`MvdApiService.getBoards`), cada 30 s
  mientras el Mapa está a la vista (ver «Los 30 s»). Al volver a estar a la vista dibuja enseguida
  lo que ya hay en `MvdApiService.latestBoards` y pide de nuevo, salvo que todas las paradas
  guardadas tengan un tablero de menos de 30 s. Una parada que ya no existe no cambia nada en el
  mapa: lo dice su tarjeta en Mis paradas.
- **Ubicación de las paradas.** Una parada elegida en «Buscar por calles» o en «Paradas cercanas»
  se guardó con su ubicación. Una agregada por número, o guardada antes de que existiera el Mapa,
  no la tiene: al abrir el Mapa o volver a él, `StopLocationsService.fillMissing` la busca, como
  mucho una vez cada 10 min por parada, y la guarda en el teléfono. Con proxy sale del catálogo de
  paradas (`getStopCatalog`, que lo descarga si no está guardado); sin proxy, de geoserver, un
  pedido por parada, por su número (`NearbyStopsService.fetchStop`). Una parada que no se
  encuentra no se dibuja.

| Estado | Qué se ve |
|---|---|
| Sin paradas guardadas | el cartel «SIN PARADAS» de `TimbreEmptyState`, «Sin paradas guardadas» y «Agregá una parada en Mis paradas para ver acá los ómnibus con GPS que se acercan.». No abre el mapa base ni pide nada |
| Abriendo el mapa base | el indicador de progreso de 18 px, sin texto |
| No se pudo abrir el mapa base | ícono `warning` de 24 en `rojoLed`, «No se pudo abrir el mapa. Probá de nuevo.» y el botón «Reintentar»; nunca el texto del error |
| Con datos | las paradas y los ómnibus encendidos |
| Ningún ómnibus con GPS viene a tus paradas | la nota «Ahora ningún ómnibus con GPS viene a tus paradas.», solo con alguna parada ubicada y algún tablero de menos de 5 min |
| No se pudo actualizar ninguna parada | el panel `avisoNoche` «No se pudo actualizar. Revisá la conexión.» con «Reintentar». Los ómnibus de la última vez quedan sin encender hasta 5 min después del `fetchedAt` de su tablero, y después desaparecen |
| Falló solo alguna parada | sin panel: los ómnibus de esa parada, y sus minutos en las hojas, pasan a estimado |
| Demasiados pedidos (`busy`) | nada: el Mapa saltea vueltas hasta que pasa `Retry-After` (60 s si no viene) |
| Sin fallo, un tablero de 1 min o más | sus ómnibus quedan sin encender, sin nota; desde los 5 min desaparecen |
| Paradas que no se pudieron ubicar | la nota «No se pudo ubicar en el mapa la parada 574.»; con dos o más, «No se pudieron ubicar en el mapa 2 paradas.» |

El panel y las notas van juntos en una columna arriba del mapa, dentro del área segura, y la
esquina de «© OpenStreetMap» queda libre. Las notas son un panel `tinta` con borde `lineaNoche`,
ícono y texto en `tenue`.

Las hojas se actualizan con cada tablero mientras están abiertas:

- **Un ómnibus** (`BusSheet`): el `LineBadge`, encendido mientras su tablero está al día, y el
  destino. Debajo, una fila por cada parada guardada a la que va, la más próxima primero: «a la
  parada 574 · SAN JOSE y ANDES» y los minutos con `MinutosEnVivo` (26 px), o el reloj y «~19:56»
  si es un estimado. Si el ómnibus deja de estar en los tableros con la hoja abierta, la hoja se
  queda con lo último, como estimado.
- **Una parada** (`StopSheet`): el nombre, «#574» y hasta 6 filas `ArrivalRow` de su tablero,
  estimadas después de un fallo o con un tablero de 1 min o más. Las filas no se tocan: «Estoy
  esperando» se abre desde Mis paradas. Mientras no hay tablero, el indicador de carga; si la
  parada falló, «No se pudo actualizar. Revisá la conexión.» en `rojoLed`; sin ómnibus, «Sin
  ómnibus próximos».

## Servicios

Código: `lib/ui/services_page.dart`.

Accesos a los sitios oficiales, como tableros chicos. «Tu tarjeta STM»: Mi STM, Recarga y Avisos.
«Para moverte»: Cómo Ir. Al pie, una nota dice que se abren en el navegador, en el sitio oficial,
que la app no ve tu usuario ni tu saldo y que Timbre MVD no es oficial.

- No pide datos a la red: no tiene estados de carga, error ni vacío.
- Cada mosaico abre su sitio en Custom Tabs (Android) o SFSafariViewController (iOS); si no hay
  dónde, en el navegador completo (`SystemBrowser.open`). Si no se pudo abrir: snack bar «No se
  pudo abrir el navegador. Revisá que tengas uno activado.»
- Mientras Servicios está elegido, ni Mis paradas ni el Mapa se refrescan.

## Info

Código: `lib/ui/info_page.dart`.

Se abre con el botón «Info» de la barra. Tarjetas de arriba a abajo:

1. El ícono de la app, el nombre «Timbre MVD» y el aviso «NO OFICIAL» sobre el tablero, con «No
   está afiliada con la Intendencia de Montevideo, el STM ni ninguna empresa de transporte.».
2. «Bloqueo biométrico», con su llave.
3. «FUENTE DE DATOS»: de dónde salen los tiempos de arribo, los horarios, las novedades, el
   estado del GPS y la posición de los ómnibus; de dónde sale el mapa («Mapa: © colaboradores de
   OpenStreetMap, con licencia ODbL. Viene dentro de la app.»), y que los tiempos con reloj son
   horarios teóricos. Solo con proxy (`MvdApiService.usesProxy`) suma dos párrafos: de dónde
   salen los datos de confort («Aire acondicionado y cero emisiones: API de transporte público de
   Montevideo.») y «Las consultas pasan por el servidor del proyecto, que no guarda datos
   personales.». Sin proxy no hay ni datos de confort ni servidor del proyecto.
4. Enlaces: «Política de privacidad» (abre Privacidad, dentro de la app, con `chevronRight`),
   «Código fuente» (en el navegador) y «Contacto» (en la app de correo).
5. Los créditos.

- No pide datos a la red.
- **Llave del bloqueo.** Para encenderla, la app pide confirmar con el sistema («Confirmá para
  activar el bloqueo biométrico»). Si el teléfono no tiene bloqueo de pantalla: «Tu dispositivo
  no tiene bloqueo de pantalla. Configuralo en Ajustes.». Si cancelás, la llave queda como
  estaba. Para apagarla no pide confirmación. Al terminar: «Bloqueo biométrico activado» o
  «Bloqueo biométrico desactivado».
- Si un enlace no se abre: «No se pudo abrir el navegador. Revisá que tengas uno activado.» o «No
  se pudo abrir el correo. Revisá que tengas una app de correo configurada.».
- Mientras Info está abierto, ni Mis paradas ni el Mapa se refrescan.

## Privacidad

Código: `lib/ui/privacy_policy_page.dart` (`PrivacyPolicyPage`) y `lib/ui/policy_markdown.dart`
(`policyToBlocks`).

Se abre con «Política de privacidad» en Info. Muestra `docs/privacy-policy.md` tal cual: el
archivo viene dentro de la app (`assets` en `pubspec.yaml`), así que dice lo mismo que el archivo
del repositorio, cuya URL va en Play Console (`docs/store-listing.md`), y se lee sin conexión. Nada
del texto está escrito en el código.

- El título del archivo («Política de privacidad — Timbre MVD») en `TimbreText.dialogTitle`, cada
  `## ` en mayúsculas con `TimbreText.sectionLabel` («RESUMEN»), y los párrafos y las viñetas en
  Fira 14 / 1.45 `papel`, como los párrafos de Info. Las direcciones (`` `código` `` en el
  archivo) van en Fira Sans Extra Condensed 600; la negrita, en Fira 700.
- Las líneas citadas (`>`) son notas para quien mantiene el archivo: no se muestran.
- En el cuerpo no hay Doto ni ámbar: el Doto queda en la barra (la placa y «PRIVACIDAD»).
- Lee el archivo una vez cada vez que se abre, sin la caché del bundle; hasta que termina, la
  pantalla queda vacía, sin indicador.
- No pide datos a la red. Mientras está abierta, ni Mis paradas ni el Mapa se refrescan: Info
  sigue debajo.

## Bloqueo

Código: `lib/ui/app_lock.dart` (`AppLock`, encima del `Navigator`, en `MaterialApp.builder` de
`lib/main.dart`) y `lib/ui/lock_screen.dart` (`LockScreen`).

Con el bloqueo biométrico encendido, la pantalla de bloqueo tapa toda la app: el tablero de LEDs,
el candado `LedLock`, «BLOQUEADA», «Tus paradas y rutas guardadas están protegidas», el botón
«Desbloquear» y la placa TIMBRE MVD al pie.

- **Cuándo aparece:** al abrir la app y al volver del segundo plano (`hidden` o `paused` y después
  `resumed`). Un estado `inactive` solo, como el de un pedido de permiso del sistema, no bloquea.
  Tampoco bloquea si la app volvió mientras el pedido del sistema estaba abierto o dentro de los 2 s
  de que se cerró, ni si la salida empezó menos de 3 s después de abrir otra app desde Timbre MVD
  (`ExternalApps`): el navegador desde Servicios, «Ver en Cómo Ir», «Código fuente» o
  «© OpenStreetMap» del Mapa, el correo de «Contacto», «Ver más» de una novedad y los ajustes del
  sistema desde «Paradas cercanas».
- **El pedido del sistema** dice «Autenticate para acceder a Timbre MVD» y acepta huella, cara,
  PIN o patrón (`biometricOnly: false`).
- **Si falla o lo cancelás,** queda la pantalla de bloqueo. «Desbloquear» lo vuelve a pedir;
  mientras el pedido está abierto, el botón se desactiva y el candado hace el barrido.
- **Sin método de bloqueo** en el teléfono (`notAvailable`, `notEnrolled`, `passcodeNotSet`), la
  app se abre: si no, quedarías encerrado. Un bloqueo temporal por intentos fallidos la deja
  cerrada.
- **Antes del primer desbloqueo** la app no se arma: ni `HomePage` ni Mis paradas existen y no hay
  pedidos. Después del primer desbloqueo, y una sola vez, la app pide el permiso de notificaciones
  si ya había avisos activados y registra o cancela la verificación en segundo plano
  (`_setupAfterAuth`, con `BackgroundWorker.sync`).
- **Mientras está bloqueada,** la app queda armada debajo, fuera de la vista y del alcance: nada se
  pinta, recibe toques o foco, se anima ni lo escucha el lector de pantalla, y ni Mis paradas ni el
  Mapa piden nada. Los snack bars de la app no aparecen sobre el bloqueo, que tiene su propio
  `ScaffoldMessenger`.
- **El botón atrás** no cierra ninguna página, hoja ni diálogo escondidos (`AppLock.routeGuard`).
  Con solo la pantalla principal debajo, sale de la app, como antes.
- **Al desbloquear** volvés a la misma página, hoja o diálogo. Mis paradas sigue en su subpestaña,
  con los tableros que tenía: apenas vuelve a estar a la vista los actualiza, sin indicadores, y
  sigue cada 30 s.

No hay datos de red en esta pantalla.

## Lo que hoy no está resuelto

Lo anotamos para corregirlo en el código cuando se toque ese archivo:

- **Privacidad sin texto.** Si el archivo de la política no se pudiera leer, la pantalla quedaría
  vacía, sin error.
- **Horarios de una parada que ya no existe** dice «Revisá la conexión.», porque
  `MvdApiService.getSchedule` devuelve `null` para cualquier fallo.
- **Horarios no dice la edad** de una respuesta guardada (hasta 6 h).
- **Agregar ruta:** «Guardar» sin número o sin destino no hace nada y no dice por qué.
- **Estoy esperando** muestra los minutos del momento en que tocaste la fila y no se actualiza
  mientras la hoja está abierta.
- **Con proxy, el Mapa cuenta la edad de un tablero desde `fetchedAt`**, la hora del servidor, y no
  desde que llegó al teléfono, como Mis paradas (`_BoardView.receivedAt`). Con el reloj del
  teléfono adelantado un minuto o más, sus ómnibus salen sin encender aunque el tablero acabe de
  llegar; con el reloj atrasado, o adelantado más de 30 s, el Mapa vuelve a pedir los tableros que
  Mis paradas acaba de traer. Sin proxy, `fetchedAt` es la hora del teléfono cuando llega la
  respuesta (`DirectSource.arrivals`) y esto no pasa.
