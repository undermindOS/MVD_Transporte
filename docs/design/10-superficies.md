# Superficies fuera de la app

El ícono, la pantalla de inicio, el widget y las notificaciones son el mismo
tablero nocturno que la app: fondo `noche`, paneles `tinta`, ámbar solo donde
algo está encendido. Las fuentes del ícono y de la pantalla de inicio están en
`assets/`; los archivos de cada plataforma se generan a partir de ellas (ver
[Regenerar](#regenerar)).

Todo lo que sigue está comprobado en el código. Si algo de esta página no
coincide con el código, manda el código y hay que corregir la página
([README.md](README.md)).

## Ícono de la app

El ómnibus de la marca (vector v2 «Aviso») encendido en `ambar` sobre una
baldosa `tinta`. El cartel, el parabrisas y las luces de las esquinas son
transparentes: a través de ellos se ven los LED apagados del tablero (`ambar`
al 10 %), y el ómnibus brilla un poco.

| Plataforma | Archivo fuente | Qué es |
|---|---|---|
| iOS, claro | `assets/app_icon.png` | Cuadrado a sangre, sin transparencia (`remove_alpha_ios: true`); iOS aplica su máscara |
| iOS 18, oscuro | `assets/app_icon_ios_dark.png` | El ómnibus encendido sobre transparente |
| iOS 18, teñido | `assets/app_icon_ios_tinted.png` | El ómnibus blanco sobre transparente; iOS lo tiñe |
| Android 8+, adaptativo | `assets/app_icon_background.png` + `assets/app_icon_foreground.png` | Fondo: tinta con LED apagados, con la grilla a 2/3 del paso de la de iOS (el launcher muestra solo los 72 dp interiores de 108). Primer plano: el ómnibus dentro de la zona segura de 66 dp (`adaptive_icon_foreground_inset: 0`) |
| Android 13+, temático | `assets/app_icon_monochrome.png` | Silueta de un color, con el cartel y el parabrisas recortados |
| Android < 8 | `assets/app_icon_android.png` | Baldosa redondeada |

La configuración está en `pubspec.yaml`, bloque `flutter_launcher_icons`. El
detalle de cada archivo está en [assets/README.md](../../assets/README.md).

Dentro de la app, la página Info dibuja el mismo ícono con código:
`TimbreAppIcon(size: 64)` (`lib/ui/widgets/timbre_bus.dart`, usado en
`lib/ui/info_page.dart`). Apila las mismas capas que el ícono del launcher:
`tinta`, `LedMatrix` con paso `size / 32`, el resplandor del ómnibus
(desenfoque de `size × 0.022`, opacidad 0.45) y el ómnibus con el cartel y el
parabrisas recortados. Las esquinas tienen radio `size × 232 / 1024`. El nivel
de detalle baja con el tamaño (`TimbreBusDetail.forIconSize`: completo desde
80 px, medio desde 50, chico desde 35, mínimo abajo de eso). No tiene variante
nocturna: la app es siempre oscura.

Ni el ícono ni ninguna otra superficie llevan símbolos oficiales (escudo,
bandera, Sol de Mayo, logos del STM, de la Intendencia o de las empresas). Por
qué: [12-decisiones.md](12-decisiones.md#ningún-símbolo-oficial).

## Pantalla de inicio

Solo el ómnibus encendido sobre `noche` (`#070F22`), de día y de noche. Es el
mismo color del fondo de la app, así que al abrir no hay destello.

- Configuración: `flutter_native_splash.yaml`. `color` y `color_dark` son
  `#070F22`, con `assets/splash_icon.png`. Para Android 12+ (`android_12`):
  `assets/splash_icon_android12.png` y `icon_background_color` `#070F22`.
- Tamaño: `splash_icon.png` mide 560 px (140 dp/pt) con el ómnibus de 125;
  `splash_icon_android12.png` mide 1152 px con el ómnibus dentro del círculo
  de 768 px que muestra Android 12+.
- La pantalla de inicio se queda hasta que la app terminó de arrancar:
  `lib/main.dart` llama a `FlutterNativeSplash.preserve` al empezar y a
  `FlutterNativeSplash.remove` después de abrir Hive, las notificaciones,
  WorkManager y «Estoy esperando».
- iOS: la vista de `ios/Runner/Base.lproj/LaunchScreen.storyboard` tiene fondo
  `#070F22`, y `Info.plist` pide texto claro en la barra de estado
  (`UIStatusBarStyle` = `UIStatusBarStyleLightContent`).

## Fondo de ventana en Android

Detrás de la vista de Flutter Android pinta la ventana. Si esa ventana es
blanca o negra, se ve una franja al abrir o cerrar el teclado. Por eso el
tema `NormalTheme` usa `android:windowBackground` = `@color/noche` en los
cuatro archivos de estilos:

- `android/app/src/main/res/values/styles.xml`
- `values-night/styles.xml`
- `values-v31/styles.xml` y `values-night-v31/styles.xml`, que son los que
  valen en Android 12+.

`@color/noche` está definido en `res/values/colors.xml` (`#070F22`), junto a
los demás colores del tablero que usa el widget.

El tema de arranque `LaunchTheme` muestra la pantalla de inicio: antes de
Android 12 con `@drawable/launch_background`; desde Android 12 con
`windowSplashScreenBackground` `#070F22`, `windowSplashScreenAnimatedIcon`
`@drawable/android12splash` y `windowSplashScreenIconBackgroundColor`
`#070F22`.

**Ojo:** `dart run flutter_native_splash:create` reescribe los dos archivos
`-v31` y deja el color del sistema en `NormalTheme`. Después de correrlo,
volvé a poner `@color/noche`. `test/brand_assets_test.dart` falla si falta en
cualquiera de los cuatro archivos.

## Widget de inicio (Android)

Un tablero chico con el próximo ómnibus de una ruta y dos accesos a sitios
oficiales. Existe solo en Android: en iOS no hay widget (ver
[Plataformas](#plataformas)).

Archivos:

- `android/app/src/main/res/layout/mvd_transporte_widget.xml`: el diseño.
- `android/app/src/main/res/xml/mvd_transporte_widget_info.xml`: tamaño y
  refresco.
- `android/app/src/main/kotlin/com/liberontech/stmapp/MVDTransporteWidgetProvider.kt`:
  lee los datos y llena las vistas.
- `lib/services/home_widget_feed.dart` (`WidgetFeed`): escribe los datos.

### Cómo se ve

- **Tamaño:** 3 × 2 celdas (`targetCellWidth` 3, `targetCellHeight` 2),
  mínimo 250 × 110 dp, redimensionable. El selector de widgets de Android 12+
  muestra el diseño real (`previewLayout`).
- **Tablero:** fondo `tinta`, borde de 1 dp `linea_noche`, radio 20 dp
  (`drawable/widget_background.xml`), margen interior 12 dp (en el diseño).
- **Placa:** `drawable-nodpi/widget_plate.png`, de 20 dp de alto: el ómnibus
  y «TIMBRE» en ámbar, «MVD» en ámbar tenue, en letras de puntos. TalkBack la
  lee «Timbre MVD».
- **Fila del ómnibus** (`widget_route_section`):
  - número de línea en un contorno de 1.5 dp `etiqueta` con radio 6 dp
    (`drawable/widget_badge_bg.xml`), texto `etiqueta` 14 sp en negrita;
  - destino en `papel`, 15 sp en negrita, una sola línea, cortado con «…» si
    no entra;
  - ícono de reloj `tenue` de 13 dp;
  - hora «~19:56» en `etiqueta`, 16 sp en negrita.

  Es una estimación de la última consulta, así que nunca se enciende en
  ámbar: contorno y reloj, como un horario en la app
  ([08-componentes.md](08-componentes.md)).
- **Sin ómnibus** (`widget_route_empty`): ícono de ruta `etiqueta` de 14 dp y
  «Sin próximos ómnibus en tus rutas», `etiqueta` 13 sp, hasta dos líneas.
- **Accesos:** «Mi STM» y «Recarga», texto `ambar` 13 sp en negrita, borde de
  1 dp `ambar_tenue` con radio 10 dp (`drawable/widget_button_bg.xml`) y el
  ícono de «se abre afuera». Cada uno mide al menos 44 dp de alto
  (`minHeight="44dp"`). Abren en el navegador las mismas páginas que
  `OfficialSite.miStm` y `OfficialSite.recarga`
  (`lib/services/official_sites.dart`).
- **Letra:** la del sistema, no las fuentes de la app. La fila del ómnibus
  usa `sans-serif-condensed`; el estado vacío y los accesos, la letra por
  defecto.
- **Colores:** `res/values/colors.xml` repite los tokens con nombres de
  Android: `etiqueta` = `etiquetaCartel`, `linea_noche` = `lineaNoche`,
  `ambar_tenue` = `ambarTenue`. Contraste sobre `tinta`: `papel` 14.6:1,
  `etiqueta` 7.9:1, `ambar` 9.5:1, el reloj `tenue` 5.3:1.
- **Íconos:** `drawable/widget_ic_clock.xml`, `widget_ic_route.xml` y
  `widget_ic_external.xml` son los glifos `clock`, `route` y `external` de
  `PixelGlyphs` pasados a vector, con el color fijo en cada archivo. No hay un
  script en el repositorio que los genere: si cambiás uno de esos glifos,
  rehacé su vector a mano: cada celda encendida de la grilla de 12 × 12, en
  la columna `x` y la fila `y`, es un cuadrado
  `M{x}.07,{y}.07h0.86v0.86h-0.86z` en un `viewport` de 12 × 12
  ([04-iconos.md](04-iconos.md)).
- **TalkBack:** lee la fila como una frase: «Línea 116 a POCITOS, alrededor
  de las 19:56, estimado».

### Qué muestra: las claves

`WidgetFeed` escribe estas claves con `home_widget` y
`MVDTransporteWidgetProvider` las lee. Los nombres están en constantes de
`WidgetFeed` (`keyLine`, `keyDestination`, etc.).

| Clave | Tipo | Valor | ¿La lee Kotlin? |
|---|---|---|---|
| `route_line` | String o nada | La línea del ómnibus. Si no está, el widget muestra el estado vacío | Sí |
| `route_dest` | String | El `destination` del ómnibus; si viene vacío, el nombre que el usuario le puso a la ruta (`RouteAlert.destinationName`) | Sí |
| `route_eta_min` | int | `etaMinutes` en el momento de la consulta | Sí, solo como respaldo |
| `route_eta_at` | String | El `clockTime` del ómnibus, «H:MM» sin cero adelante («8:07», «19:56») | Sí |
| `route_expected_at_ms` | String | `expectedAt` pasado al reloj del teléfono (más la hora del teléfono al consultar, menos el `fetchedAt` del tablero), en milisegundos desde 1970, en decimal | Sí |
| `route_checked_at_ms` | String | Cuándo se consultó el tablero, en milisegundos | No |
| `route_status` | String | `ok`, `none`, `offline` u `off` | No |

### Reglas

- **Qué ruta:** la primera ruta con el aviso activado, en el orden de la
  pestaña Rutas, a cualquier hora (el horario del aviso no cuenta para el
  widget).
- **Qué ómnibus:** el primero del tablero de la parada de origen de esa ruta
  que pasa `RouteAlert.accepts` (sus líneas y su dirección).
- **Estados que escribe `WidgetFeed.update`:**
  - tablero bien y hay ómnibus → `ok`, se escribe la fila;
  - tablero bien y no hay ómnibus → `none`, `route_line` se borra;
  - el tablero falló o falta → `offline`; la fila anterior se queda mientras
    `route_expected_at_ms` esté en el futuro del reloj del teléfono, si no
    `route_line` se borra;
  - no hay ninguna ruta con aviso → `off`, `route_line` se borra.
- **`WidgetFeed.clear('off')`:** lo llama `BackgroundWorker.sync()` cada vez
  que no queda ninguna ruta con el aviso activado, aunque una alerta de
  parada mantenga viva la tarea periódica. Sin ruta, la app no escribe el
  widget y la tarea lo pondría en `off` recién en su próxima pasada, 15 min o
  más después, así que no debe quedar una fila vieja. Sin ningún aviso, la
  tarea además se cancela.
- **Quién escribe:**
  - la consulta periódica de fondo (`BackgroundWorker.checkAlerts`), al menos
    cada 15 min;
  - la app, después de cada actualización de Mis paradas que incluyó la
    parada de origen de esa ruta (`_refresh` en `lib/ui/stops_page.dart`).
- **Redibujo:** después de escribir, `WidgetFeed` siempre llama a
  `HomeWidget.updateWidget`, con su propio manejo de errores. Además Android
  redibuja cada 30 min (`updatePeriodMillis` = 1800000).
- **Caducidad:** Kotlin oculta la fila cuando la hora del teléfono pasa
  `route_expected_at_ms` + 2 min (`EXPIRED_AFTER_MS`). Con proxy las dos
  están en el reloj del teléfono, así que uno con la hora corrida respecto
  de la fuente no oculta la fila antes ni después de tiempo. Sin proxy,
  `fetchedAt` es la hora del teléfono cuando llega la respuesta: la
  diferencia da cero y `route_expected_at_ms` queda en la hora que da la
  Intendencia (`time`). Solo se comprueba al
  redibujar, así que entre redibujos un ómnibus que ya pasó puede verse hasta
  unos 30 min. Es un tema abierto: un redibujo programado a esa hora lo
  cerraría.
- **Respaldos de Kotlin:** con `route_eta_at` muestra «~H:MM». Sin esa clave
  (filas guardadas por versiones viejas) muestra «ahora» si `route_eta_min`
  es 0 o «N min». La fila se muestra solo si hay `route_line`, `route_dest` y
  `route_eta_min` ≥ 0. Una fila sin `route_expected_at_ms` no caduca.
- **Por qué el destino del ómnibus y no el nombre de la ruta:**
  [12-decisiones.md](12-decisiones.md#el-widget-muestra-el-destino-del-ómnibus).

## Notificaciones

Todas se generan en el teléfono (`flutter_local_notifications` y
`flutter_foreground_task`). No hay notificaciones remotas.

### Canales de Android

| Id | Nombre | Descripción | Para qué | Dónde |
|---|---|---|---|---|
| `bus_alerts` | Alertas de ómnibus | Avisos cuando tu ómnibus está por llegar | Avisos de parada, avisos de ruta, el aviso final de «Estoy esperando» | `NotificationService` (`lib/services/notification_service.dart`), importancia alta, con sonido |
| `bus_wait` | Esperando un ómnibus | Aviso fijo mientras la app sigue a tu ómnibus («Estoy esperando») | El aviso fijo del servicio en primer plano | `AndroidBusWait.init` (`lib/services/bus_wait_service.dart`), `onlyAlertOnce` |

### Ícono y color

- **Ícono chico:** `@drawable/ic_stat_timbre`, la silueta blanca del ómnibus
  con el cartel y el parabrisas huecos. Android dibuja ese ícono solo por su
  forma: uno a color sería una mancha blanca. El aviso fijo lo toma de
  `AndroidManifest.xml` (`com.liberontech.stmapp.NOTIFICATION_ICON`).
- **Acento:** `TimbreColors.tinta`, en las notificaciones (`color:`) y en el
  aviso fijo (`NotificationIcon.backgroundColor`). Sobre la cortina clara
  tiene 17:1 contra blanco; según el comentario del código, Android lo aclara
  en la cortina oscura. El ámbar no se usa: en la cortina clara se vería
  marrón ([12-decisiones.md](12-decisiones.md#el-acento-de-las-notificaciones-es-el-azul-del-tablero)).
- **Fondo:** no se pinta. `flutter_foreground_task` solo fija el color del
  acento, no ofrece la notificación coloreada.

### Textos

`N` son los minutos del ómnibus; `PARADA` es el nombre de la parada como lo
guardaste («SAN JOSE y ANDES»).

**Aviso de parada** (`NotificationService.showBusAlert`). Lo usan la consulta
de fondo y el final de «Estoy esperando».

| Minutos | Título | Texto |
|---|---|---|
| 0 o menos | «Línea 116 — llegando» | «Tu ómnibus está llegando a PARADA» |
| 1 | «Línea 116 — 1 min» | «Tu ómnibus está llegando a PARADA» |
| 2 o más | «Línea 116 — N min» | «Tu ómnibus llega en N min a PARADA» |

**Aviso de ruta** (`NotificationService.showRouteAlert`). `DESTINO` es el
nombre que le pusiste a la ruta («Centro»). El texto largo usa
`BigTextStyleInformation`.

| Minutos | Título | Texto |
|---|---|---|
| 1 o menos | «Línea 116 → DESTINO» | «Tu ómnibus está llegando a ORIGEN» |
| 2 o más | «Línea 116 → DESTINO» | «Sale en N min desde ORIGEN» |

**Aviso fijo de «Estoy esperando»** (Android; `BusWait.title` y
`BusWait.statusText` en `lib/models/bus_wait.dart`).

- Título: «Esperando el 116 → POCITOS», o «Esperando el 116» si el ómnibus no
  tiene destino.
- Texto: `estado · PARADA`, donde el estado es uno de:
  - «Llega en N min» (con GPS);
  - «Llegando» (con GPS, 0 min o menos);
  - «Según horario 20:17, sin GPS todavía» (sin GPS, con la hora del horario);
  - «Sin datos del ómnibus por ahora» (el viaje no aparece en la respuesta);
  - «Sin conexión, reintentando…» (la consulta falló).
- Botón: «Dejar de esperar».

**Recordatorio de «Estoy esperando»** (iOS;
`NotificationService.scheduleWaitReminder`). `M` son los minutos que elegiste
(3, 5 o 10).

| Título | Texto |
|---|---|
| «Línea 116 — ~M min» | «Debería llegar en unos M min a PARADA» |

### Cuándo salen

- **Consulta de fondo** (`lib/services/background_worker.dart`): una tarea de
  WorkManager cada 15 min (primera a los 2 min, con red y sin batería baja).
  Pide una sola vez cada parada que haga falta, todas en paralelo
  (`MvdApiService.getBoards`). Avisa solo por ómnibus con GPS
  (`isRealTime`) que estén dentro de los minutos del aviso, y solo dentro del
  horario del aviso (`AlertSchedule.allows`). Si una parada no se pudo
  consultar, no avisa nada sobre ella. Cada aviso tiene un id fijo por línea
  y parada (o línea y destino, en las rutas), así que uno nuevo reemplaza al
  anterior en vez de apilarse.
- **«Estoy esperando» en Android** (`AndroidBusWait`,
  `lib/services/bus_wait_task.dart`): un servicio en primer plano de tipo
  `dataSync` consulta la parada cada 30 s, también con la pantalla apagada, y
  actualiza el aviso fijo. Termina cuando el ómnibus seguido tiene GPS y está
  a los minutos elegidos o menos (entonces manda el aviso de parada), cuando
  el viaje pasó (no aparece 2 min después de su hora), a los 60 min o con el
  botón. «Su hora» es `BusWait.expectedOnPhone`: el `expectedAt` de la fuente
  más la diferencia de relojes que se mide con cada tablero (la hora del
  teléfono menos su `fetchedAt`). No vuelve a arrancar solo
  (`allowAutoRestart: false`).
- **«Estoy esperando» en iOS** (`ScheduledBusWait`): iOS no deja consultar en
  segundo plano sin un servidor de push, así que la app programa un
  recordatorio a `expectedOnPhone − minutos elegidos` (o a los 5 s, si esa
  hora ya pasó): las notificaciones locales van con el reloj del teléfono.
  Al empezar, la diferencia de relojes es la del tablero de la fila. Cada
  vez que la app actualiza Mis paradas en primer plano, mueve el
  recordatorio a la hora nueva; si en ese momento el ómnibus tiene GPS y está
  a los minutos elegidos o menos, manda enseguida el aviso de parada y
  termina. `AppDelegate.swift` registra el delegado de notificaciones para que
  iOS las muestre también con la app abierta.
- **Permiso:** la app pide permiso de notificaciones al activar un aviso, al
  empezar a esperar un ómnibus y, después del primer desbloqueo, si ya había
  avisos activados (`AppLockState._setupAfterAuth` en `lib/ui/app_lock.dart`).

Lo que dice la app alrededor de «Estoy esperando» (`_showWaitSheet` en
`lib/ui/stops_page.dart`):

- En la hoja, bajo el botón «Avisarme cuando llegue»: en Android «Verás un
  aviso fijo mientras la app sigue al ómnibus, también con la pantalla
  apagada. Avisa cuando el ómnibus tiene GPS.»; en iOS «Te avisamos a la hora
  estimada. Si abrís la app mientras esperás, el aviso se ajusta al GPS.»
- Al empezar: «Te avisamos cuando el 116 esté a M min».
- Si el ómnibus ya está a los minutos elegidos o menos, no empieza nada y
  dice «El 116 ya está a N min».
- Si no se pudo empezar: «No se pudo activar el aviso. Revisá que las
  notificaciones estén permitidas y probá de nuevo.»

## Plataformas

- **iOS sin widget:** no hay extensión de widget ni App Group. `WidgetFeed`
  intenta escribir igual y atrapa el error.
- **iOS sin consulta de fondo:** `Info.plist` no declara
  `BGTaskSchedulerPermittedIdentifiers` y `AppDelegate.swift` no registra la
  tarea, así que en iOS la tarea periódica no corre. `BackgroundWorker.sync`
  atrapa el error. Los avisos de parada y de ruta salen solo en Android; en
  iOS solo existe el recordatorio de «Estoy esperando».
- **Verificación:** los recursos de Android y el widget se comprueban con
  `flutter build apk --debug` y con `test/brand_assets_test.dart`; no hay
  pruebas en emulador. Los cambios de iOS (`Info.plist`, storyboard) no se
  compilaron en esta versión.

## Tiendas

- **Nombre:** «Timbre MVD», el mismo que muestra el teléfono:
  `android:label` en `AndroidManifest.xml`, `app_name` en
  `res/values/strings.xml`, `CFBundleDisplayName` y `CFBundleName` en
  `ios/Runner/Info.plist`, y `title` de `MaterialApp` en `lib/main.dart`. Los
  textos de la ficha están en [docs/store-listing.md](../store-listing.md).
- **Lo que no cambia con el nombre:** el id de la app
  `com.liberontech.stmapp` (Android e iOS; Google Play trata un
  `applicationId` nuevo como otra app, dice
  `android/app/build.gradle.kts`), el paquete Dart `stm_app` y la clase
  `MVDTransporteWidgetProvider`.
- **Descripción del widget** en el selector: «Próximo ómnibus de tus rutas y
  accesos a Mi STM y Recarga» (`widget_description`).
- **Permiso de ubicación en iOS:** «Timbre MVD usa tu ubicación para
  mostrarte las paradas cercanas.», en `NSLocationWhenInUseUsageDescription`
  y en `NSLocationAlwaysAndWhenInUseUsageDescription` (geolocator hace
  referencia a la segunda, por eso queda).
- **Ícono de Google Play** (512 px): el mismo `assets/app_icon.png`, reducido.
- **Capturas:** solo pantallas de la app. Nada de capturas de stm.gub.uy ni
  logos del STM o de la Intendencia. Una captura del Mapa lleva «© OpenStreetMap»
  a la vista, como en la app, que lo muestra siempre.
- **Servicio en primer plano:** Google Play pide declarar el tipo `dataSync`
  de «Estoy esperando» con un video; el texto propuesto está en
  [docs/store-listing.md](../store-listing.md).

## Regenerar

```bash
dart run flutter_launcher_icons        # íconos; hace falta la 0.14+ para el monocromo
dart run flutter_native_splash:create  # pantalla de inicio
```

Después de `flutter_native_splash:create`, volvé a poner `@color/noche` como
`android:windowBackground` de `NormalTheme` en `values-v31/styles.xml` y
`values-night-v31/styles.xml`, y corré `flutter test test/brand_assets_test.dart`.

Los PNG de `assets/` salen del vector de la marca; qué es cada uno está en
[assets/README.md](../../assets/README.md).

---

Ver también: [08-componentes.md](08-componentes.md) (la fila del ómnibus en
la app), [11-accesibilidad.md](11-accesibilidad.md),
[13-en-el-codigo.md](13-en-el-codigo.md).
