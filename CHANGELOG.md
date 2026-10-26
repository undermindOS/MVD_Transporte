# Changelog

Todos los cambios relevantes del proyecto. Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/);
versiones: [SemVer](https://semver.org/lang/es/).

## [Unreleased]

### Cambiado
- `applicationId` y paquete de Android: `com.liberontech.stmapp` en lugar del `com.example.stm_app` de la plantilla
  (Google Play no acepta `com.example`), igual que el bundle id de iOS. Para el sistema es otra app:
  una build debug instalada antes no se actualiza, sino que queda instalada al lado.
- Mi STM, Recarga, Cómo Ir y Avisos se abren en el navegador del sistema (Chrome Custom Tabs en Android,
  SFSafariViewController en iOS) en lugar de un WebView integrado. Google Play (Spam policy) prohíbe
  «webview of a website without permission», y el inicio de sesión con ID Uruguay tiene que hacerse en un
  navegador externo (RFC 8252), no en un WebView con JS inyectado. La navegación inferior tiene dos pestañas
  nativas: «Mis paradas» (principal) y «Servicios», con tarjetas de los sitios oficiales.
- Botones del widget de Android: «Mi STM» y «Recarga»; abren el sitio en el navegador.
- El bloqueo biométrico protege las paradas y rutas guardadas (se corrigió el texto en Info);
  volver del navegador no bloquea la app otra vez.

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
- Un error del widget ya no bloquea las notificaciones de rutas en segundo plano.
- Borrar deslizando (`Dismissible`) quita la tarjeta de forma sincrónica; antes aparecía el error
  «A dismissed Dismissible widget is still part of the tree».
- El bloqueo biométrico no se abre con `LockedOut`/`PermanentlyLockedOut` (era fail-open);
  ya no hay un ciclo de rebloqueo después de ingresar el PIN.
- El interruptor de biometría en la página Info muestra el estado real.
- Los botones del widget «Inicio»/«Recarga» abren la pestaña correcta (nadie leía el extra `tab`).
- Geolocalización en Cómo Ir en Android: el WebView rechazaba por defecto la Geolocation API; el permiso
  se pide en el momento en que Cómo Ir lo solicita, y solo para dominios de la IM.
- Los scrapers de saldo y de Cómo Ir se ejecutan solo en los hosts oficiales; se quitaron los selectores
  `[class*="to"]`, `[class*="from"]`, `[data-id]`, que capturaban `toolbar`/`button` y cualquier elemento.
- El saldo en el widget muestra solo el monto, no el texto del contenedor.
- Las líneas preferidas se comparan sin distinguir mayúsculas de minúsculas («64d» = «64D»).
- El widget muestra la hora de llegada (`~08:14`), no un «N min» que queda desactualizado.
- Un error de red se muestra como «No se pudo actualizar», no como «Sin colectivos próximos».
- Tests: estaban rotos (sin Hive ni plataforma de WebView en el entorno de tests); se reescribieron, 20 tests.
- iOS no compilaba: `workmanager_apple` requiere iOS 14 y Xcode 27, como mínimo iOS 15. El deployment target
  subió a 15.0 y el Podfile alinea el target de todos los pods.
- «Cargando...» eterno en el WebView: cuando muere el proceso WebContent (iOS, por falta de memoria),
  `onPageFinished` nunca llega. Ahora hay un reinicio automático y después la pantalla
  «No se pudo cargar la página» con el botón «Reintentar»; los errores del frame principal se manejan igual.

### Cambiado
- Ícono nuevo: ómnibus blanco sobre azul. El anterior combinaba un ómnibus con el escudo de Montevideo,
  algo riesgoso para una app no oficial según las políticas de las tiendas (falsa afiliación).
  El ícono adaptativo de Android y la pantalla de inicio (splash) usan el primer plano transparente
  `assets/app_icon_foreground.png`; de `assets/README.md` y `LOGO_SETUP.md` se quitaron los consejos
  de usar el escudo.

### Agregado
- «Estoy esperando»: tocar un ómnibus → «Avisarme cuando llegue» con 3/5/10 min de anticipación. El viaje se
  identifica por línea, destino y hora prevista (los viajes por horario no tienen id), así que un segundo ómnibus
  de la misma línea no se confunde con el primero. La campanita del chip muestra qué viaje se está siguiendo.
  - Android: un servicio en primer plano (`flutter_foreground_task`, tipo `dataSync`) consulta la parada
    cada 30 s, también con la pantalla apagada, muestra una notificación fija con el botón
    «Dejar de esperar» y avisa solo por un ómnibus con GPS. Termina solo después del aviso,
    cuando el viaje ya pasó o a los 60 min; no se reinicia ni arranca al encender el teléfono.
  - iOS: no hay consulta en segundo plano (haría falta un servidor de push propio), así que se programa un
    recordatorio para la hora prevista, que se reprograma en cada actualización mientras la app está abierta.
  - Permisos nuevos de Android: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`; en Play Console
    hay que declarar el tipo de servicio con un video (`docs/store-listing.md`).
- Los tiempos de arribo en «Mis paradas» se actualizan solos: cada 30 s mientras la app está en pantalla, y
  enseguida al volver del segundo plano (antes, solo con pull-to-refresh, y a los 10 minutos en pantalla seguía
  un «3 min» viejo). Sin indicador de carga, para que los chips no parpadeen; una parada compartida por una
  tarjeta y una ruta se consulta una sola vez; en segundo plano no hay consultas.
- «Ver en Cómo Ir» en la tarjeta de la parada: el deep link oficial `/comoir/parada?numero=N` en el navegador.
- Pestaña «Novedades» en «Mis paradas»: novedades oficiales del transporte de la IM (desvíos, cambios de
  líneas, horarios de feriados) desde el servicio abierto `api.montevideo.gub.uy/notificacion/mensajes`,
  el mismo que lee Cómo Ir. Las nuevas arriba, contador de no leídas; se recuerda el último
  `idMensaje` leído. El HTML se muestra como texto (se parsea a DOM sin WebView ni JS; se descartan
  `<script>`/`<iframe>`/imágenes) y «Ver más» abre el enlace en el navegador del sistema.
  Se consulta como máximo una vez cada 10 min (con pull-to-refresh, cada 30 s); las respuestas se guardan en caché en Hive.
  La API devuelve de a 10 mensajes con `id > fromIdMessage` sin orden, así que paginar por el
  id máximo (como hace Cómo Ir) pierde mensajes; la app busca la «ventana superior» según `count`.
- Ícono ♿ en el chip de los viajes con `accesibilidad: true`.
- Pantalla «Horarios» (ícono de reloj en la tarjeta de la parada): horario teórico según tipo de día
  (Hábiles/Sábados/Domingos) y hora — `transporteRest/siguientesParada/{parada}/{tipoDia}/{H:MM}`,
  ~50 viajes, pasando la medianoche; las respuestas se guardan en caché por 6 h.
- Aviso «Datos GPS parciales» en «Mis paradas» si una empresa tiene menos del 70 % de sus ómnibus
  transmitiendo GPS (`pci.montevideo.gub.uy/buses/control`, mismo umbral que Cómo Ir); como máximo una vez por minuto.
- La página Info enumera los datos nuevos en «Fuente de datos».
- Dependencias: `url_launcher` (enlaces de las novedades), `html` (parseo del HTML de las novedades; ya era transitiva).
- «Paradas cercanas» en el diálogo «Agregar parada»: paradas en un radio de 400 m según la ubicación, las más
  cercanas primero, con número, distancia y líneas; no hace falta ingresar el número. Fuente: el WFS abierto
  de `geoserver.montevideo.gub.uy` (capa `imm:v_uptu_paradas`, sin autenticación); el permiso de
  ubicación se pide al tocar el botón. La parada elegida se guarda como antes,
  mediante `transporteRest/lineas`.
- `docs/store-listing.md`: texto para Google Play / App Store con fuentes y aviso legal,
  borrador de Data safety; `docs/privacy-policy.md`: política de privacidad (Ley 18.331);
  `docs/carta-imm.md`: borrador de carta a pci@imm.gub.uy (no enviada).
- Ícono de «por horario» en los viajes sin GPS; su hora se muestra como hora de reloj («8:07»).
- Mención de la fuente de datos en la página Info; se corrigió el enlace a GitHub.
- `docs/REVIEW.md`: revisión, mapa de la API de la Intendencia de Montevideo, marco legal, propuestas.

### Eliminado
- Saldo de la tarjeta en el widget de Android y `BalanceScraper`: desde el navegador del sistema no se puede leer
  el saldo, y no hay una API abierta de saldo (en `api.montevideo.gub.uy` solo están `transporte` y `playas`).
- `ComoIrScraper` y el banner «Ruta detectada en Cómo Ir» (no funcionaba: Cómo Ir es una SPA de Ionic).
- Dependencias `webview_flutter`, `webview_flutter_android`, `permission_handler`; el borrado de la caché del WebView
  después de 2 h de inactividad.
- Permiso `SCHEDULE_EXACT_ALARM` (no se usaba; Google Play lo restringe).
- Tráfico HTTP sin cifrar (`usesCleartextTraffic="false"`): todos los endpoints son HTTPS.
- El pedido de ubicación en cada inicio y el pedido de permiso de notificaciones sin alertas activas.
