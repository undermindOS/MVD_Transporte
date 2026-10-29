# Changelog

Todos los cambios relevantes del proyecto. Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/);
versiones: [SemVer](https://semver.org/lang/es/).

## [Unreleased]

### Agregado
- Pestaña «Mapa», entre «Mis paradas» y «Servicios»: tus paradas guardadas y los ómnibus con GPS que vienen a
  ellas, sobre un mapa nocturno de Montevideo y alrededores. El mapa viene dentro de la app (datos de
  OpenStreetMap, estilo «Timbre Noche», unos 15 MB en `assets/map/`): moverlo o acercarlo no hace pedidos y la
  pestaña no usa tu ubicación. Cada ómnibus aparece una sola vez aunque vaya a dos de tus paradas; al tocarlo
  muestra cuánto le falta para cada una, y al tocar una parada se ven sus próximos ómnibus. Entre un refresco y
  el siguiente los ómnibus se deslizan a su posición nueva, salvo con «reducir movimiento». La pestaña se arma la
  primera vez que la abrís y pide los arribos cada 30 s solo mientras está a la vista, con los mismos tableros que
  «Mis paradas»: si «Mis paradas» los trajo hace menos de 30 s, no los vuelve a pedir. Después de un fallo, los
  últimos ómnibus quedan sin encender hasta 5 minutos, contados desde que el tablero llegó al teléfono, como en
  «Mis paradas». «© OpenStreetMap» se ve siempre en una esquina y abre la
  página de derechos de OpenStreetMap. Info nombra la posición de los ómnibus entre las fuentes de datos y suma
  «Mapa: © colaboradores de OpenStreetMap, con licencia ODbL. Viene dentro de la app.», con y sin proxy. Las
  paradas elegidas en «Buscar por calles» o en «Paradas cercanas» se guardan con su ubicación; a las demás se la
  busca la app al abrir el Mapa: con el proxy, en el catálogo de paradas; sin proxy, en geoserver, por número de
  parada. Glifo nuevo para la pestaña: dos calles que se cruzan y un ómnibus.
- «Buscar por calles» en el diálogo «Agregar parada»: la parada se encuentra por los nombres de sus calles
  («18 de julio ejido» → «AV 18 DE JULIO y EJIDO», «san jose andes» → 574). Las palabras van en cualquier orden,
  sin distinguir mayúsculas, tildes, Ñ ni apóstrofos («ohiggins» = «O´HIGGINS»; «ordoñez» encuentra también
  «ORDOÐEZ», mal escrito en el catálogo); primero las coincidencias al principio de una palabra, hasta 50. La
  parada elegida se guarda al instante con su nombre, sus líneas y su ubicación. El catálogo del proxy
  (`/v1/catalog/stops`, 4 972 paradas) se baja al escribir la primera letra y queda en el teléfono un día (unos
  660 KB, que se leen del disco solo cuando hacen falta); si el proxy no responde, se usa la copia anterior. Un
  catálogo que llega sin líneas (el proxy todavía no armó su índice de paradas) nunca pisa una copia que sí las
  tiene y se vuelve a pedir a los 15 minutos. Solo en la build con `MVD_PROXY_URL`; sin proxy el campo no aparece.
- «Paradas cercanas» en el diálogo «Agregar parada»: paradas en un radio de 400 m según tu ubicación, las más
  cercanas primero, con número, distancia y líneas; no hace falta ingresar el número. El permiso de ubicación se
  pide al tocar el botón, y la parada elegida se guarda al instante con su nombre, sus líneas y su ubicación. Con
  el proxy se calculan en el teléfono con el catálogo de paradas, así tu ubicación no sale del dispositivo. Sin
  proxy se le pide al WFS abierto de `geoserver.montevideo.gub.uy` (capa `imm:v_uptu_paradas`, sin autenticación)
  un área aproximada —tu posición redondeada a 3 decimales, unos 110 m— y después se filtra en el teléfono con la
  posición exacta.
- Aire acondicionado y «cero emisiones» en las filas de «Mis paradas», con ícono y texto para TalkBack y
  VoiceOver, cuando la app usa el proxy. Solo se muestra un «sí» confirmado: «sin datos» no es «no».
- Ajustes del aviso de una parada o de una ruta: la línea «Aviso N min antes · …» debajo de la campanita encendida
  abre una hoja con la anticipación (3, 5 o 10 min; antes era siempre 5 y no se podía cambiar) y el horario: días de
  la semana y franja horaria («Lun a Vie 7:30–8:30»; puede pasar la medianoche y cuenta para el día en que empieza).
  Fuera de esa franja, la verificación en segundo plano no avisa por esa parada o ruta y no consulta la parada (la
  ruta del widget de Android se sigue consultando). Las paradas y rutas guardadas antes se leen como «siempre».
- «Agregar ruta» con chips: las líneas se eligen entre las de la parada (botón «Ver líneas» junto al número) en
  lugar de escribir «183, 64D», y el destino (HACIA) entre los destinos de esas líneas en la parada, aunque no venga
  ningún ómnibus; para una línea sin destinos conocidos (sin proxy, todas) se usan los de los ómnibus que vienen.
  La tarjeta dice «Hacia: POCITOS»; si no elegís nada, valen todas. Cada destino guarda también sus variantes
  (`preferredVariantIds`), así un ómnibus de esa variante coincide aunque su destino esté escrito distinto. Las
  rutas que ya tenías se siguen leyendo igual.
- «Estoy esperando»: tocar un ómnibus → «Avisarme cuando llegue» con 3/5/10 min de anticipación. El viaje se sigue
  por su identificador (`tripId`), así que otro ómnibus de la misma línea y el mismo destino que llegue unos
  minutos antes no se confunde con el tuyo, y se sigue también cuando un viaje por horario pasa a tener GPS. La
  fila del ómnibus que seguís se destaca con una campanita. La hora del viaje se pasa al reloj del teléfono con la
  diferencia de relojes que se mide con cada tablero: un teléfono con la hora corrida no da tu ómnibus por pasado
  ni avisa antes (o después) de tiempo, con proxy o sin él. Sin proxy, el reloj de la fuente es el encabezado
  `Date` de la respuesta de la Intendencia (si no viene, el del teléfono).
  - Android: un servicio en primer plano (`flutter_foreground_task`, tipo `dataSync`) consulta la parada
    cada 30 s, también con la pantalla apagada, muestra una notificación fija con el botón
    «Dejar de esperar» y avisa solo por un ómnibus con GPS. Termina solo después del aviso,
    cuando el viaje ya pasó o a los 60 min; no se reinicia ni arranca al encender el teléfono.
  - iOS: no hay consulta en segundo plano (haría falta un servidor de push propio), así que se programa un
    recordatorio para la hora prevista, que se reprograma en cada actualización mientras la app está abierta.
  - Permisos nuevos de Android: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`; en Play Console
    hay que declarar el tipo de servicio con un video (`docs/store-listing.md`).
- Los tiempos de arribo en «Mis paradas» se actualizan solos: cada 30 s mientras estás en «Mis paradas», y al
  momento cuando volvés del segundo plano, de Servicios, de Horarios o de Info (antes, solo con pull-to-refresh, y a
  los 10 minutos en pantalla seguía un «3 min» viejo). Sin indicador de carga, para que las filas no parpadeen; en
  segundo plano y con la app bloqueada no hay consultas, tampoco justo cuando aparece la pantalla de bloqueo al
  volver. Cada parada se pide una sola vez y todas a la vez, aunque una ruta salga de una parada guardada: la
  tarjeta de la ruta usa los datos de su parada de origen.
- Si falla la actualización, la tarjeta dice «No se pudo actualizar. Datos de las H:MM. Deslizá para reintentar.»
  y debajo quedan los últimos ómnibus como estimados («~20:01», nunca en ámbar) durante 5 minutos como máximo.
  Sin error, un tablero que no se renueva hace más de un minuto (al volver de Horarios o Info, o con el proxy
  saturado) tampoco muestra minutos en vivo: los ómnibus quedan como estimados, sin los que tenían que pasar hace
  más de un minuto, y pasados 5 minutos la tarjeta espera el tablero nuevo. El minuto y los 5 minutos se cuentan
  desde que el tablero llegó al teléfono, con o sin error, y la hora de cada ómnibus se compara con el reloj del
  servidor (sin proxy, el encabezado `Date` de la Intendencia): un teléfono con la hora corrida no da minutos
  viejos por nuevos ni borra estimados antes de tiempo.
- Si una parada guardada dejó de existir, la tarjeta dice «Esta parada ya no existe. Deslizá la tarjeta para
  borrarla.».
- Una parada que agregás sin conexión queda como «Parada N» y toma su nombre y sus líneas la próxima vez que abrís
  la app con conexión.
- Mejoras para TalkBack y VoiceOver. Cada fila se lee como una sola frase y los nombres de la API se leen como
  palabras («Parada 574, San Jose y Andes», «De San Jose y Andes a Trabajo», «Nueva. 2 de octubre. …»). Los enlaces
  de Info dicen dónde se abren, las tarjetas tienen la acción «Borrar» además de deslizarlas, los días se leen
  completos, los campos dicen «obligatorio» y el contador de Novedades se lee «N novedades sin leer».
- «Ver en Cómo Ir» en la tarjeta de la parada: el deep link oficial `/comoir/parada?numero=N` en el navegador.
- Pestaña «Novedades» en «Mis paradas»: novedades oficiales del transporte de la IM (desvíos, cambios de
  líneas, horarios de feriados) desde el servicio abierto `api.montevideo.gub.uy/notificacion/mensajes`,
  el mismo que lee Cómo Ir. Las nuevas arriba, contador de no leídas; se recuerda el último
  `idMensaje` leído. El HTML se muestra como texto (se parsea a DOM sin WebView ni JS; se descartan
  `<script>`/`<iframe>`/imágenes) y «Ver más» abre el enlace en el navegador del sistema.
  Se consulta como máximo una vez cada 10 min (con pull-to-refresh, cada 30 s); las respuestas se guardan en caché en Hive.
  La API devuelve de a 10 mensajes con `id > fromIdMessage` sin orden, así que paginar por el
  id máximo (como hace Cómo Ir) pierde mensajes; la app busca la «ventana superior» según `count`.
- Ícono de accesibilidad en los viajes con `accesibilidad: true`.
- Pantalla «Horarios» (ícono de reloj en la tarjeta de la parada): horario teórico según tipo de día
  (Hábiles/Sábados/Domingos) y hora — `transporteRest/siguientesParada/{parada}/{tipoDia}/{H:MM}`,
  ~50 viajes, pasando la medianoche; las respuestas se guardan en caché por 6 h.
- Aviso «Datos GPS parciales» en «Mis paradas» si una empresa tiene menos del 70 % de sus ómnibus
  transmitiendo GPS (`pci.montevideo.gub.uy/buses/control`, mismo umbral que Cómo Ir); como máximo una vez por minuto.
- La página Info enumera los datos nuevos en «Fuente de datos». El aire acondicionado y «cero emisiones», y la
  frase «Las consultas pasan por el servidor del proyecto, que no guarda datos personales.», aparecen solo en la
  build con `MVD_PROXY_URL`, la única que tiene esos datos y ese servidor.
- Pantalla «Privacidad»: la fila «Política de privacidad» de Info, que ahora se ve siempre, abre la política dentro
  de la app, también sin conexión. Es el mismo texto de `docs/privacy-policy.md`, que viene incluido en la app, sin
  las notas para quien mantiene el archivo; TalkBack y VoiceOver anuncian el título y cada sección como
  encabezados. Google Play pide la política también dentro de la app.
- Ícono de «por horario» en los viajes sin GPS; su hora se muestra como hora de reloj («8:07»).
- Mención de la fuente de datos en la página Info; se corrigió el enlace a GitHub.
- Con `--dart-define=MVD_PROXY_URL=…` la app le pide todo al proxy (`/v1`): paradas, arribos (también en segundo
  plano y en «Estoy esperando»), horarios, el catálogo, las novedades y el estado GPS, y ya no se conecta con ningún
  servidor de la Intendencia. Si el proxy responde 429, no pide nada hasta que pase el tiempo de `Retry-After` y no
  muestra ningún error. Sin esa opción, la app llama directo a los servicios de la ciudad, como antes, porque el
  proxy todavía no está desplegado.
- Proxy en Cloudflare Workers (`proxy/`, versión 0.3.0), la futura única dirección del backend de la app. Responde
  en su propio formato `/v1`, con caché de Workers y un límite de 300 pedidos por minuto por IP:
  - `/v1/stops/{id}`: el nombre, las líneas en el orden de la app y a dónde va cada línea (`directions`, con el
    destino y los `variantIds`, según las variantes de geoserver y de la API oficial). Se guarda 24 h; si las
    direcciones fallan o tardan más de 2 s, responde `directions: []` y se guarda 5 minutos.
  - `/v1/stops/{id}/arrivals`: cada arribo trae `tripId`, `variantId`, `state` (`arriving`, `live` o `scheduled`),
    `expectedAt`, `clockTime`, `airConditioning`, `zeroEmission` y `location`: la posición del ómnibus con GPS
    (`{lat, lng}`, de `coordinates`, solo con `real: true`) o `null`. Una fila con una hora imposible se descarta,
    en lugar de un error para toda la parada; una posición imposible deja solo `location` en `null`. Se guarda
    15 s.
  - `/v1/stops/{id}/schedule/{weekday|saturday|sunday}/{H:MM}`: solo con la hora canónica (`8:05` anda, `08:05` y
    `8:5` dan 404). Se guarda 6 h.
  - `/v1/catalog/stops`: las 4 972 paradas con sus líneas y `linesAvailable`. Se guarda un día; si todavía no hay
    índice de paradas, responde con `lines: []` y se guarda 15 minutos.
  - `/v1/news`: las 10 novedades más nuevas, con la misma paginación que la app (hasta 8 páginas, 5 s cada una),
    los textos recortados y los enlaces http(s) normalizados; si falla una página, responde error y no una lista
    más corta. Se guarda 5 minutos.
  - `/v1/status/gps`: el porcentaje de ómnibus con GPS por empresa, redondeado entre 0 y 100, con `partial` cuando
    baja de 70 %. Si pci devuelve una lista vacía responde 502, así nunca parece que todo anda bien. Se guarda
    1 minuto.
  - Registra los errores de las fuentes con un texto fijo `<fuente>: <tipo>` (por ejemplo
    `transporteRest: HTTP 500` o, de la API oficial, `imApi: token refused`), sin URL, ruta ni IP, y se
    identifica siempre con el mismo User-Agent. Cualquier error inesperado responde `500 internal_error` en JSON.
    `proxy/README.md` está en español: rutas, enlace al contrato, la regla de logs apagados y el orden de
    despliegue (primero el proxy, después la app).
- La API oficial de la IM (`api.montevideo.gub.uy/api/transportepublico`) dentro del proxy. La clave del portal
  está solo en los secretos del Worker (`IM_CLIENT_ID`, `IM_CLIENT_SECRET`), no en la app. Es una sola clave para
  todos y permite 14 pedidos por minuto (medido), así que a la API llama un único Durable Object, `ImGateway`:
  guarda el token, respeta un presupuesto de 12 pedidos por minuto (el contador sobrevive cuando el objeto se
  duerme), baja la instantánea de toda la flota como mucho cada 15 s y entrega la anterior mientras baja la nueva.
  El confort se cruza por número de ómnibus (18 de 18 coincidieron); los arribos no lo esperan más de 2 s, y como
  el confort de cada vehículo queda guardado, también después de que el objeto se duerme la respuesta viene con
  él. Los tiempos de arribo siguen saliendo de `transporteRest`: `upcomingbuses` de la API oficial siempre viene
  vacío. Errores nuevos: `503 upstream_busy` (presupuesto agotado, con `Retry-After`) y `503 not_configured`.
- Índice de paradas en el proxy: una vez por día arma, con el CSV de toda la capa de geoserver, las líneas y
  variantes de cada parada, sin gastar el presupuesto de la API oficial. Lo guarda en el Durable Object en 64 partes,
  lo sirve hasta 7 días y, si falla, lo reintenta a los 15 minutos, aunque el objeto se haya dormido en el medio
  (la hora del fallo queda guardada).
- `proxy/contract/v1/`, el contrato /v1 que comparten el proxy y la app: 24 casos, las respuestas esperadas
  escritas a mano, vectores para cada regla de derivación y capturas fechadas de las fuentes (`upstream/`), entre
  ellas novedades, estado GPS y una muestra del índice de paradas de geoserver del 2026-10-27. Las pruebas de los
  dos lados —el proxy (`contract.test.js`, `rules.test.js`) y la app (`test/contract/`, con proxy y sin proxy)—
  usan los mismos archivos, así que si el contrato cambia de un solo lado, las pruebas del otro se ponen en rojo.
- `lib/services/api/`, la capa de datos del contrato /v1 en la app: `ApiResult` y `ApiFailure`, las reglas de
  derivación en Dart (las mismas que el proxy), un único lector por forma (`V1Parser`) y dos fuentes: el proxy, o
  los servidores de la ciudad convertidos a JSON v1 en el teléfono. Sin proxy, una respuesta que no se puede
  convertir hace fallar solo ese pedido: las otras paradas y sus avisos siguen andando.
- `proxy/scripts/smoke.js <url>`, para probar un proxy andando: pide cada ruta de los casos 200 del contrato y
  verifica status, `Cache-Control`, `Content-Type` y las claves del cuerpo.
- Dependencias: `url_launcher` (enlaces de las novedades), `html` (parseo del HTML de las novedades; ya era
  transitiva), `flutter_map` 8.3.2 y `flutter_map_vector_tiles` 2.10.1 (el Mapa, con versiones fijas),
  `latlong2` (coordenadas del mapa) y `path_provider` (la copia del mapa base en la caché de la app).
- `docs/store-listing.md`: texto para Google Play / App Store con fuentes y aviso legal,
  borrador de Data safety y la URL de la política para Play Console; `docs/privacy-policy.md`: política de
  privacidad (Ley 18.331), con fecha del 28 de octubre de 2026;
  `docs/carta-imm.md`: borrador de carta a pci@imm.gub.uy (no enviada).
- `docs/REVIEW.md`: revisión, mapa de la API de la Intendencia de Montevideo, marco legal, propuestas.

### Cambiado
- Info dice que la app la desarrolla Liberon Tech, de Khrestenkov & Co, y el contacto pasa a ser
  daniil@khrestenkov.com, también en la política de privacidad.
- Diseño nuevo: la app se llama Timbre MVD (en la pantalla de inicio del teléfono, en el widget y, en iOS, también
  en `CFBundleName`) y toda la interfaz es un tablero de LED nocturno. Fondo azul noche; el ámbar queda solo para lo
  que pasa ahora (un ómnibus con GPS, LLEGANDO), y la hora en Horarios, el resumen del aviso, el candado de Info, la
  nota de Servicios y las marcas de las listas de paradas van en gris azulado. Fira para leer, letras de puntos
  (Doto) para los carteles e íconos de píxel. «Mis paradas» está rehecha: cada parada es un pequeño tablero con sus
  ómnibus —línea y minutos encendidos para los que tienen GPS, contorno y reloj para los de horario—, tres filas y
  «Ver las N» para el resto. Servicios, Novedades, Horarios, Info y la pantalla de bloqueo (un candado de LED) siguen
  el mismo tablero, y todas las pantallas usan los tokens de `lib/ui/theme/`. Las fuentes vienen dentro de la app,
  sin descargas.
- Ícono y pantalla de inicio nuevos: el ómnibus de Timbre MVD encendido en ámbar sobre el tablero nocturno, con
  ícono temático para Android 13 y los íconos oscuro y teñido de iOS 18; la pantalla de inicio es el mismo ómnibus
  sobre el azul noche de la app, sin texto. El ícono anterior combinaba un ómnibus con el escudo de Montevideo, algo
  riesgoso para una app no oficial según las políticas de las tiendas (falsa afiliación); de `assets/README.md` y
  `LOGO_SETUP.md` se quitaron los consejos de usar el escudo.
- Notificaciones: todos los textos dicen «ómnibus»; en la barra de estado se ve la silueta blanca del ómnibus
  en lugar del ícono de colores, que Android dibujaba como una mancha blanca, y el acento es el azul tinta del
  tablero. La de un ómnibus que ya está en la parada dice «Línea 116 — llegando» en vez de «0 min».
- El widget de Android es un pequeño tablero nocturno con la placa TIMBRE MVD. Muestra el destino del propio
  ómnibus («Línea 116 a POCITOS») y la hora que da la fuente, no la que calcula el reloj del teléfono, y se
  actualiza cada vez que la app refresca los arribos, no solo con el chequeo en segundo plano.
- `applicationId` y paquete de Android: `com.liberontech.stmapp` en lugar del `com.example.stm_app` de la plantilla
  (Google Play no acepta `com.example`), igual que el bundle id de iOS. Para el sistema es otra app:
  una build debug instalada antes no se actualiza, sino que queda instalada al lado.
- Mi STM, Recarga, Cómo Ir y Avisos se abren en el navegador del sistema (Chrome Custom Tabs en Android,
  SFSafariViewController en iOS) en lugar de un WebView integrado. Google Play (Spam policy) prohíbe
  «webview of a website without permission», y el inicio de sesión con ID Uruguay tiene que hacerse en un
  navegador externo (RFC 8252), no en un WebView con JS inyectado. La navegación inferior tiene tres pestañas
  nativas: «Mis paradas» (principal), «Mapa» y «Servicios», con tarjetas de los sitios oficiales.
- Botones del widget de Android: «Mi STM» y «Recarga»; abren el sitio en el navegador.
- El bloqueo biométrico protege las paradas y rutas guardadas (se corrigió el texto en Info). Volver de una app
  que abriste desde Timbre MVD —el navegador, también desde un enlace de Info; el correo de «Contacto»; «Ver más»
  de una novedad; los ajustes del sistema desde «Paradas cercanas»— no bloquea la app otra vez. El siguiente paso
  al segundo plano sí la bloquea.
- La hora esperada de un arribo sale de la fuente y ya no se calcula sumando minutos al reloj del teléfono.
- El chequeo en segundo plano consulta todas las paradas en paralelo y cada una una sola vez.
- El número de parada admite hasta 7 dígitos. Un número que no puede existir, como 0, se informa como inexistente
  sin consultar a nadie, con proxy y sin proxy.
- Los errores dentro de una tarjeta y en Horarios se muestran en rojo y dicen qué hacer, por ejemplo «No existe la
  parada N. Revisá el número.» o «No se pudo cargar el horario. Revisá la conexión.».
- Los mensajes usan voseo y dicen cuál es el paso siguiente: bloqueo biométrico («Autenticate para acceder a Timbre
  MVD», «Tu dispositivo no tiene bloqueo de pantalla. Configuralo en Ajustes.»), navegador, correo, enlaces de
  Novedades, permiso de ubicación («Timbre MVD usa tu ubicación para mostrarte las paradas cercanas.») y avisos que
  no se pudieron activar.

### Corregido
- Los tiempos de arribo (ETA) vuelven a funcionar: el viejo `m.montevideo.gub.uy/stmonlineRest/nextETA` respondía
  `400 Argumentos invalidos`; ahora se usa `api.montevideo.gub.uy/transporteRest/siguientesParada/{id}`,
  el mismo servicio que usa la app web oficial Cómo Ir.
- Nombre de la parada: `transporteRest/variantes` respondía 500; ahora `transporteRest/lineas/{id}`
  devuelve el nombre real («AV RAMON ANADOR y TIBURCIO GOMEZ») en lugar de «Parada 1234».
- Ya no se puede agregar una parada inexistente; agregar de nuevo una parada no borra la configuración de sus alertas.
- La verificación en segundo plano se registra al activar cualquier alerta (antes, solo al iniciar la app
  y solo para paradas, sin contar las rutas) y se cancela cuando no quedan alertas.
- Las notificaciones «llegando» se envían solo para ómnibus con GPS (`real: true`), no por horario.
- Si en segundo plano no se pudo consultar una parada, ya no cuenta como «sin ómnibus» y no avisa nada.
- Un error del widget ya no bloquea las notificaciones de rutas en segundo plano.
- Borrar deslizando (`Dismissible`) quita la tarjeta de forma sincrónica; antes aparecía el error
  «A dismissed Dismissible widget is still part of the tree».
- El bloqueo biométrico no se abre con `LockedOut`/`PermanentlyLockedOut` (era fail-open);
  ya no hay un ciclo de rebloqueo después de ingresar el PIN.
- El bloqueo biométrico tapa toda la app. Antes, si la app se bloqueaba con Horarios, Info, un diálogo o una hoja
  abiertos, esa pantalla quedaba encima de la pantalla de bloqueo, a la vista y al alcance. Ahora, mientras está
  bloqueada, nada de la app se ve, se toca ni lo leen TalkBack o VoiceOver, sus mensajes no aparecen sobre la
  pantalla de bloqueo y el botón atrás no cierra nada escondido. Al desbloquear volvés a la misma pantalla, hoja
  o diálogo, y «Mis paradas» sigue en la subpestaña en que estabas y actualiza los tableros sin cargarlos de cero.
- Un diálogo del sistema que no saca la app de la pantalla, como un pedido de permiso, ya no la bloquea: solo la
  bloquea volver del segundo plano.
- El interruptor de biometría en la página Info muestra el estado real.
- Las líneas preferidas se comparan sin distinguir mayúsculas de minúsculas («64d» = «64D»).
- El widget muestra la hora de llegada (`~08:14`), no un «N min» que queda desactualizado.
- El widget ya no se queda mostrando un ómnibus viejo. Lo deja de mostrar 2 minutos después de la hora en que
  tenía que pasar, queda vacío apenas no te queda ninguna ruta activada (aunque tengas una alerta de parada) y,
  sin conexión, muestra el último ómnibus solo hasta su hora. Esa hora se guarda en el reloj del teléfono, así que
  uno con la hora corrida no oculta el ómnibus antes ni después de tiempo, con proxy o sin él (sin proxy, el reloj
  de la fuente es el encabezado `Date` de la Intendencia).
- Los enlaces «Mi STM» y «Recarga» del widget miden 44 dp de alto, así son más fáciles de tocar, y el widget sigue
  entrando en 3 × 2.
- Un error de red o una respuesta de arribos con forma inesperada se muestra como «No se pudo actualizar», no como
  «Sin ómnibus próximos».
- En modo directo, un `minutos` que no es número ya no se muestra como «Llegando».
- Si falla la consulta del estado GPS, se sigue mostrando el último que llegó bien.
- Sin el proxy, una novedad con una fecha imposible ya no hace fallar la actualización de Novedades: se descarta y
  se muestran las demás, como hace el proxy.
- Ya no aparece una franja blanca (o negra) detrás de la app cuando abrís o cerrás el teclado, tampoco en
  Android 12 o más nuevo: el fondo de la ventana es el azul noche del tablero.
- Los chips elegidos en «Agregar ruta» y en los días del aviso tienen letras oscuras sobre el ámbar. Antes el texto
  claro casi no se leía.
- Con letra grande ya no se corta nada con «…». El título de la página se achica hasta entrar entero; el nombre de
  la parada en Horarios usa hasta cuatro líneas y el subtítulo de Servicios pasa a una segunda. El destino en
  Horarios y en el cartel de «Estoy esperando» también usa dos líneas, o una línea propia cuando dos no alcanzan.
- Aunque achiques la letra del sistema, las letras de puntos («LLEGANDO», el cartel de «Estoy esperando», la placa
  TIMBRE MVD, los carteles de lista vacía) nunca quedan por debajo de 19 px.
- Si la URL del proxy termina en «/», los pedidos ya no salen con «//».
- Cuando dos pedidos a la API oficial se cruzaban justo al llegar el token, el proxy a veces pedía un segundo token.
- Tests: estaban rotos (sin Hive ni plataforma de WebView en el entorno de tests); se reescribieron.
- iOS no compilaba: `workmanager_apple` requiere iOS 14 y Xcode 27, como mínimo iOS 15. El deployment target
  subió a 15.0 y el Podfile alinea el target de todos los pods.

### Eliminado
- Saldo de la tarjeta en el widget de Android y `BalanceScraper`: desde el navegador del sistema no se puede leer
  el saldo, y no hay una API abierta de saldo (en `api.montevideo.gub.uy` solo están `transporte` y `playas`).
- `ComoIrScraper` y el banner «Ruta detectada en Cómo Ir» (no funcionaba: Cómo Ir es una SPA de Ionic).
- Dependencias `webview_flutter`, `webview_flutter_android`, `permission_handler`; el borrado de la caché del WebView
  después de 2 h de inactividad.
- Permiso `SCHEDULE_EXACT_ALARM` (no se usaba; Google Play lo restringe).
- Tráfico HTTP sin cifrar (`usesCleartextTraffic="false"`): todos los endpoints son HTTPS.
- El pedido de ubicación en cada inicio y el pedido de permiso de notificaciones sin alertas activas.
