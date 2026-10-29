# Componentes

Las piezas con las que se arman las pantallas. Las públicas están en `lib/ui/widgets/`; las
tarjetas, las notas y las filas de los diálogos son privadas de `lib/ui/stops_page.dart`,
`lib/ui/schedule_page.dart`, `lib/ui/news_list.dart` y `lib/ui/map/`. Para cada una: qué es, sus estados, qué
dato muestra (campo del modelo ← campo de /v1) y dónde se usa.

La cadena completa hasta la fuente de la ciudad (por ejemplo `clockTime` ← `horaDesc`) está en
[pantalla-a-datos.md](pantalla-a-datos.md). Colores en [02-color.md](02-color.md), estilos de
texto en [03-tipografia.md](03-tipografia.md), íconos en [04-iconos.md](04-iconos.md), radios y
espacios en [05-formas-y-espacio.md](05-formas-y-espacio.md), brillo y animación en
[06-luz-y-movimiento.md](06-luz-y-movimiento.md), textos en [07-textos.md](07-textos.md).

## `ArrivalRow`: un ómnibus en el tablero

`lib/ui/widgets/arrival_row.dart`. A la izquierda el `LineBadge`, en el medio el destino y las
marcas de confort, a la derecha el tiempo. Alto mínimo 52, márgenes 14 × 6.

### Estados

| Estado | Cuándo | Badge | Tiempo | Frase del lector (después de «Línea 121 a Punta Carretas, ») |
|---|---|---|---|---|
| **vivo** | `isRealTime` y `etaMinutes > 0`, no `stale` | lleno, `ambar` | `MinutosEnVivo`: punto, «12» en Doto 26 `ambar`, «min» | «llega en 12 minutos, con GPS» |
| **llegando** | `isRealTime` y `etaMinutes <= 0`, no `stale` | lleno, `ambar` | `LlegandoChip`: «LLEGANDO» | «llegando, con GPS» |
| **horario** | `state == scheduled`, no `stale` | contorno `etiquetaCartel` | reloj `tenue` y «20:17» en `scheduleTime` 20 px | «horario 20:17, sin GPS» |
| **estimado** | `stale: true` (último tablero después de un fallo, o uno que llegó hace 1 min o más) | contorno, aunque haya tenido GPS | reloj y «~20:01» en `scheduleTime` 20 px | «alrededor de las 20:01, estimado» |
| **esperado** | `waited: true` y no `stale` | el de su estado | el de su estado | se agrega «estás esperando este ómnibus» |

- *Esperado* se suma a vivo, llegando u horario: la fila se levanta con fondo `tintaAlta` y
  suma la marca `bellRing` en `ambar`.
- Una fila *estimada* no se puede tocar, no se marca como esperada y nunca va en ámbar.
- Las marcas de confort van en `etiquetaCartel`, 14 px, solo cuando el dato es `true`:
  `accessible` (accesible), `snow` (aire acondicionado), `bolt` (cero emisiones). Un `null` no
  muestra nada.
- El destino va en Fira Sans Extra Condensed 17, hasta 2 líneas y después «…». Si viene vacío
  se muestra «Línea 121».
- Con letra grande (`TimbreText.isLarge`, desde 150 %) el tiempo baja a su propia línea,
  alineado a la derecha, y se achica con `FittedBox` antes de cortarse.
- Tocar la fila abre «Estoy esperando» ([09-pantallas.md](09-pantallas.md)).

### Qué muestra

