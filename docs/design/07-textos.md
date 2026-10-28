# Textos

Cómo habla Timbre MVD: la voz, las palabras, los formatos de hora y el catálogo de los
mensajes que muestra la app hoy. Cada texto entre «» está copiado del código. Si cambiás un
texto en el código, cambialo también acá y en las pruebas que lo buscan (`find.text`,
`find.bySemanticsLabel`).

Ver también:
- [11-accesibilidad.md](11-accesibilidad.md): las frases que escuchan los lectores de pantalla.
- [10-superficies.md](10-superficies.md): notificaciones y widget en detalle.
- [08-componentes.md](08-componentes.md) y [09-pantallas.md](09-pantallas.md): dónde aparece cada texto.
- [contrato-v1.md](contrato-v1.md): los errores del proxy y cómo llegan a la app.

## Voz

- Español de Montevideo, con voseo. Imperativo: «Tocá», «Deslizá», «Revisá», «Activá»,
  «Permití», «Probá», «Elegí», «Buscá», «Agregá», «Recargá», «Planificá», «Confirmá». Con
  pronombre: «Activalo», «Configuralo», «Autenticate». Presente: «abrís», «esperás», «elegís»,
  «tengas».
- Nunca tuteo («Revisa», «puedes») ni usted («Revise»).
- Frases cortas que dicen una sola cosa. Sin signos de exclamación, sin emoji, sin tono de
  publicidad.
- La app habla en primera persona del plural solo cuando promete un aviso: «Te avisamos cuando
  el 121 esté a 5 min», «Te avisamos a la hora estimada».

## Palabras

| Usá | No uses | En la app |
|---|---|---|
| ómnibus (igual en singular y plural) | autobús, colectivo, bus | «Sin ómnibus próximos» |
| parada | estación | «Agregar parada» |
| línea | ruta, recorrido (para el número) | «Línea 121» |
| ruta: un viaje guardado de una parada de origen a un destino tuyo | — | «Agregar ruta», «Sin rutas guardadas» |
| horario, horarios teóricos: lo que no tiene GPS | — | «Horarios teóricos, sin ubicación GPS» |
| tiempo de arribo | ETA, tiempo de llegada | «Tiempos de arribo, horarios por parada…» (Info) |
| con GPS, sin GPS | en vivo, tiempo real | «Según horario 20:17, sin GPS todavía» |
| aviso | notificación push | «Activar avisos», «Aviso 5 min antes» |
| Intendencia de Montevideo | IM, IMM | «Publicadas por la Intendencia de Montevideo (Cómo Ir).» |
| setiembre, SET | septiembre | fechas de Novedades |
| tienda (Google Play, App Store) | store | textos de las tiendas, `docs/store-listing.md` |

La tabla vale para los textos de la app. En estas páginas, «vivo» (un dato en vivo),
«llegando», «horario» y «estimado» son los nombres de los estados de una fila
([08-componentes.md](08-componentes.md)); en los textos de la app se dice «con GPS» o «sin GPS»,
nunca «en vivo».

«Alerta» quedó en dos lugares: el vacío de Rutas («Tocá + para guardar una alerta de salida.»)
y el canal de Android «Alertas de ómnibus». En el resto de la app se dice «aviso».

### Nombres que vienen de la API

- Las paradas y los destinos se muestran como los escribe la API, en mayúsculas y con la «y»
  en minúscula: «SAN JOSE y ANDES», «PUNTA CARRETAS». La app no les cambia nada en pantalla, ni
  mayúsculas ni tildes.
- Los lectores de pantalla los escuchan con `spokenName` («San Jose y Andes»): ver
  [11-accesibilidad.md](11-accesibilidad.md).
- Lo que escribe la persona (el destino de una ruta, por ejemplo «Trabajo») se muestra y se lee
  tal cual.
- Las líneas, como las da la fuente: «121», «CE1», «D10». En «Paradas cercanas» y «Buscar por
  calles» los nombres vienen de geoserver y pueden diferir de los de la tarjeta («M-A», «PA»,
  «124 SD»).
- Una parada sin nombre se llama «Parada 574». Pasa cuando se guardó sin conexión o cuando el
  catálogo no tiene sus calles.
