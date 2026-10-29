# Decisiones

Por qué el sistema es como es. Antes de cambiar una regla, leé por qué
apareció. Cada decisión tiene tres partes: el contexto (qué problema había),
la decisión (qué se eligió) y la consecuencia (qué implica, también lo
incómodo).

Las doce primeras vienen del diseño original de Timbre y están corregidas
según el código. Las siguientes salieron de la reconstrucción del proxy como
Backend-for-Frontend (`/v1`), de la revisión de diseño de la misma rama y de
la pestaña Mapa. El contrato completo está en [contrato-v1.md](contrato-v1.md).

Índice:

- Identidad: [No copiamos la app oficial](#no-copiamos-la-app-oficial) ·
  [Siempre oscuro](#siempre-oscuro-sin-tema-claro) ·
  [El ámbar es luz](#el-ámbar-es-luz-y-la-luz-es-lo-vivo) ·
  [El GPS se distingue por la forma](#el-gps-se-distingue-por-la-forma-no-solo-por-el-color) ·
  [Doto desde 19 px](#doto-nunca-por-debajo-de-19-px) ·
  [Íconos de píxeles](#íconos-de-píxeles-en-vez-de-material) ·
  [La parada es un cartel](#la-parada-es-un-cartel-en-un-poste-no-un-marcador-de-mapa) ·
  [Acento de las notificaciones](#el-acento-de-las-notificaciones-es-el-azul-del-tablero) ·
  [Ningún símbolo oficial](#ningún-símbolo-oficial) ·
  [Ámbar solo sobre azul noche](#el-ámbar-solo-como-luz-de-led-sobre-azul-noche) ·
  [La letra grande no corta nada](#la-letra-grande-no-corta-nada) ·
  [Riesgo: el sol](#riesgo-el-sol)
- Datos y pantallas: [Datos viejos como estimado](#los-datos-viejos-se-muestran-como-estimado) ·
  [«NUEVA» en ámbar](#nueva-y-la-fecha-de-lo-no-leído-van-en-ámbar) ·
  [El brillo de `LiveDot`](#el-brillo-de-livedot) ·
  [El widget muestra el destino del ómnibus](#el-widget-muestra-el-destino-del-ómnibus) ·
  [Los widgets de parada encienden la línea, no la hora](#los-widgets-de-parada-encienden-la-línea-no-la-hora) ·
  [El bloqueo va encima del `Navigator`](#el-bloqueo-va-encima-del-navigator) ·
  [El bloqueo vuelve solo después del segundo plano](#el-bloqueo-vuelve-solo-después-del-segundo-plano) ·
  [El mapa viene dentro de la app](#el-mapa-viene-dentro-de-la-app)
- Backend: [Sin ruta por lotes](#sin-ruta-por-lotes) ·
  [Cercanas en el teléfono](#las-paradas-cercanas-se-calculan-en-el-teléfono) ·
  [Sin cambio automático al modo directo](#sin-cambio-automático-al-modo-directo) ·
  [Rutas públicas eliminadas](#rutas-públicas-eliminadas) ·
  [Horarios solo con H:MM](#la-ruta-de-horarios-acepta-una-sola-forma-de-hora-hmm) ·
  [Rutas por variante o por destino](#las-rutas-reconocen-el-ómnibus-por-variante-o-por-destino)

---

## Identidad

### No copiamos la app oficial

**Contexto.** Si la app se parece a la oficial, la primera pregunta del
usuario es «¿y cuál es la diferencia?».

**Decisión.** La respuesta es el producto: el tablero de tu parada en el
bolsillo, el GPS separado del horario y «Estoy esperando» con su aviso. El
tablero oscuro lo muestra antes del primer toque.

**Consecuencia.** Cada pantalla es un tablero con carteles
([01-principios.md](01-principios.md)). Un componente que solo imita a la app
oficial no entra.

### Siempre oscuro, sin tema claro

**Contexto.** El tablero de una parada es oscuro. Dos temas son dos
revisiones de contraste y el doble de trabajo.

**Decisión.** Un solo tema oscuro: `buildTimbreTheme()` arma un
`ColorScheme` con `Brightness.dark` y `MaterialApp` no tiene `darkTheme` ni
`themeMode` (`lib/main.dart`). La pantalla de inicio, el ícono, el widget y
la ventana de Android detrás de la app también son oscuros
([10-superficies.md](10-superficies.md)), para que la app no destelle en
blanco al abrir.

**Consecuencia.** No hay superficies blancas en ningún lado. El riesgo de
esta decisión es el sol ([Riesgo: el sol](#riesgo-el-sol)).

### El ámbar es luz, y la luz es lo vivo

**Contexto.** Si todo brilla, el brillo no significa nada.

**Decisión.** `ambar` se enciende solo donde algo está vivo, encendido o
pide una acción:

- los datos en vivo: los minutos con GPS (`MinutosEnVivo`), «LLEGANDO»
  (`LlegandoChip`), el número de línea relleno (`LineBadge(live: true)`),
  el ómnibus que estás esperando, los ómnibus con GPS sobre el Mapa;
- los carteles de la marca: «TIMBRE», el título de página, el candado de
  bloqueo, el cartel de una lista vacía;
- las acciones: el relleno del botón principal y el texto de los botones de
  contorno y de texto;
- lo elegido o encendido: chip y segmento elegidos, interruptor encendido,
  pestaña elegida, campanita de un aviso activado;
- el foco de un campo, el cursor y los indicadores de carga;
- los contadores (ver [la excepción de «NUEVA»](#nueva-y-la-fecha-de-lo-no-leído-van-en-ámbar))
  y el ícono de los avisos sobre `avisoNoche`;
- los LED apagados de `LedMatrix`, al 10 % más o menos.

Los horarios, los estimados y los datos viejos nunca van en ámbar.

**Consecuencia.** Una hora de horario se escribe con `TimbreText.scheduleTime`
en `etiquetaCartel`, nunca en Doto ni en ámbar. Las reglas completas están en
[02-color.md](02-color.md).

### El GPS se distingue por la forma, no solo por el color

**Contexto.** Hay usuarios con daltonismo, pantallas al sol y lectores en
escala de grises.

**Decisión.** Un ómnibus con GPS y uno de horario se diferencian también por
la forma: número relleno contra contorno (`LineBadge`), punto encendido y
dígitos Doto (`LiveDot` + `TimbreText.liveMinutes`) contra reloj y Fira
Sans Extra Condensed (`PixelGlyphs.clock` + `TimbreText.scheduleTime`), en
`ArrivalRow`.

**Consecuencia.** Un estado nuevo de llegada necesita su propia forma, no
solo un color. El lector de pantalla también lo dice con palabras («con
GPS», «sin GPS», «estimado»).

### Doto nunca por debajo de 19 px

**Contexto.** Más chicos, los puntos de Doto se mezclan y dejan de leerse
como letras.

**Decisión.** `TimbreFonts.dotoMinSize` = 19. `TimbreText.liveMinutes` y
`TimbreText.cartel` suben a 19 cualquier tamaño menor, y los carteles en Doto
usan `MediaQuery.withClampedTextScaling(minScaleFactor: 1)` para que una
letra del sistema más chica no los achique.

**Consecuencia.** Lo que no entra en 19 px no va en Doto: se escribe en Fira
([03-tipografia.md](03-tipografia.md)).

### Íconos de píxeles en vez de Material

**Contexto.** Los íconos de Material hacen que cualquier app parezca una
plantilla.

**Decisión.** Íconos y letras comparten la misma grilla de puntos:
`PixelGlyphs` (35 glifos de 12 × 12 en `lib/ui/widgets/pixel_glyphs.dart`),
dibujados por `PixelIcon`. En `lib/` no queda ningún `Icons.`.

**Consecuencia.** Un ícono nuevo se dibuja en la grilla
([04-iconos.md](04-iconos.md)). Los tres íconos del widget de Android son
copias vectoriales de glifos y hay que rehacerlas a mano si el glifo cambia
([10-superficies.md](10-superficies.md#cómo-se-ve)).

### La parada es un cartel en un poste, no un marcador de mapa

**Contexto.** Un marcador de mapa dice «un lugar en el mapa», y una parada es
otra cosa: el cartel donde esperás el ómnibus. La regla original decía que la
app no muestra mapas, que muestra paradas. Con la pestaña Mapa la app dibuja
un mapa propio, y ahí lo fácil era la gota de siempre.

**Decisión.** La parada es `PixelGlyphs.stop`, un cartel con un ómnibus
arriba de un poste, en la pestaña Paradas, las listas, el origen de una ruta
y sobre el mapa de la pestaña Mapa. La pestaña Mapa tiene su propio glifo,
`streets` (dos calles que se cruzan y un ómnibus). El glifo `map` sigue solo
en «Ver en Cómo Ir» y en la baldosa Cómo Ir de Servicios, que abren el mapa
del sitio oficial.

**Consecuencia.** En el mapa no hay gotas ni alfileres: cada parada guardada
es `stop` sobre una baldosa `tinta`, sin encender, y cada ómnibus con GPS es
una píldora con el ómnibus de píxeles y su número de línea (de lejos, un
punto). `StopResponse`
sigue sin la ubicación de la parada: el Mapa la toma del catálogo con proxy,
o de geoserver por número sin proxy, y la guarda en la parada
([El mapa viene dentro de la app](#el-mapa-viene-dentro-de-la-app)).

### El acento de las notificaciones es el azul del tablero

**Contexto.** Android oscurece el ámbar en la cortina clara hasta un marrón.

**Decisión.** El acento es `TimbreColors.tinta` (`color:` en
`NotificationService` y `NotificationIcon.backgroundColor` en
`AndroidBusWait`). Contra blanco tiene 17:1, y coincide con el widget y con
la baldosa del ícono. `test/brand_assets_test.dart` comprueba que
`notification_service.dart` no use `TimbreColors.ambar`.

**Consecuencia.** Las notificaciones no llevan ámbar. El fondo de la
notificación no se pinta ([10-superficies.md](10-superficies.md#ícono-y-color)).

### Ningún símbolo oficial

**Contexto.** Las tiendas tratan una app no oficial con escudo o logo del
STM como falsa afiliación y la bajan.

**Decisión.** Nada de escudo de Montevideo, bandera, Sol de Mayo, logos del
STM, de la Intendencia ni de las empresas de ómnibus, ni en la app ni en el
ícono, el widget, las capturas o la ficha de la tienda. Los accesos a Mi STM y
Recarga son texto, no logos.

**Consecuencia.** La app se presenta como no oficial en la ficha y en Info
([docs/store-listing.md](../store-listing.md)).

### El ámbar solo como luz de LED sobre azul noche

**Contexto.** Bloques planos amarillos y negros se leen en Uruguay como los
colores de un club de fútbol, y la app tiene que ser para todas las
hinchadas.

**Decisión.** El ámbar aparece como luz de LED sobre `noche` o `tinta`,
nunca como franjas o bloques sobre negro, y nunca sobre blanco.

**Consecuencia.** El texto sobre un relleno ámbar es siempre `tinta` (9.5:1),
nunca blanco ([02-color.md](02-color.md)).

### La letra grande no corta nada

**Contexto.** Muchas personas mayores usan la letra grande del sistema. Un
destino cortado o «MIS PARAD…» son usuarios perdidos, no un detalle.

**Decisión.** Desde 150 % (`TimbreText.largeFrom` = 1.5) las filas apilan
la hora debajo del destino y las barras de pestañas se desplazan. El título
de página se achica al ancho (`FittedBox`) en vez de terminar en «…». Las
pantallas se prueban con fuentes reales en un teléfono de 390 × 844 a 1×,
1.3× y 2× (`test/support/layout.dart`).

**Consecuencia.** Un texto nuevo tiene que pasar esas pruebas
([11-accesibilidad.md](11-accesibilidad.md)). El widget de Android es la
excepción: mide 3 × 2 celdas y corta el destino con «…» en una línea
([10-superficies.md](10-superficies.md#cómo-se-ve)).

### Riesgo: el sol

**Contexto.** Una pantalla oscura refleja en la calle.

**Decisión.** La apuesta es el contraste alto y los minutos grandes. No hay
modo de día.

**Consecuencia.** Si las reseñas dicen «no se ve», el modo de día se hace con
el mismo tema y los mismos tokens, no con colores sueltos.

---

## Datos y pantallas

### Los datos viejos se muestran como estimado

**Contexto.** Antes, si una actualización fallaba, la tarjeta perdía los
ómnibus y mostraba solo el error, aunque los datos de hace un minuto
siguieran sirviendo. Pero mostrarlos tal cual haría pasar minutos viejos por
datos en vivo.

**Decisión.** Si la actualización falla y el último tablero bueno tiene menos
de 5 min (`_staleFor` en `lib/ui/stops_page.dart`, contados desde que llegó
al teléfono, con el reloj del teléfono), la tarjeta muestra la nota en
`rojoLed` «No se pudo actualizar. Datos de las H:MM. Deslizá para
reintentar.» y debajo los ómnibus de ese tablero cuya hora esperada no pasó
hace más de 1 min (`_staleRowGrace`) en el reloj de la fuente (`fetchedAt`
más lo que el tablero lleva en el teléfono), como `ArrivalRow(stale: true)`: número en contorno, reloj
y «~20:01» en `TimbreText.scheduleTime`, sin `MinutosEnVivo` y sin ámbar,
aunque antes tuvieran GPS. Con 5 min o más, solo la nota «No se pudo
actualizar. Deslizá para reintentar».

Sin fallo, un tablero también envejece: al volver a Mis paradas desde
Horarios, Info o Servicios, hasta que llega el nuevo, o mientras el proxy
contesta 429 (`busy` deja el tablero como está). Si llegó hace 1 min o más
(`_liveFor`, dos vueltas de 30 s), sus filas pasan a estimado igual, sin las
que debían pasar hace más de 1 min y sin nota: `busy` no dice nada y un
refresco que está por llegar no es «No se pudo actualizar». Con 5 min o más,
o si no queda ninguna fila, la tarjeta muestra el indicador de carga, como
antes del primer tablero. Esta edad se cuenta desde que el tablero llegó al
teléfono (`_BoardView.receivedAt`, con `StopsPage.clock`), no desde
`fetchedAt`, que es la hora del servidor.

**Consecuencia.** Una fila vieja no se puede tocar ni muestra la campanita de
«Estoy esperando». El lector de pantalla dice «alrededor de las 20:01,
estimado». El mismo formato «~H:MM» es el del widget
([08-componentes.md](08-componentes.md), [07-textos.md](07-textos.md)). El
Mapa sigue la misma regla con sus ómnibus: sin encender después de un fallo o
con un tablero de 1 min o más, y fuera del mapa desde los 5 min. Como en Mis
paradas, la edad se cuenta desde que el tablero llegó al teléfono, con el
reloj del teléfono, para que uno con la hora corrida no apague los ómnibus
([09-pantallas.md](09-pantallas.md#mapa)).

### «NUEVA» y la fecha de lo no leído van en ámbar

**Contexto.** En Novedades, una noticia sin leer muestra el día en dígitos
Doto ámbar sobre una baldosa de LED y la etiqueta «NUEVA» en ámbar
(`_DateTile` y `_NewsRow` en `lib/ui/news_list.dart`). No son datos en vivo,
así que en principio la regla del ámbar no los permite.

**Decisión.** Se dejan así y cuentan como contador, igual que la insignia de
Novedades: marcan algo que todavía no viste. Cuando la noticia se lee, la
baldosa queda vacía, el día pasa a Fira Sans Extra Condensed en
`etiquetaCartel` y el mes a `tenue`.

**Consecuencia.** La lista de usos permitidos del ámbar incluye los
contadores ([02-color.md](02-color.md)). Un indicador de «no leído» nuevo
puede usar ámbar; un dato sin novedad, no.

### El brillo de `LiveDot`

**Contexto.** La regla original decía que no hay sombras salvo la luz de LED
de «LLEGANDO». Pero el punto de `LiveDot`, que acompaña los minutos con GPS,
también tiene un halo.

**Decisión.** Se deja: es luz de LED sobre un dato en vivo, lo mismo que
«LLEGANDO». En el código son dos valores distintos: `LlegandoChip` usa el
token `TimbreShadow.ledGlow` (ámbar al 35 %, desenfoque de 12 px) y `LiveDot`
calcula su propio halo (su color al 60 %, desenfoque de `0.45 × size`, 5.4 px
con el tamaño por defecto de 12).

**Consecuencia.** Solo brilla lo encendido: los datos en vivo y, con el
brillo de `PixelIcon(glow: true)`, la pestaña elegida, la campana de un
aviso activado y los mosaicos de Servicios. Una sombra nueva que no sea luz
de algo encendido no entra ([06-luz-y-movimiento.md](06-luz-y-movimiento.md)).

### El widget muestra el destino del ómnibus

**Contexto.** Una ruta guardada tiene un nombre que pone el usuario
(«Centro»), y cada ómnibus tiene su destino oficial («POCITOS»). El diseño
original mostraba «Línea 116 a POCITOS».

**Decisión.** `route_dest` es el `destination` del ómnibus; si viene vacío,
el nombre de la ruta (`RouteAlert.destinationName`). Lo escribe `WidgetFeed`
(`lib/services/home_widget_feed.dart`).

**Consecuencia.** El widget puede decir un destino distinto del nombre que el
usuario ve en su tarjeta de ruta. El aviso de ruta, en cambio, usa el nombre
de la ruta en el título («Línea 116 → Centro»)
([10-superficies.md](10-superficies.md#textos)).

### Los widgets de parada encienden la línea, no la hora

**Contexto.** Un widget se redibuja con datos de hasta 15 min (la consulta
de fondo) o de cuando tocaste actualizar: nunca es GPS en vivo. Con todo
apagado, en la pantalla de inicio se veía como una lista gris, no como
Timbre. El dueño del producto pidió más ámbar (2026-10-29).

**Decisión.** Se encienden la identidad y la acción: el número de línea
(contorno `ambarTenue`, cifras `ambar`), el cartel `stop`, el botón de
actualizar y los LEDs apagados del encabezado. La hora queda en `papel`,
con «~» y reloj `ambarTenue`, y nunca es un conteo («5 min»).

**Consecuencia.** En los widgets la forma separa lo vivo de lo estimado,
no el color: el relleno ámbar sigue siendo solo GPS en la app. Es la
excepción 3 de [02-color.md](02-color.md#excepciones-documentadas).

### El bloqueo va encima del `Navigator`

**Contexto.** La pantalla de bloqueo la dibujaba `HomePage` en lugar de sus
pestañas. Lo que estaba abierto encima —Horarios, Info, un diálogo, una
hoja— quedaba por encima del bloqueo, a la vista y al alcance.

**Decisión.** `AppLock` (`lib/ui/app_lock.dart`) va en `MaterialApp.builder`
(`lib/main.dart`), encima del `Navigator`. Antes del primer desbloqueo no
arma la app. Después la deja armada debajo de la pantalla de bloqueo, dentro
de `Offstage`, `TickerMode(enabled: false)` y `ExcludeFocus`: no se pinta, no
recibe toques ni foco, no anima y no está en el árbol de semántica.
`AppLock.routeGuard`, en `navigatorObservers`, le registra a cada ruta abierta
encima de la primera un `PopEntry` que no la deja cerrar mientras la app está
bloqueada. La pantalla de bloqueo tiene su propio `ScaffoldMessenger`, así que
los snack bars de la app se quedan con la app.

**Consecuencia.** Al desbloquear volvés a la misma página, hoja o diálogo, y
Mis paradas no se carga de cero. Como sigue armada, tiene que saber que está
tapada: `HomePage` le pasa `active: false`, a Mis paradas y al Mapa, mientras
`AppLock.of(context).locked`,
y el refresco al volver del segundo plano espera al primer cuadro
(`WidgetsBinding.endOfFrame`) para no pedir nada justo cuando aparece el
bloqueo. Con solo la pantalla principal debajo, el atrás de Android sigue
saliendo de la app. Lo que se agregue en `MaterialApp.builder` fuera de
`AppLock` no queda tapado.

### El bloqueo vuelve solo después del segundo plano

**Contexto.** Antes, cualquier estado que no fuera `resumed` contaba como una
salida, también `inactive`: un pedido de permiso del sistema alcanzaba para
que la app se bloqueara al volver. Y solo el navegador abierto desde
`HomePage` (Servicios, «Ver en Cómo Ir») marcaba la salida como propia: volver
del correo, de un enlace de Info o de «Ver más» de una novedad bloqueaba otra
vez.

**Decisión.** Solo bloquea `hidden` o `paused` seguido de `resumed`
(`AppLockState.didChangeAppLifecycleState`). Siguen las protecciones de antes:
no bloquea mientras está abierto el pedido del sistema (`_isAuthenticating`)
ni en los 2 s después de que se cerró. Toda apertura de otra app pasa por
`ExternalApps` (`lib/services/external_apps.dart`): `launch` para una URL
(`SystemBrowser.open`, el correo de Info, «Ver más» de una novedad) y `open`
para una llamada de plugin (los ajustes de la app desde «Paradas cercanas»).
`AppLock` escucha `ExternalApps.launches`, y una salida que empieza menos de
3 s después de una apertura no bloquea a la vuelta.

**Consecuencia.** Un enlace nuevo que se abra con `launchUrl` directo, sin
`ExternalApps`, vuelve a bloquear la app a la vuelta.
`test/app_lock_test.dart` prueba las salidas de hoy: navegador, correo,
enlace de una novedad y ajustes del sistema. Lo que cuenta es cuándo empezó
la salida, no cuánto duró: si desde la app que abriste vas a la pantalla de
inicio y volvés a Timbre MVD horas después, tampoco bloquea.

### El mapa viene dentro de la app

**Contexto.** La app no dibujaba mapas, y los arribos de `/v1` no traían la
posición de los ómnibus. La pestaña Mapa necesita un mapa base. Pedirle
teselas a un servidor de mapas (el de OpenStreetMap, uno pago o la
cartografía de la Intendencia) le diría a ese servidor qué zona mirás cada vez
que movés el mapa, y la app dependería de un servicio más.

**Decisión.** El mapa base viene con la app: un recorte de Protomaps de
Montevideo y alrededores (`assets/map/mvd-20261028.pmtiles`, 14,86 MB, zoom 0
a 15) con el estilo «Timbre Noche» (`assets/map/style_noche.json`), dibujado
por `flutter_map` y `flutter_map_vector_tiles`. No hay servidor de teselas:
`Basemap` (`lib/services/map/basemap.dart`) copia el archivo una vez a la
caché de la app y lee las teselas de esa copia. Encima van solo las paradas
guardadas y los ómnibus con GPS que vienen a ellas, con la posición de
`arrivals[].location`. Un ómnibus es uno solo aunque vaya a dos paradas: se
reconoce por su `tripId` (`bus-{idEmpresa}-{idBus}`). El Mapa no usa la
ubicación del teléfono.

**Consecuencia.** Mover o acercar el mapa no hace pedidos, tampoco sin
conexión. Los únicos pedidos del Mapa son los arribos de las paradas
guardadas, cada 30 s mientras está a la vista, y la ubicación de una parada
guardada que todavía no la tiene. La app pesa unos 15 MB más, y en el
teléfono el archivo está dos veces: en la app y en su copia de la caché, que
la app vuelve a copiar si el sistema la borra. El recorte envejece: se rehace
con los pasos de `assets/map/README.md`. «© OpenStreetMap» se ve siempre en
una esquina del mapa (licencia ODbL). El estilo está modificado y por eso no
se llama Protomaps. El mapa base no usa ámbar: queda para los ómnibus con
GPS. Las etiquetas del mapa salen con la fuente del sistema, no con Fira
([03-tipografia.md](03-tipografia.md)). Tema abierto: mostrar la flota de
toda la ciudad, y no solo los ómnibus que vienen a tus paradas, pide una ruta
nueva del contrato (por ejemplo `/v1/buses`, con la flota que ya baja
`ImGateway`), y espera a que el proxy esté desplegado.

---

## Backend

### Sin ruta por lotes

**Contexto.** Mis paradas muestra varias paradas a la vez. Una ruta que
devolviera todas juntas ahorraría pedidos, pero cada usuario tendría su
propia combinación, y la caché compartida del borde dejaría de servir.

**Decisión.** Una URL por parada (`GET /v1/stops/{id}/arrivals`, 15 s en la
caché del borde). La app pide cada parada una sola vez y todas en paralelo:
`MvdApiService.getBoards` quita los ids repetidos y comparte un pedido en
curso para la misma parada. Lo usan Mis paradas, el Mapa y la consulta de
fondo.

**Consecuencia.** Una parada popular se sirve a todos desde la misma copia
del borde. Con N paradas la app hace N pedidos; el límite por IP del proxy
es de 300 por minuto, contado solo en los pedidos que no salen de la caché
(`proxy/wrangler.jsonc`).

### Las paradas cercanas se calculan en el teléfono

**Contexto.** Para buscar paradas cercanas hay que comparar la posición con
las paradas. Mandar la posición a un servidor, aunque sea el del proyecto,
haría falsa la promesa de la política de privacidad.

**Decisión.** Con proxy, «Paradas cercanas» baja el catálogo de paradas
(`/v1/catalog/stops`, unos 660 KB, guardado un día en la caja `catalog` de
Hive) y busca en el teléfono las que están a 400 m o menos
(`NearbyStopsService.nearbyFrom`). No existe `/v1/stops/near`. Sin proxy,
la app pide a geoserver una caja centrada en la posición redondeada a 3
decimales, de 472 m de medio lado (los 400 m más 72 m, la media diagonal de
una celda de 0.001°), y filtra en el teléfono con la posición exacta.

**Consecuencia.** En una build con proxy la posición no sale del teléfono;
`test/proxy_privacy_test.dart` lo comprueba. Si el catálogo llega con
`linesAvailable: false`, no se recurre a geoserver. Ese catálogo no reemplaza
una copia del teléfono que tiene líneas, y la lista sigue con esa copia; sin
una copia con líneas, la lista se muestra sin líneas y el catálogo vence a los
15 min, lo mismo que en la caché del proxy.

### Sin cambio automático al modo directo

**Contexto.** Mientras el proxy no esté desplegado, la app puede hablar
directamente con los servicios de la Intendencia (modo directo). Se podría
caer al modo directo cuando el proxy falla.

**Decisión.** El modo se elige al compilar: con `--dart-define=MVD_PROXY_URL=…`
todo va al proxy; sin eso, todo va directo (`MvdApiService.source` en
`lib/services/mvd_api_service.dart`). No hay cambio en tiempo de ejecución.

**Consecuencia.** Una build con proxy nunca contacta `api.montevideo.gub.uy`,
`pci.montevideo.gub.uy` ni `geoserver.montevideo.gub.uy`
(`test/proxy_privacy_test.dart`, `test/proxy_bff_test.dart`). Si el proxy no
responde, la app muestra el error. Por eso el orden de despliegue es primero
el proxy y después la app ([contrato-v1.md](contrato-v1.md)).

### Rutas públicas eliminadas

**Contexto.** El proxy tenía `GET /v1/lines/{line}/buses` y
`GET /v1/catalog/lines`, que la app nunca llamaba. La primera era la única
ruta pública que podía hacer que el Durable Object cargara la flota de la API
oficial a pedido, y esa API permite 14 pedidos por minuto para todos.

**Decisión.** Se sacaron de `ROUTES` (`proxy/src/index.js`); ahora dan 404
`not_found`. El Durable Object `ImGateway` conserva `/lines/{line}/buses` y
`/catalog/lines` para uso interno, sin ruta pública que llegue a ellas.

**Consecuencia.** Los casos `removed.lines_buses` y `removed.catalog_lines`
de `proxy/contract/v1/cases.json` fijan el 404. Si alguna pantalla las
necesita, vuelven como ruta nueva del contrato.

### La ruta de horarios acepta una sola forma de hora: H:MM

**Contexto.** `8:05`, `08:05` y `8:5` serían tres claves de caché para el
mismo horario.

**Decisión.** La ruta es `/v1/stops/{id}/schedule/{day}/{H:MM}`: hora sin
cero adelante y minutos con dos cifras (`TIME` en `proxy/src/index.js`). Otra
forma, como `08:05`, da 404 `not_found` sin consultar la fuente; una hora
mayor que 23 da 400 `bad_request`. La app arma la ruta con
`ContractRules.schedulePath` (`lib/services/api/contract_rules.dart`).

**Consecuencia.** Cada horario tiene una sola copia en la caché. El vector
`proxy/contract/v1/vectors/schedule_path.json` y el caso
`schedule.noncanonical` fijan la regla en los dos lados.

### Las rutas reconocen el ómnibus por variante o por destino

**Contexto.** Las direcciones de una parada salen del índice de paradas del
proxy: las variantes de la capa WFS de geoserver unidas con `linevariants`
de la API oficial. Su nombre de destino puede no coincidir con el `destino`
de transporteRest, y los ids de variante tampoco son del todo consistentes
entre fuentes.

**Decisión.** Al guardar una ruta, cada chip HACIA guarda su destino en
`preferredDestinations` y sus variantes en `preferredVariantIds` (campo 11 de
Hive en `RouteAlert`). `RouteAlert.accepts` acepta un ómnibus si su línea
está en la ruta y coincide su variante o su destino. Las llegadas nunca se
cruzan con la flota de la API oficial por variante.

**Consecuencia.** Una ruta reconoce el ómnibus aunque el nombre del destino
cambie entre fuentes. Tema abierto: una ruta creada solo con datos de la API
oficial cuyo id de variante cambie después puede dejar de coincidir sin
avisar.

---

Ver también: [README.md](README.md), [13-en-el-codigo.md](13-en-el-codigo.md).