| En pantalla | Modelo (`BusArrival`, `ArrivalsBoard`) | /v1 (`GET /v1/stops/{id}/arrivals`) |
|---|---|---|
| número de línea | `line` | `arrivals[].line` |
| destino | `destination` | `arrivals[].destination` |
| badge lleno o contorno, punto y Doto o reloj | `state` → `isRealTime` | `arrivals[].state` (`live`, `arriving`, `scheduled`) |
| minutos | `etaMinutes` | `arrivals[].etaMinutes` |
| «20:17» y «~20:17» | `clockTime` (en horario, a través de `etaLabel`) | `arrivals[].clockTime` |
| marca accesible | `accessible` | `arrivals[].accessible` |
| marca aire acondicionado | `airConditioning == true` | `arrivals[].airConditioning` (`null` sin proxy) |
| marca cero emisiones | `zeroEmission == true` | `arrivals[].zeroEmission` (`null` sin proxy) |
| fila esperada | `tripId`, `variantId`, `expectedAt` a través de `BusWait.follows` | `arrivals[].tripId`, `variantId`, `expectedAt` |
| qué filas estimadas quedan | `expectedAt` ≥ el «ahora» de la fuente − 1 min (`ReceivedBoardClock.sourceNow`) | `arrivals[].expectedAt` |
| «Datos de las 19:52» (en la nota de arriba) | `ArrivalsBoard.fetchedAt` | `fetchedAt` |

Sin proxy no hay datos de confort: la app solo muestra «accesible».

## `LineBadge`: el número de línea

`lib/ui/widgets/line_badge.dart`.

| Variante | Cuándo | Aspecto |
|---|---|---|
| encendido (`live: true`) | ómnibus con GPS | relleno `ambar`, número en `tinta` |
| apagado (`live: false`) | horario o estimado | borde `etiquetaCartel` de 1.5, número en `etiquetaCartel` |
| normal | filas de arribos | 19 px, ancho de 46 a 70, radio `TimbreRadii.badge` (8) |
| compacto (`compact: true`) | Horarios | 17 px, ancho de 52 a 76, radio 7 (literal, no es un token) |

El número se achica con `FittedBox` cuando no entra («124 SD»). La diferencia entre GPS y
horario no depende solo del color: relleno contra contorno.

Muestra `BusArrival.line` ← `arrivals[].line`, o `ScheduledPass.line` ← `passes[].line`. Se usa
en `ArrivalRow` (`live: a.isRealTime && !stale`), en la fila de horario (`live: false,
compact: true`) y en la hoja de un ómnibus del Mapa (`live` mientras su tablero está al día).

## `MinutosEnVivo`: los minutos con GPS

`lib/ui/widgets/cartel.dart`. `LiveDot`, los minutos en Doto (`TimbreText.liveMinutes`, 30 por
defecto; `ArrivalRow` y la hoja de un ómnibus del Mapa usan 26) y «min» en `TimbreText.minuteUnit`
(Fira Sans Extra Condensed 14, `ambarTenue`). Con `minutes <= 0` muestra un `LlegandoChip`.

Frase propia: «en 12 minutos, con GPS». Dentro de `ArrivalRow` no se escucha, porque la fila
lee su propia frase. Solo para GPS: un horario teórico usa `TimbreText.scheduleTime`.

## `LlegandoChip`: el ómnibus está en la parada

`lib/ui/widgets/cartel.dart`. «LLEGANDO» en Doto 20, `tinta` sobre `ambar`, radio
`TimbreRadii.badge`, con la sombra `TimbreShadow.ledGlow`. Es el único estado encendido entero.
La escala de texto no lo achica (`withClampedTextScaling(minScaleFactor: 1)`). El lector dice
«llegando».

Aparece cuando `etaMinutes <= 0` en un ómnibus con GPS (/v1 `state: "arriving"`).

## `LiveDot`: la marca de GPS

`lib/ui/widgets/cartel.dart`. Un píxel encendido de 6 px dentro de una caja de 12, con brillo
propio (`ambar` al 60 %, desenfoque de `size × 0.45`). No usa `TimbreShadow.ledGlow`; la razón
está en [12-decisiones.md](12-decisiones.md). Va en `MinutosEnVivo`, `CartelTira` y
`CartelParada`.

## `CartelTira`: el cartel de «Estoy esperando»