- El número de parada se escribe «#574» debajo del nombre y en las listas, « · 574» en el
  subtítulo de Horarios y «Parada 574» en lo que escucha el lector de pantalla.

### Carteles y rótulos

- Los carteles en Doto van en mayúsculas: «MIS PARADAS» (el título de página se pasa a
  mayúsculas en `PageTitleBar`), «SIN PARADAS», «LLEGANDO», «BLOQUEADA», «NO OFICIAL», «TIMBRE
  MVD».
- Los rótulos de sección en Fira también van en mayúsculas: «LÍNEAS», «HACIA», «DÍAS», «FUENTE
  DE DATOS», «NUEVA».
- El lector de pantalla escucha la frase normal («Mis paradas», «Sin paradas guardadas»).

### Signos

| Signo | Uso | Ejemplos |
|---|---|---|
| `·` | separa datos en una misma línea | «#5109 · 48 m · 124, 125», «Aviso 5 min antes · Lun a Vie 7:30–8:30», «SAN JOSE y ANDES · con GPS» |
| `→` | hacia dónde va | «→ Trabajo» (tarjeta de ruta), «121 → PUNTA CARRETAS», «Esperando el 121 → PUNTA CARRETAS» |
| `—` (raya) | título de notificación | «Línea 121 — 3 min» |
| `–` (semiraya) | rango de horas | «7:30–8:30» |
| `…` (un solo carácter) | algo en curso | «Buscando parada…», «Sin conexión, reintentando…» |
| `~` | hora estimada | «~20:17» |
| `Ej: ` | ejemplo dentro de un campo | «Ej: 1234», «Ej: San José y Andes», «Ej: Centro» |
| `*` | campo obligatorio (en pantalla) | «Parada de origen *», «Destino *»; el lector dice «obligatorio» |

## Hora y tiempo

| Qué | En pantalla | Dónde | De dónde sale |
|---|---|---|---|
| Ómnibus con GPS en camino | «12» en Doto + «min» | `ArrivalRow` → `MinutosEnVivo` | `BusArrival.etaMinutes` ← /v1 `etaMinutes` |
| Ómnibus con GPS en la parada | «LLEGANDO» | `LlegandoChip`, `CartelTira` | `etaMinutes <= 0` con GPS |
| Horario teórico | reloj + «20:17» | `ArrivalRow` sin GPS | `BusArrival.clockTime` ← /v1 `clockTime` |
| Estimado, de datos viejos | reloj + «~20:01» | `ArrivalRow(stale: true)`; widget «~14:32» | `clockTime` del último tablero que llegó |
| Hora de los datos | «Datos de las 19:52» | nota de error de la tarjeta | `ArrivalsBoard.fetchedAt` con `MvdApiService.montevideoClock` |
| Pasada de horario | «8:09» | Horarios | `ScheduledPass.time` ← /v1 `passes[].time` |
| Encabezado de hora | «8 h» | Horarios | `ScheduledPass.hhmm ~/ 100` |
| Hora de inicio | «Desde 8:05» | Horarios | la hora elegida |
| Ventana de un aviso | «Siempre», «Lun a Vie 7:30–8:30», «Sáb, Dom», «22:00–1:00» | fila «Aviso … min antes» | `AlertSchedule.label` |
| Horas de la ventana | «Desde 7:00», «Hasta 9:00» | ajustes de aviso | `AlertSchedule.time` |
| Fecha de una novedad | «02» + «OCT» en el recuadro; «02/10/2026» en el detalle | Novedades | /v1 `publishedAt`, en la hora del teléfono |
| Distancia | «48 m» | «Paradas cercanas» | calculada en el teléfono |

Reglas:

- **Reloj «H:MM».** 24 horas, la hora sin cero adelante y los minutos con dos cifras: «8:07»,
  «20:17», «0:05». Vale para `clockTime`, `montevideoClock`, las pasadas de Horarios,
  `AlertSchedule.time` y el botón «Desde» de Horarios. El selector de hora de Horarios fuerza
  24 horas (`alwaysUse24HourFormat: true`). El de los ajustes de aviso usa el formato del
  teléfono, pero los botones muestran igual «H:MM».
- **Cuenta regresiva solo con GPS.** «12 min» sale únicamente de un ómnibus con GPS. Un horario
  teórico es siempre una hora de reloj, nunca «en 20 min».
