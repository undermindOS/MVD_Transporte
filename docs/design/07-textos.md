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
  el 121 esté a 5 min», «Te avisamos a la hora estimada». La excepción es la bienvenida, cuando
  dice qué no hace el proyecto con tus datos: «No registramos lo que hacés ni lo que buscás. Sin
  publicidad, analíticas ni rastreo.», «Lo que guardás queda en tu teléfono, no en servidores
  nuestros.».

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
  `rojoLed`: la nota de la tarjeta, las líneas de error de los diálogos, Horarios, el mapa base
  que no se pudo abrir y la hoja de una parada del Mapa.
- **Sobre una lista o un mapa que se siguen viendo:** el panel `avisoNoche` con borde
  `ambarTenue` e ícono en `ambar`. Lo usan el fallo de Novedades, el aviso de GPS parcial y el
  fallo del Mapa.
- **Después de una acción:** un snack bar. En `lib/ui/stops_page.dart` (`_showError`) lleva el
  ícono `warning` en `rojoLed`. En `home_page.dart`, `info_page.dart`, `news_list.dart` y
  `map/mapa_page.dart` es texto solo.
- **En el bloqueo:** en la misma pantalla, como región en vivo, porque encima del `Navigator` no
  hay diálogos: «Código incorrecto», la espera y la nota de un teléfono sin bloqueo de pantalla.
  El error del código va en `rojoLed`; la nota, que no es un error, en `etiquetaCartel`. Las
  páginas del código de Info hacen lo mismo.

**Excepción.** Las notas del Mapa sobre paradas sin ubicar («No se pudo ubicar en el mapa la
parada 574.», «No se pudieron ubicar en el mapa 2 paradas.») van en `tenue` y tienen una sola
frase: no hay nada que hacer, porque la app vuelve a buscar esas paradas sola, como mucho cada
10 minutos, al volver al Mapa.

**Excepción.** Los mensajes del teclado del código son cortos y van sin punto final: «Código
incorrecto» no dice qué hacer, porque el teclado queda listo para probar otra vez, y «Demasiados
intentos. Probá de nuevo en 30 s» cuenta los segundos que faltan.

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

### Mapa

Código: `lib/ui/map/mapa_page.dart` y `lib/ui/map/map_sheets.dart`.

| Situación | Texto | Cómo se ve |
|---|---|---|
| Sin paradas guardadas | cartel «SIN PARADAS», «Sin paradas guardadas» y «Agregá una parada en Mis paradas para ver acá los ómnibus con GPS que se acercan.» | `TimbreEmptyState` |
| No se pudo abrir el mapa base | «No se pudo abrir el mapa. Probá de nuevo.» y el botón «Reintentar» | ícono rojo y texto `papel` |
| Ninguna parada se pudo actualizar | «No se pudo actualizar. Revisá la conexión.» y el botón «Reintentar» | panel `avisoNoche` arriba del mapa; los últimos ómnibus quedan sin encender |
| Ningún ómnibus con GPS viene a las paradas guardadas | «Ahora ningún ómnibus con GPS viene a tus paradas.» | nota en `tenue` con el ícono `bus` |
| Una parada guardada no se pudo ubicar | «No se pudo ubicar en el mapa la parada 574.» | nota en `tenue` con el ícono `stop` |
| Dos o más | «No se pudieron ubicar en el mapa 2 paradas.» | nota en `tenue` con el ícono `stop` |
| Demasiados pedidos (`busy`) | ninguno: el Mapa saltea actualizaciones hasta que pasa `Retry-After` | — |
| Atribución, siempre a la vista | «© OpenStreetMap» | rótulo abajo a la izquierda; abre `https://www.openstreetmap.org/copyright` |
| Hoja de un ómnibus, una fila por parada | «a la parada 574 · SAN JOSE y ANDES» y los minutos, o «~19:56» | — |
| Hoja de una parada que no se pudo actualizar | «No se pudo actualizar. Revisá la conexión.» | nota roja |
| Hoja de una parada sin ómnibus | «Sin ómnibus próximos» | nota en `tenue` con el ícono `bus` |

### Servicios, Info y Privacidad

Código: `lib/ui/home_page.dart`, `lib/ui/info_page.dart`, `lib/ui/code_pages.dart`, `lib/ui/privacy_policy_page.dart`.