`lib/ui/widgets/cartel.dart`. Una tira de LED con la línea, el destino y los minutos del ómnibus
que vas a esperar. Solo para viajes con GPS; un viaje sin GPS se muestra como texto
(«121 → PUNTA CARRETAS»).

- Línea en Doto 26, destino en Doto 22, minutos en Doto 34 y «min» en Doto 19; con 0 min,
  «LLEGANDO» en Doto 22. Panel `tinta`, borde `lineaNoche`, radio `TimbreRadii.button` (14).
- **En fila:** línea, destino en hasta 2 líneas, minutos.
- **Apilado:** línea y minutos arriba, destino abajo en hasta 3 líneas. Pasa con letra grande
  (`isLarge`) y también por debajo de 150 % cuando el destino no entra en 2 líneas al lado de los
  minutos sin cortar una palabra (`_fitsInRow`, que mide con `TextPainter`).
- La escala de texto no lo achica (`minScaleFactor: 1`).
- Frase: «Línea 121 a Punta Carretas, llega en 12 minutos, con GPS».

Muestra `line`, `destination` y `etaMinutes` del `BusArrival` que tocaste (/v1 `line`,
`destination`, `etaMinutes`). Los minutos son los de ese momento: la hoja no se actualiza
mientras está abierta.

## `CartelParada`: sin uso

`lib/ui/widgets/cartel.dart`. Un cartel grande con el próximo ómnibus con GPS: «PRÓXIMO»,
«Actualizado 08:05», la línea y el destino en Doto, los minutos en Doto 72 o «LLEGANDO», y las
marcas de confort. Ninguna pantalla lo usa hoy; solo lo prueba `test/cartel_test.dart`. Si se
vuelve a usar:

- Muestra la hora con cero adelante y en la hora del teléfono (`_hhmm`), no con el reloj «H:MM»
  de [07-textos.md](07-textos.md).
- Sus marcas de confort son `bool`, no `bool?`: hay que pasarle `airConditioning == true`.
- Un cartel por pantalla (regla en el comentario de `cartel.dart`).

## `CartelCompacto`: la placa TIMBRE MVD

`lib/ui/widgets/cartel.dart`. El ómnibus encendido y «TIMBRE» en `ambar` con « MVD» en
`ambarTenue`, en Doto 22 (mínimo 19) sobre `tinta`. La escala de texto se limita entre 1 y 1.3,
así que la placa no crece más de 130 %. El lector dice «Timbre MVD». No muestra datos. Es el
título de todas las barras (`buildTimbreAppBar`) y va al pie de la pantalla de bloqueo.

## `TimbreEmptyState`: una lista vacía

`lib/ui/widgets/empty_state.dart`. Un cartel sin nada que anunciar: panel `tinta` con LED
apagados (`LedMatrix` al 11 %), el ómnibus y el `sign` en Doto 20 (la escala no lo achica), y
abajo el `detail` en `TimbreText.subtitle`. El lector escucha `message`.

| Pantalla | `sign` | `message` | `detail` | Cuándo |
|---|---|---|---|---|
| Paradas | «SIN PARADAS» | «Sin paradas guardadas» | «Tocá + para agregar una parada y recibir un aviso cuando llegue el ómnibus.» | no hay paradas guardadas (Hive) |
| Rutas | «SIN RUTAS» | «Sin rutas guardadas» | «Tocá + para guardar una alerta de salida.» | no hay rutas guardadas (Hive) |
| Novedades | «SIN NOVEDADES» | «Sin novedades» | «Los desvíos y cambios de recorrido aparecen acá.» | /v1 `news` vacío y nada guardado |
| Horarios | «SIN PASADAS» | «Sin pasadas para este horario» | «Probá con otro día o con una hora más temprano.» | /v1 `passes` vacío |
| Mapa | «SIN PARADAS» | «Sin paradas guardadas» | «Agregá una parada en Mis paradas para ver acá los ómnibus con GPS que se acercan.» | no hay paradas guardadas (Hive) |