- **«min» no cambia.** Se escribe «1 min» y «12 min». El lector de pantalla dice «1 minuto» y
  «12 minutos».
- **«~» solo para estimados.** Lo usan las filas viejas (después de un fallo, o de un tablero
  que llegó hace 1 min o más), el widget y el título del recordatorio de iOS
  («Línea 121 — ~5 min»). Un estimado nunca va en ámbar.
- **La hora de arribo viene hecha.** `clockTime` sale de `horaDesc` de transporteRest. Con proxy
  lo arma el Worker; sin proxy, el adaptador del teléfono con la misma regla
  (`ContractRules.arrival`). Si la fila no trae `horaDesc`, se usa `time` en UTC−3, y solo si
  tampoco trae `time` entra el reloj del que responde. La pantalla nunca calcula la hora sumando
  minutos al reloj del teléfono. «Datos de las …» usa UTC−3 fijo
  (`ContractRules.montevideoClock`). Si Uruguay vuelve al horario de verano, hay que cambiarlo en
  los dos lados del contrato ([contrato-v1.md](contrato-v1.md)).
- **Excepción.** `CartelParada`, que hoy no usa ninguna pantalla, muestra «Actualizado 08:05»
  con cero adelante y en la hora del teléfono (`_hhmm` en `lib/ui/widgets/cartel.dart`).

## Errores: qué pasó y qué hacer

Un mensaje de error dice qué falló y qué puede hacer la persona, en dos frases cortas: «No se
pudo cargar el horario. Revisá la conexión.» Empieza por «No se pudo…», «No existe…» o «No
hay…», y la segunda frase arranca con un verbo en voseo.

Dónde se muestra (colores en [02-color.md](02-color.md)):

- **Dentro de una tarjeta o debajo de un campo:** un LED rojo. Ícono `warning` y texto en
  `rojoLed`: la nota de la tarjeta, las líneas de error de los diálogos, Horarios.
- **Sobre una lista que se sigue viendo:** el panel `avisoNoche` con borde `ambarTenue` e ícono
  en `ambar`. Lo usan el fallo de Novedades y el aviso de GPS parcial.
- **Después de una acción:** un snack bar. En `lib/ui/stops_page.dart` (`_showError`) lleva el
  ícono `warning` en `rojoLed`. En `home_page.dart`, `info_page.dart`, `app_lock.dart` y
  `news_list.dart` es texto solo.

### Mis paradas: tarjetas de parada y de ruta

Código: `_buildArrivals` y `_buildGpsWarning` en `lib/ui/stops_page.dart`.

| Situación | Texto | Cómo se ve |
|---|---|---|
| Falló la última actualización y no hay datos de menos de 5 min | «No se pudo actualizar. Deslizá para reintentar» | nota roja |
| Falló, pero hay datos de menos de 5 min | «No se pudo actualizar. Datos de las 19:52. Deslizá para reintentar.» y debajo las filas «~H:MM» | nota roja y filas estimadas |
| No falló, pero el último tablero llegó hace 1 min o más (al volver a Mis paradas, o con `busy`) | ninguno: solo las filas «~H:MM» | filas estimadas, sin nota; desde los 5 min, o si no queda ninguna fila, el indicador de carga |
| La parada ya no existe (`notFound`) | «Esta parada ya no existe. Deslizá la tarjeta para borrarla.» | nota roja, sin filas |
| No viene ningún ómnibus, o ninguno pasa el filtro de la ruta | «Sin ómnibus próximos» | nota en `tenue` con el ícono `bus` |
| Demasiados pedidos (`busy`) | ninguno: la app saltea actualizaciones hasta que pasa `Retry-After` | la tarjeta queda como estaba, hasta que el tablero cumple 1 min (fila de los estimados sin fallo) |
| Carga inicial, o un tablero sin fallo de 5 min o más | ninguno: un indicador de progreso de 18 px | — |
| Un operador manda GPS de menos del 70 % de sus ómnibus | «Datos GPS parciales (CUTCSA 60 %): algunos tiempos pueden ser horarios teóricos o menos precisos.» | panel `avisoNoche` arriba de la lista |

En el aviso de GPS van solo los operadores con datos parciales, separados por coma, con un
espacio antes de «%» (`BusStatusService.partialWarning`).