| Situación | Texto |
|---|---|
| «FUENTE DE DATOS» de Info, siempre | «Tiempos de arribo, horarios por parada, novedades del transporte, estado del GPS y posición de los ómnibus: servicios en línea de la Intendencia de Montevideo, los mismos que usa Cómo Ir.», «Mapa: © colaboradores de OpenStreetMap, con licencia ODbL. Viene dentro de la app.» |
| «FUENTE DE DATOS» de Info, solo con proxy | «Aire acondicionado y cero emisiones: API de transporte público de Montevideo.», «Las consultas pasan por el servidor del proyecto, que no guarda datos personales.» |
| Enlace a la política, en Info | «Política de privacidad»; abre la pantalla «Privacidad» |
| Pantalla Privacidad | el texto de `docs/privacy-policy.md` tal cual, sin las líneas `>`; cada `## ` en mayúsculas («RESUMEN») |
| No se abrió el navegador | «No se pudo abrir el navegador. Revisá que tengas uno activado.» |
| No se abrió el correo | «No se pudo abrir el correo. Revisá que tengas una app de correo configurada.» |
| Fila del bloqueo, en Info | «Código de acceso»; debajo, «La app lo pide al abrirse» (encendida) o «Protegé tus paradas y rutas guardadas» (apagada) |
| Con un código, en Info | «Cambiar código»; «Desbloquear con huella» y debajo «El código queda de respaldo» |
| Páginas del código | título «CÓDIGO»; cartel «CÓDIGO NUEVO» con «Elegí 4 cifras para abrir la app.»; cartel «TU CÓDIGO» (el lector oye «Tu código») con «Ingresá tu código actual.» y «¿Olvidaste el código?» |
| Código equivocado o espera, en «TU CÓDIGO» | los del bloqueo: «Código incorrecto», «Demasiados intentos. Probá de nuevo en 30 s» |
| Pedido del sistema de «¿Olvidaste el código?», en «TU CÓDIGO» | «Usá el bloqueo de tu teléfono para cambiar el código» o «Usá el bloqueo de tu teléfono para desactivar el código» |
| «¿Olvidaste el código?» en «TU CÓDIGO», en un teléfono sin bloqueo de pantalla | «Tu teléfono no tiene bloqueo de pantalla, así que no puede confirmar que sos vos. Sin el código no se puede cambiar ni desactivar.» |
| Pedido del sistema al encender el desbloqueo rápido (también en la bienvenida) | «Confirmá para abrir Timbre MVD con tu huella» |
| Después de cambiar el bloqueo | «Código activado», «Código cambiado», «Bloqueo desactivado», «Desbloqueo con huella activado», «Desbloqueo con huella desactivado» |
| El teléfono no tiene ninguna huella ni rostro | «Tu teléfono no tiene una huella ni un rostro configurados.» |

Con Face ID o Touch ID, «huella» y «tu huella» pasan a «Face ID» o «Touch ID»
(`BiometricKind.label` y `phrase`): «Desbloquear con Face ID», «Confirmá para abrir Timbre MVD con
Face ID», «Desbloqueo con Face ID activado». En Android dice siempre «huella».

### Bloqueo

Código: `lib/ui/app_lock.dart`, `lib/ui/lock_screen.dart`, `lib/ui/passcode_entry.dart`,
`lib/services/device_auth.dart`.

| Situación | Texto |
|---|---|
| Pantalla del código | cartel «BLOQUEADA» (el lector oye «Aplicación bloqueada») e «Ingresá tu código» |
| Código equivocado | «Código incorrecto» |
| Espera, desde el quinto código equivocado seguido | «Demasiados intentos. Probá de nuevo en 30 s», con los segundos que faltan |
| Teclas sin cifra (lo que oye el lector) | «Borrar»; «Desbloquear con huella», «Desbloquear con Face ID» o «Desbloquear con Touch ID» |
| Debajo del teclado | «¿Olvidaste el código?» |
| Pedido del sistema del desbloqueo rápido | «Desbloqueá Timbre MVD» |
| Pedido del sistema de «¿Olvidaste el código?» | «Usá el bloqueo de tu teléfono para entrar a Timbre MVD» |
| Código nuevo, después de olvidarlo | cartel «CÓDIGO NUEVO» (el lector oye «Código nuevo»), «Elegí 4 cifras nuevas para abrir la app.» y «Ahora no» |
| Repetir un código nuevo (también en la bienvenida y en Info) | cartel «REPETILO» (el lector oye «Repetí el código»), «Ingresá el mismo código otra vez.» y «Volver» |
| Los dos códigos no coinciden | «No coinciden. Elegí el código de nuevo.» |
| Sin bloqueo de pantalla, en Android | «Tu teléfono no tiene bloqueo de pantalla, así que no puede confirmar que sos vos. Para entrar sin el código, borrá los datos de Timbre MVD en los ajustes del teléfono: se borran tus paradas y rutas.» |
| Sin bloqueo de pantalla, en iOS | «Tu teléfono no tiene bloqueo de pantalla, así que no puede confirmar que sos vos. Para entrar sin el código, borrá Timbre MVD y volvé a instalarla: se borran tus paradas y rutas.» |
| Bloqueo anterior, pantalla | «BLOQUEADA», «Tus paradas y rutas guardadas están protegidas», «Desbloquear» |
| Bloqueo anterior, pedido del sistema | «Autenticate para acceder a Timbre MVD» |
| Dentro del pedido del sistema, en Android (`AndroidAuthMessages`) | título «Timbre MVD», «Confirmá que sos vos» y, solo con huella o cara, el botón «Usar código». Con el bloqueo del teléfono no hay botón de la app: el sistema ofrece su propio PIN o patrón |
| Dentro del pedido del sistema, en iOS (`IOSAuthMessages`) | «Usar código» después de un intento fallido de Face ID (solo con huella o cara); el aviso propio del plugin después de muchos intentos, «Face ID y Touch ID se bloquearon por muchos intentos. Bloqueá y desbloqueá el teléfono para volver a usarlos.», con «Aceptar» |