En Paradas y Rutas va dentro de `_EmptyTab`, que lo centra y lo deja desplazarse con la letra más
grande; en el Mapa, dentro de `_NoStops`, que hace lo mismo.

## `PageTitleBar` y `buildTimbreAppBar`: la barra de cada pantalla

`lib/ui/widgets/page_title_bar.dart`, `lib/ui/widgets/timbre_app_bar.dart`.

`buildTimbreAppBar` arma la barra: `CartelCompacto` como título, LED apagados a la derecha que se
desvanecen hacia el título (`LedMatrix` con `TimbreOpacity.ledUnlit`) y abajo el
`PageTitleBar`.

- **Título:** en mayúsculas, Doto 28 `ambar` (`TimbreText.pageTitle`). Si no entra, se achica a
  lo ancho (`FittedBox`); nunca termina en «…». El lector escucha el título como encabezado y como
  se escribe, sin pasarlo a mayúsculas («Mis paradas»).
- **Subtítulo:** hasta 4 líneas (`subtitleMaxLines`): un nombre del catálogo como «AV 18 DE
  JULIO y CIRCUNVALACION DR ENRIQUE TARIGO» ocupa tres a 2×. Por defecto `TimbreText.subtitle`.
- **`subtitleTrailing`:** el final que nunca se corta. Horarios pone « · 574» después del nombre.
- **`semanticLabel`:** reemplaza la frase de toda la barra.
- **Alto:** `preferredSize` se calcula con la escala de texto y con las líneas que ocupa el
  subtítulo al ancho de la pantalla (`width`).

| Pantalla | Título | Subtítulo | Frase |
|---|---|---|---|
| Mis paradas | «Mis paradas» | — | «Mis paradas» |
| Mapa | «Mapa» | — | «Mapa» |
| Servicios | «Servicios» | «Sitios oficiales, en tu navegador» | título y subtítulo |
| Horarios | «Horarios» | `BusStop.name` + « · » + `BusStop.id`, en Fira Sans Extra Condensed 17 `etiquetaCartel` | «Horarios de la parada 574, San Jose y Andes» |
| Info | «Info» | — | «Info» |
| Privacidad | «Privacidad» | — | «Privacidad» |

El nombre de la parada en Horarios es el que guardaste (`BusStop.name`, que vino de /v1
`name` o del catálogo).

## `TimbreSegmented`: elegir una opción

`lib/ui/widgets/segmented.dart`. Una pista `tinta` con borde `lineaNoche` y radio
`TimbreRadii.button` (14). Cada segmento tiene radio 11 (literal) y alto mínimo
`TimbreSpace.touch` (44). El elegido se enciende en `ambar` con texto `tinta`; los otros, texto
`papel`. Una etiqueta que no entra se achica (`FittedBox`).

Para el lector, el grupo tiene nombre (`semanticLabel`) y cada segmento es un botón con
`selected` y su propio `onTap`.

| Dónde | Opciones | Nombre del grupo | Qué cambia |
|---|---|---|---|
| Horarios | «Hábiles», «Sábados», «Domingos» (`DayType.label`) | «Tipo de día» | `{day}` de `/v1/stops/{id}/schedule/{day}/{H:MM}`: `weekday`, `saturday`, `sunday` |
| Estoy esperando | «3 min», «5 min», «10 min» (5 por defecto) | «Minutos antes de que llegue» | `BusWait.alertMinutes` |
| Ajustes de aviso | «3 min», «5 min», «10 min» | «Minutos antes de que llegue» | `etaAlertMinutes` o `alertMinutes` |

## Tarjeta de parada

`_buildStopCard` en `lib/ui/stops_page.dart`. Un tablero chico sobre una `Card` `tinta` con
borde `lineaNoche` y radio 16.