### Agregar parada

Código: `_addStop` y `_AddStopDialogState` en `lib/ui/stops_page.dart`.

| Situación | Texto | Cómo se ve |
|---|---|---|
| Número imposible (0 o ceros; el campo admite hasta 7 cifras) | «No existe la parada 0. Revisá el número.» | snack bar con ícono rojo, sin pedido a la red |
| La parada ya está guardada | «La parada 574 ya está guardada» | snack bar con ícono rojo |
| Buscando un número escrito | «Buscando parada…» | snack bar |
| La parada no existe | «No existe la parada 574. Revisá el número.» | snack bar con ícono rojo |
| Cualquier otro fallo al buscar | ninguno: se guarda como «Parada 574» y se completa en un arranque posterior (`healPlaceholderStops`) | — |
| No cargó el catálogo de calles | «No se pudo cargar la lista de paradas. Revisá la conexión.» | texto rojo de 13 px |
| Ninguna parada coincide | «Ninguna parada coincide» | texto `etiquetaCartel` |
| Más de 50 coincidencias | «Hay más de 50: agregá la otra calle» | texto `etiquetaCartel` |
| Ubicación del teléfono apagada | «Activá la ubicación del teléfono para buscar paradas cercanas.» | texto rojo |
| Permiso de ubicación negado | «Permití la ubicación para buscar paradas cercanas.» | texto rojo |
| Permiso negado para siempre | «El permiso de ubicación está desactivado para la app. Activalo en Ajustes.» y el botón «Abrir ajustes» | texto rojo |
| No hay posición | «No se pudo obtener tu ubicación. Probá de nuevo.» | texto rojo |
| No cargaron las paradas cercanas | «No se pudieron cargar las paradas cercanas. Revisá la conexión.» | texto rojo |
| Ninguna parada en 400 m | «No hay paradas a menos de 400 m» | texto `etiquetaCartel` |

### Agregar ruta

Código: `_AddRouteDialogState` y `_addRouteManually` en `lib/ui/stops_page.dart`.

| Situación | Texto |
|---|---|
| Antes de buscar la parada | «Buscá la parada para elegir sus líneas» |
| La parada no existe | «No existe la parada 574. Revisá el número.» (rojo en el diálogo; snack bar si se guarda sin haber buscado) |
| Cualquier otro fallo al buscar | «No se pudieron cargar las líneas. Revisá la conexión.» |
| Ayuda debajo de los chips | «Si no elegís ninguna, se incluyen todas.» |
| Guardar sin haber buscado | «Buscando parada…»; si falla la red, el origen queda como «Parada 574», sin mensaje |

### Estoy esperando

Código: `_showWaitSheet` en `lib/ui/stops_page.dart`.

| Situación | Texto |
|---|---|
| El aviso empezó | «Te avisamos cuando el 121 esté a 5 min» |
| El ómnibus ya está dentro del margen | «El 121 ya está a 3 min» |
| No se pudo empezar | «No se pudo activar el aviso. Revisá que las notificaciones estén permitidas y probá de nuevo.» |
| Nota en Android | «Verás un aviso fijo mientras la app sigue al ómnibus, también con la pantalla apagada. Avisa cuando el ómnibus tiene GPS.» |
| Nota en iOS | «Te avisamos a la hora estimada. Si abrís la app mientras esperás, el aviso se ajusta al GPS.» |
| Viaje sin GPS | «Según horario 20:17, sin GPS todavía · SAN JOSE y ANDES» |
| Viaje con GPS | «SAN JOSE y ANDES · con GPS» |

### Ajustes de aviso

Código: `_AlertSettingsSheetState` en `lib/ui/stops_page.dart`.

| Situación | Texto |
|---|---|
| Ningún día elegido | «Elegí al menos un día» (y «Guardar» queda desactivado) |
| «Desde» igual a «Hasta» | «Elegí horas distintas» (y «Guardar» queda desactivado) |
| Nota en Android | «Se revisa cada 15 min aprox. y avisa solo por ómnibus con GPS.» |

### Horarios

Código: `lib/ui/schedule_page.dart`.