### Bienvenida

Código: `lib/ui/welcome/`.

| Paso | Texto |
|---|---|
| Todos | «Paso 1 de 4» a «Paso 4 de 4»: lo que oye el lector en los puntos de arriba |
| 1. Hola | cartel «HOLA» (el lector oye «Hola»); «Timbre MVD te muestra los ómnibus de Montevideo como el cartel de la parada.»; «Mis paradas»: «Los minutos en vivo de tus paradas, con el GPS de cada ómnibus.»; «Mapa»: «Los ómnibus que vienen a tus paradas.»; «Estoy esperando»: «Te avisamos cuando tu ómnibus está cerca.»; «App no oficial: no está afiliada con la Intendencia de Montevideo, el STM ni ninguna empresa de transporte.»; «Continuar» |
| 2. Sin cuentas ni registros | cartel «SIN CUENTAS» / «NI REGISTROS» (el lector oye «Sin cuentas ni registros»); «No tenés que crear una cuenta: la app no te pide nombre, mail ni teléfono.»; «No registramos lo que hacés ni lo que buscás. Sin publicidad, analíticas ni rastreo.»; «Lo que guardás queda en tu teléfono, no en servidores nuestros.»; «Leer la política de privacidad»; «Continuar» |
| 3. Tu código | cartel «TU CÓDIGO» (el lector oye «Tu código»); «Elegí 4 cifras para abrir la app.»; «Ahora no»; para repetirlo y si no coincide, los de «Bloqueo» |
| 3b. Huella | cartel «HUELLA», «FACE ID» o «TOUCH ID» (el lector oye «Huella», «Face ID» o «Touch ID»); «Abrí Timbre MVD con tu huella. Si no funciona, usás el código.»; «Usar huella»; «Ahora no»; el pedido del sistema «Confirmá para abrir Timbre MVD con tu huella» |
| 4. Listo | cartel «LISTO» (el lector oye «Listo»); con código, «La app pide tu código al abrirse.» y, con el desbloqueo rápido, «También se abre con tu huella.»; sin código, «La app se abre sin código.»; siempre, «Podés cambiarlo cuando quieras en Info.»; «Empezar» |

«Lo que guardás queda en tu teléfono, no en servidores nuestros.» no dice «solo en este teléfono»:
Android puede incluir los datos de la app en la copia de seguridad de Google de la persona.

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

En el Mapa, `offline`, `timeout` y `failed` en todas las paradas dan el panel «No se pudo
actualizar. Revisá la conexión.»; si falla solo alguna, sus ómnibus pasan a estimado sin ningún
texto. `busy` y `notFound` no dicen nada.

El estado de GPS no muestra errores: si falla, queda el último estado bueno, y si nunca llegó
no se muestra nada.

## Estados que no son errores

- **Cargando.** Indicadores de progreso sin texto. El único texto de espera es «Buscando
  parada…».
- **Vacío.** Cuatro carteles de `TimbreEmptyState` (ver [08-componentes.md](08-componentes.md)).
  El Mapa repite «SIN PARADAS» con su propio detalle (ver «Mapa», arriba):

  | Cartel | Lo que escucha el lector | Detalle |
  |---|---|---|
  | «SIN PARADAS» | «Sin paradas guardadas» | «Tocá + para agregar una parada y recibir un aviso cuando llegue el ómnibus.» |
  | «SIN RUTAS» | «Sin rutas guardadas» | «Tocá + para guardar una alerta de salida.» |
  | «SIN NOVEDADES» | «Sin novedades» | «Los desvíos y cambios de recorrido aparecen acá.» |
  | «SIN PASADAS» | «Sin pasadas para este horario» | «Probá con otro día o con una hora más temprano.» |

- **Confirmaciones.** Snack bars: «Te avisamos cuando el 121 esté a 5 min», «Código activado».

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
- La bienvenida dice «Los minutos en vivo de tus paradas, con el GPS de cada ómnibus.»: en los
  textos de la app se dice «con GPS», no «en vivo» (ver «Palabras»).
- «Tu teléfono no tiene una huella ni un rostro configurados.» dice qué pasó, pero no qué hacer.

## Antes de agregar un texto

- [ ] Voseo, «ómnibus», «parada», «tiempo de arribo».
- [ ] Si es un error: qué pasó y qué hacer, en ese orden.
- [ ] Horas en «H:MM»; «~» solo para estimados; cuenta regresiva solo con GPS.
- [ ] Una frase para el lector de pantalla si el texto está en un cartel o en una fila
      ([11-accesibilidad.md](11-accesibilidad.md)).
- [ ] Sin emoji.
- [ ] Este archivo y las pruebas que buscan el texto, actualizados.