1. **Encabezado:** nombre (`TimbreText.stopName`) y «#574» (13 px, `etiquetaCartel`); el botón
   del reloj «Horarios»; la campana (`_AlertButton`: apagada `bell` en `tenue`, encendida
   `bellRing` en `ambar` con brillo; descripción «Activar avisos» o «Desactivar avisos»).
2. **Fila del aviso**, solo con el aviso encendido: «Aviso 5 min antes · Lun a Vie 7:30–8:30»
   en 13 px `etiquetaCartel`, con la campana en `ambar` y una flecha. Abre los ajustes.
3. **Bloque de arribos** (abajo).
4. **«Ver en Cómo Ir»**: abre `m.montevideo.gub.uy/comoir/parada?numero=574` en el navegador.

Se borra deslizando hacia la izquierda (fondo `rojoLed` con la papelera en `noche`, que el lector
llama «Eliminar») o con la acción «Borrar» del lector de pantalla. No pide confirmación.

| En pantalla | Modelo | Origen |
|---|---|---|
| nombre, número | `BusStop.name`, `BusStop.id` (Hive) | al guardar: /v1 `name` (`StopDetails.displayName`) o el `name` del catálogo |
| campana, fila del aviso | `notificationsEnabled`, `etaAlertMinutes`, `schedule` | solo en el teléfono |
| filas | el tablero de `stop.id` | `GET /v1/stops/{id}/arrivals` |

## Tarjeta de ruta

`_buildRouteCard` en `lib/ui/stops_page.dart`. Misma `Card` que la de parada.

1. **Encabezado:** ícono de parada y el nombre del origen (13 px, `etiquetaCartel`); «→ Trabajo»
   (`TimbreText.stopName`); si elegiste líneas o destinos, «Líneas: 116, 117 · Hacia: POCITOS» en
   `TimbreText.caption` `tenue`; la campana.
2. **Fila del aviso**, con la ruta encendida.
3. **Bloque de arribos** del origen, filtrado con `RouteAlert.accepts`.

No tiene botón de Horarios ni «Ver en Cómo Ir». Se borra igual que la de parada.

`accepts` deja pasar un ómnibus si su línea está en `preferredLines` (sin importar mayúsculas; si
no elegiste líneas, pasan todas) y además la ruta no guardó destinos ni variantes, o su
`variantId` está en `preferredVariantIds`, o su `destination` está en `preferredDestinations`. Si una parada guardada es también el origen de una ruta, las
dos tarjetas leen el mismo tablero: un solo pedido.

| En pantalla | Modelo (`RouteAlert`, Hive) | Origen |
|---|---|---|
| origen | `originName` | /v1 `name` al crear la ruta; «Parada N» sin conexión |
| «→ Trabajo» | `destinationName` | lo que escribiste |
| «Líneas: …» | `preferredLines` | chips de /v1 `lines` |
| «Hacia: …» | `preferredDestinations` (más `preferredVariantIds`, que no se ven) | /v1 `directions[].destination` y `variantIds`, o `destination` y `variantId` de los arribos |
| filas | el tablero de `originStopId` | `GET /v1/stops/{id}/arrivals` |

## Bloque de arribos

`_buildArrivals` y `_buildRows` en `lib/ui/stops_page.dart`. Lo comparten las dos tarjetas. Las
condiciones se revisan en este orden:

| # | Condición | Muestra |
|---|---|---|
| 1 | todavía no hay tablero, y no hay fallo o se está cargando con indicador | indicador de progreso de 18 px |
| 2 | fallo `notFound` | nota roja «Esta parada ya no existe. Deslizá la tarjeta para borrarla.» |
| 3 | otro fallo, sin tablero o con un tablero de 5 min o más | nota roja «No se pudo actualizar. Deslizá para reintentar» |
| 4 | otro fallo, con un tablero de menos de 5 min | nota roja «No se pudo actualizar. Datos de las 19:52. Deslizá para reintentar.» y las filas estimadas con `expectedAt` ≥ el «ahora» de la fuente − 1 min |
| 5 | sin fallo, con un tablero que llegó hace 1 min o más (`_liveFor`) | sin nota, las filas estimadas con `expectedAt` ≥ el «ahora» de la fuente − 1 min. Con 5 min o más, o si no queda ninguna, el indicador de 18 px, como antes del primer tablero |
| 6 | sin fallo, ninguna fila (o ninguna pasa el filtro) | nota «Sin ómnibus próximos» en `tenue` con el ícono `bus` |
| 7 | sin fallo, con filas | hasta 6 filas; se ven 3 y el resto con «Ver las 6»; «Ver menos» las vuelve a ocultar |

Una respuesta `busy` no cambia nada: quedan el último tablero, su hora de llegada y el último
fallo, así que con varios 429 seguidos el tablero también envejece (fila 5). Con fallo o sin él,
la edad del tablero se mide desde que llegó al teléfono (`_BoardView.receivedAt`, con
`StopsPage.clock`), y una fila estimada se saca si su `expectedAt` pasó hace más de 1 min en el
reloj de la fuente (`fetchedAt` más lo que el tablero lleva en el teléfono).

## Nota de error: `_BoardNote`

`lib/ui/stops_page.dart`. Una línea dentro de la tarjeta: ícono de 20 px y texto en
`TimbreText.subtitle`, los dos del mismo color, con margen de 14. No tiene panel. Hay dos
variantes: `warning` en `rojoLed` para los fallos, y `bus` en `tenue` para «Sin ómnibus
próximos». Es la forma de un error dentro de una tarjeta; un aviso sobre una lista usa el panel
`avisoNoche` ([02-color.md](02-color.md)).

## Aviso de GPS parcial

`_buildGpsWarning` en `lib/ui/stops_page.dart`. Panel `avisoNoche` con borde `ambarTenue`, radio
`TimbreRadii.control` (12), ícono `signal` en `ambar` y texto `papel` de 13 px. Es la primera
fila de las listas de Paradas y de Rutas; no aparece cuando la lista está vacía.

Aparece cuando algún operador tiene datos parciales y nombra solo a esos: «Datos GPS parciales
(CUTCSA 60 %): algunos tiempos pueden ser horarios teóricos o menos precisos.»

| En pantalla | Modelo (`OperatorGpsStatus`) | /v1 (`GET /v1/status/gps`) |
|---|---|---|
| empresa | `company` | `operators[].company` |
| porcentaje | `percent` | `operators[].percent` |
| si aparece | `isPartial` (`partial`, o `percent < 70` si falta) | `operators[].partial` |

## Fila de horario y encabezado de hora

`_PassRow` y `_HourHeader` en `lib/ui/schedule_page.dart`.

- **Fila:** la hora en `TimbreText.scheduleTime` (22 px, `etiquetaCartel`, cifras tabulares) en
  un ancho de 56 que se achica antes de partirse; el `LineBadge` compacto apagado; el destino en
  17 px, hasta 2 líneas. Alto mínimo 44. Frase: «23:31, línea 145 a Plaza España».
- **Encabezado:** «20 h» en Fira Sans Extra Condensed 20, `etiquetaCartel`, sobre una franja
  `tinta`. Es un rótulo, no un dato vivo: nunca va en ámbar. El lector lo escucha como
  encabezado: «Las 20».
- **«Después de medianoche»:** aparece cuando `hhmm` de una fila es menor que el de la anterior.

| En pantalla | Modelo (`ScheduledPass`) | /v1 (`GET /v1/stops/{id}/schedule/{day}/{H:MM}`) |
|---|---|---|
| hora | `time` | `passes[].time` |
| línea | `line` | `passes[].line` |
| destino | `destination` | `passes[].destination` |
| encabezado y medianoche | `hhmm` | `passes[].hhmm` |