| Situación | Texto |
|---|---|
| No cargó | «No se pudo cargar el horario. Revisá la conexión.» y el botón «Reintentar» |
| Sin pasadas | cartel «SIN PASADAS» y «Probá con otro día o con una hora más temprano.» |
| Nota fija | «Horarios teóricos, sin ubicación GPS» |
| La lista pasa la medianoche | «Después de medianoche» |

### Novedades

Código: `lib/ui/news_list.dart`.

| Situación | Texto |
|---|---|
| No se pudo actualizar | «No se pudo actualizar. Deslizá para reintentar» en el panel `avisoNoche`, arriba de lo guardado |
| Sin novedades | cartel «SIN NOVEDADES» y «Los desvíos y cambios de recorrido aparecen acá.» |
| Pie de la lista | «Publicadas por la Intendencia de Montevideo (Cómo Ir).» |
| El enlace no se abrió | «No se pudo abrir el enlace. Probá de nuevo más tarde.» |

### Servicios, Info, Privacidad y bloqueo

Código: `lib/ui/home_page.dart`, `lib/ui/info_page.dart`, `lib/ui/privacy_policy_page.dart`,
`lib/ui/app_lock.dart`, `lib/ui/lock_screen.dart`.

| Situación | Texto |
|---|---|
| «FUENTE DE DATOS» de Info, solo con proxy | «Aire acondicionado y cero emisiones: API de transporte público de Montevideo.», «Las consultas pasan por el servidor del proyecto, que no guarda datos personales.» |
| Enlace a la política, en Info | «Política de privacidad»; abre la pantalla «Privacidad» |
| Pantalla Privacidad | el texto de `docs/privacy-policy.md` tal cual, sin las líneas `>`; cada `## ` en mayúsculas («RESUMEN») |
| No se abrió el navegador | «No se pudo abrir el navegador. Revisá que tengas uno activado.» |
| No se abrió el correo | «No se pudo abrir el correo. Revisá que tengas una app de correo configurada.» |
| El teléfono no tiene bloqueo de pantalla | «Tu dispositivo no tiene bloqueo de pantalla. Configuralo en Ajustes.» |
| Pedido del sistema al activar el bloqueo | «Confirmá para activar el bloqueo biométrico» |
| Pedido del sistema al abrir la app | «Autenticate para acceder a Timbre MVD» |
| Bloqueo activado o desactivado | «Bloqueo biométrico activado», «Bloqueo biométrico desactivado» |
| Pantalla de bloqueo | «BLOQUEADA», «Tus paradas y rutas guardadas están protegidas», «Desbloquear» |

### De `ApiFailure` al texto

La capa de datos devuelve un `ApiFailure` (`lib/services/api/api_result.dart`). Cada pantalla
elige el texto; la tabla junta los casos. Los códigos HTTP que llevan a cada fallo están en
[contrato-v1.md](contrato-v1.md).

| `ApiFailure` | Tarjeta | Agregar parada (número) | Agregar ruta | Horarios | Novedades | Calles y cercanas |
|---|---|---|---|---|---|---|
| `offline`, `timeout`, `failed` | «No se pudo actualizar. Deslizá para reintentar» (con «Datos de las …» si hay datos de menos de 5 min) | se guarda «Parada N», sin mensaje | «No se pudieron cargar las líneas. Revisá la conexión.» | «No se pudo cargar el horario. Revisá la conexión.» | panel «No se pudo actualizar…» | se usa la copia guardada del catálogo; si no hay, «No se pudo cargar la lista de paradas…» o «No se pudieron cargar las paradas cercanas…» |
| `notFound` | «Esta parada ya no existe. Deslizá la tarjeta para borrarla.» | «No existe la parada N. Revisá el número.» | «No existe la parada N. Revisá el número.» | «No se pudo cargar el horario. Revisá la conexión.» | — | — |
| `busy` | ninguno; se saltean actualizaciones hasta `Retry-After` | se guarda «Parada N», sin mensaje | «No se pudieron cargar las líneas. Revisá la conexión.» | «No se pudo cargar el horario. Revisá la conexión.» | panel «No se pudo actualizar…» | igual que `offline` |
| `unavailable` | — | — | — | — | — | sin proxy, el campo «Buscar por calles» no aparece; con proxy sin configurar, igual que `offline` |

El estado de GPS no muestra errores: si falla, queda el último estado bueno, y si nunca llegó
no se muestra nada.