## Fila de novedad y panel de error de Novedades

`_NewsRow`, `_DateTile`, `_FailedBanner` y `showNewsDetail` en `lib/ui/news_list.dart`.

- **Sin leer:** fondo `tinta`; recuadro de fecha con LED apagados y el día en Doto 24 `ambar`;
  rótulo «NUEVA» en `ambar`; título en negrita. El ámbar de lo no leído es un contador: ver
  [12-decisiones.md](12-decisiones.md).
- **Leída:** fondo `noche`; recuadro vacío con el día en Fira Sans Extra Condensed 26
  `etiquetaCartel` y el mes en `tenue`.
- El recuadro mide 52 × 56 y la fecha se achica adentro con la letra más grande.
- Frase: «Nueva. 27 de octubre. Título. Resumen», como botón.
- Tocarla abre el detalle: título (`TimbreText.dialogTitle`), fecha «27/10/2026», el texto con
  `SafeHtml` y, si hay enlace, el botón «Ver más».
- `_FailedBanner`: panel `avisoNoche` con «No se pudo actualizar. Deslizá para reintentar» en
  `ambar`, arriba de las novedades guardadas.

| En pantalla | Modelo (`TransportNews`) | /v1 (`GET /v1/news`) |
|---|---|---|
| sin leer o leída | `id` comparado con el último leído | `news[].id` |
| título | `title` | `news[].title` |
| resumen | `summary` | `news[].summary` |
| fecha | `date` (hora del teléfono) | `news[].publishedAt` |
| texto del detalle | `body` (o `summary` si está vacío) | `news[].body` |
| «Ver más» | `link` | `news[].link` |

## Filas de parada en «Agregar parada»

`_buildNearbyTile` y `_buildMatchTile` en `lib/ui/stops_page.dart`. Ícono de parada de 22 px en
`etiquetaCartel` (una marca pasiva, sin encender), nombre en `papel` y una línea en
`TimbreText.caption`.

- **Cercana:** «#5109 · 48 m · 124, 125», hasta 2 líneas. Sin líneas termina en la distancia.
  Frase: «Parada 5109, Av Italia y Propios, a 48 metros, líneas 124, 125».
- **Por calles:** «#574». Frase: «Parada 574, San Jose y Andes».
- Elegir una la guarda en el acto como `BusStop(id, name, lines, latitude, longitude)`, sin otro
  pedido: la ubicación es la que usa después el Mapa.

| En pantalla | Modelo | Con proxy: /v1 (`GET /v1/catalog/stops`) | Sin proxy |
|---|---|---|---|
| número | `NearbyStop.id`, `CatalogStop.id` | `stops[].id` | WFS `cod_ubic_parada` |
| nombre | `name` («Parada N» si falta) | `stops[].name` | WFS `calle` y `esquina` |
| líneas | `lines` | `stops[].lines` (vacías con `linesAvailable: false`) | WFS `desc_linea` |
| distancia | `NearbyStop.distanceMeters` | calculada en el teléfono con `stops[].location` | calculada en el teléfono |

## Chips de «Agregar ruta» y de los ajustes de aviso

`FilterChip` con el tema de `lib/ui/theme/timbre_theme.dart`: fondo `tintaAlta`; elegido, fondo
`ambar` con texto y tilde en `tinta`; radio 999 (literal).

- **LÍNEAS:** `StopDetails.lines` ← /v1 `lines`.
- **HACIA:** `StopDetails.directions` ← /v1 `directions[]`, agrupadas por `destination`. Cada chip
  lleva la unión de sus `variantIds`. Una línea sin direcciones toma los destinos de sus próximos
  ómnibus (`destination` y `variantId` de `GET /v1/stops/{id}/arrivals`).
- **DÍAS** (ajustes de aviso): «Lu», «Ma», «Mi», «Ju», «Vi», «Sá», «Do», sin la marca de elegido
  (`showCheckmark: false`); el lector dice «Lunes» a «Domingo».

## El Mapa: paradas, ómnibus, notas y hojas

Privadas de `lib/ui/map/`, salvo `BusLayer`, `BusSheet` y `StopSheet`. Los estados de la pantalla
están en [09-pantallas.md](09-pantallas.md#mapa); las frases del lector, en
[11-accesibilidad.md](11-accesibilidad.md).

- **Parada (`_StopMarker`, `mapa_page.dart`).** Baldosa `tinta` de 26 × 26, radio
  `TimbreRadii.chip` (6), borde `etiquetaCartel` de 1.5, con `stop` de 16 px en `papel`, en un
  área táctil de 44 × 44. No se enciende nunca: el ámbar queda para los ómnibus. Muestra
  `BusStop.latitude`, `longitude` ← `stops[].location`.
- **Ómnibus (`BusLayer`, `bus_layer.dart`).** Todos en una sola capa pintada, sin un widget por
  ómnibus: las píldoras salen de un atlas dibujado una vez por número de línea (`drawRawAtlas`), y
  los puntos, de `drawRawPoints`. Muestra `BusArrival.location` ← `arrivals[].location` y `line`.
  - Píldora, desde el zoom 14 del estilo: 22 de alto, el ómnibus de píxeles de 12 px y el número en
    `TimbreText.lineBadge` a 15 px, con un borde `noche` de 1.5 que separa las que se pisan.
    Encendida, placa `ambar` con ómnibus y número en `tinta`, como `LineBadge(live: true)`;
    estimada, placa `tinta` con borde de 1.5, ómnibus y número en `etiquetaCartel`.
  - Punto, más lejos: `ambar` de 5.5 px con halo `noche` de 8; estimado, un aro `etiquetaCartel`
    con el centro `tinta`.
  - Los encendidos van encima de los estimados, y los de más al sur encima de los de más al norte.
- **Nota (`_MapNote`).** Panel `tinta`, borde `lineaNoche`, radio `TimbreRadii.control` (12),
  ícono de 20 y texto `TimbreText.subtitle` en `tenue`.
- **Panel de error (`_FailedBanner`).** Como el de Novedades: `avisoNoche`, borde `ambarTenue`,
  radio 12, `warning` y texto en `ambar` (`TimbreText.subtitle`, 600), y «Reintentar». Desde 150 %
  el botón pasa debajo del texto.
- **Atribución (`_Attribution`).** «© OpenStreetMap» (`Basemap.attribution`) en
  `TimbreText.caption` (`etiquetaCartel`) sobre un recuadro `noche` con la esquina de arriba a la
  derecha redondeada (6), en un área táctil de 44 × 44.
- **Hoja de un ómnibus (`BusSheet`, `map_sheets.dart`).** Arriba, el `LineBadge` y el destino en
  `TimbreText.destination` («Línea N» si viene vacío). Debajo, una fila de 52 de alto como mínimo
  por cada parada guardada a la que va (`MapBus.etas`, la más próxima primero): «a la parada 574 ·
  SAN JOSE y ANDES» en `TimbreText.body` y, a la derecha, `MinutosEnVivo` de 26 o, si es un
  estimado, el reloj y «~19:56» en `scheduleTime` de 20. Desde 150 % el tiempo pasa debajo.
- **Hoja de una parada (`StopSheet`, `map_sheets.dart`).** El nombre en `TimbreText.stopName` y
  «#574» en `TimbreText.caption` de 13; debajo, hasta 6 `ArrivalRow` sin acción de tocar, en
  `stale` cuando el tablero no está al día. Sin filas, una nota: «Sin ómnibus próximos» en `tenue`
  con `bus`, o «No se pudo actualizar. Revisá la conexión.» en `rojoLed` con `warning`.

Las dos hojas se desplazan cuando sus filas no entran en la pantalla.