## Estados que no son errores

- **Cargando.** Indicadores de progreso sin texto. El único texto de espera es «Buscando
  parada…».
- **Vacío.** Cuatro carteles de `TimbreEmptyState` (ver [08-componentes.md](08-componentes.md)):

  | Cartel | Lo que escucha el lector | Detalle |
  |---|---|---|
  | «SIN PARADAS» | «Sin paradas guardadas» | «Tocá + para agregar una parada y recibir un aviso cuando llegue el ómnibus.» |
  | «SIN RUTAS» | «Sin rutas guardadas» | «Tocá + para guardar una alerta de salida.» |
  | «SIN NOVEDADES» | «Sin novedades» | «Los desvíos y cambios de recorrido aparecen acá.» |
  | «SIN PASADAS» | «Sin pasadas para este horario» | «Probá con otro día o con una hora más temprano.» |

- **Confirmaciones.** Snack bars: «Te avisamos cuando el 121 esté a 5 min», «Bloqueo biométrico
  activado».

## Notificaciones y widget

El detalle (canales, íconos, cuándo sale cada una) está en [10-superficies.md](10-superficies.md).
Los textos son estos; los nombres de parada van como los escribe la API.

| Dónde | Título | Texto |
|---|---|---|
| Aviso de parada y alerta de «Estoy esperando» (`NotificationService.showBusAlert`) | «Línea 121 — 3 min»; con 0 min o menos, «Línea 121 — llegando» | «Tu ómnibus llega en 3 min a SAN JOSE y ANDES»; con 1 min o menos, «Tu ómnibus está llegando a SAN JOSE y ANDES» |
| Aviso de ruta (`showRouteAlert`) | «Línea 121 → Trabajo» | «Sale en 3 min desde SAN JOSE y ANDES»; con 1 min o menos, «Tu ómnibus está llegando a SAN JOSE y ANDES» |
| Recordatorio de «Estoy esperando» en iOS (`scheduleWaitReminder`) | «Línea 121 — ~5 min» | «Debería llegar en unos 5 min a SAN JOSE y ANDES» |
| Aviso fijo de «Estoy esperando» en Android (`BusWait.title`, `statusText`) | «Esperando el 121 → PUNTA CARRETAS» o «Esperando el 121» | «Llega en 12 min · SAN JOSE y ANDES», «Llegando · …», «Según horario 20:17, sin GPS todavía · …», «Sin datos del ómnibus por ahora · …», «Sin conexión, reintentando… · …»; botón «Dejar de esperar» |
| Canales de Android | «Alertas de ómnibus» | «Avisos cuando tu ómnibus está por llegar» |
| | «Esperando un ómnibus» | «Aviso fijo mientras la app sigue a tu ómnibus («Estoy esperando»)» |
| Widget de Android | — | fila «116 POCITOS ~14:32»; vacío «Sin próximos ómnibus en tus rutas»; botones «Mi STM» y «Recarga» |

## Lo que hoy no sigue estas reglas

Lo dejamos anotado para corregirlo en el código cuando se toque ese archivo:

- «La parada 574 ya está guardada» dice qué pasó, pero no qué hacer, y no lleva punto final.
- «No se pudo actualizar. Deslizá para reintentar» va sin punto final en la tarjeta y en
  Novedades; con «Datos de las …» lleva punto final.
- «Alerta» y «aviso» conviven (ver «Palabras»).
- En «Agregar ruta», «Guardar» sin número de parada o sin destino no hace nada y no dice por qué.
- Si una parada guardada dejó de existir, Horarios pide «Revisá la conexión.», porque
  `MvdApiService.getSchedule` devuelve `null` para cualquier fallo.

## Antes de agregar un texto

- [ ] Voseo, «ómnibus», «parada», «tiempo de arribo».
- [ ] Si es un error: qué pasó y qué hacer, en ese orden.
- [ ] Horas en «H:MM»; «~» solo para estimados; cuenta regresiva solo con GPS.
- [ ] Una frase para el lector de pantalla si el texto está en un cartel o en una fila
      ([11-accesibilidad.md](11-accesibilidad.md)).
- [ ] Sin emoji.
- [ ] Este archivo y las pruebas que buscan el texto, actualizados.
