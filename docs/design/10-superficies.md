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

## Widgets de parada (Android)

Tres tableros con los próximos ómnibus de tus paradas guardadas, del mismo
material que la tarjeta de Mis paradas. Existen solo en Android: en iOS no
hay widget (ver [Plataformas](#plataformas)). Reemplazan al widget de ruta
(3 × 2, la próxima ruta con aviso), que se quitó.

| Widget (selector) | Clase | Celdas, mínimo | Qué muestra |
|---|---|---|---|
| Timbre · Próximo | `TimbreProximoWidget` | 2 × 2, 140 × 140 dp | Una parada: el próximo ómnibus grande («~20:14») y los dos siguientes en una línea («538 ~20:16 · 144 ~20:17») |
| Timbre · Parada | `TimbreParadaWidget` | 4 × 2, 250 × 150 dp | Una parada y sus próximos tres ómnibus, en filas |
| Timbre · Mis paradas | `TimbreMisParadasWidget` | 4 × 4, 250 × 320 dp | Dos paradas con tres ómnibus cada una, la placa TIMBRE MVD y los accesos a Mi STM y Recarga |

Archivos:

- `android/app/src/main/kotlin/com/liberontech/stmapp/TimbreStopWidget.kt`:
  los tres providers. Dibujan, cambian de parada, piden datos y programan
  el redibujo.
- `android/app/src/main/kotlin/com/liberontech/stmapp/StopWidgetData.kt`:
  las reglas, sin Android.
- `res/layout/widget_stop_small.xml`, `widget_stop_medium.xml`,
  `widget_stop_large.xml`, la fila `widget_stop_row.xml` y las vistas
  previas `*_preview.xml`; `res/xml/widget_stop_*_info.xml`.
- `lib/services/stop_widgets_feed.dart` (`StopWidgetsFeed`): escribe los
  datos y atiende el botón de actualizar.

### Cómo se ven

- **Tablero:** fondo `tinta`, borde de 1 dp `linea_noche`, radio 20 dp
  (`widget_background.xml`), margen interior de 10 a 14 dp. Arriba, LEDs apagados (`widget_led_band.xml`: un punto `ambar` al 16 %
  cada 6 dp, que se apaga hacia la izquierda y hacia abajo, como la app
  bar). Desde Android 12 el contenido se recorta a las esquinas
  (`clipToOutline`).
- **Encabezado:** `stop` en `ambar`, el nombre de la parada en `papel` y
  « · 574» más chico en `etiqueta` (Próximo muestra solo el nombre). Mis
  paradas lleva arriba la placa TIMBRE MVD (`drawable-nodpi/widget_plate.png`,
  20 dp de alto: el ómnibus y «TIMBRE» en ámbar, «MVD» en ámbar tenue, en
  letras de puntos; TalkBack la lee «Timbre MVD»).
- **Fila** (`widget_stop_row.xml`, 30 dp):
  - número de línea en un contorno `ambarTenue` de 1.5 dp, radio 8 dp,
    cifras `ambar` 16 sp en negrita (`widget_badge_lit_bg.xml`);
  - destino en `papel` 16 sp, una línea, con «…» si no entra;
  - marca accesible `etiqueta` de 14 dp, si el ómnibus lo es;
  - reloj `ambarTenue` de 13 dp y la hora «~20:14» en `papel` 18 sp.

  Entre filas, una línea `linea_noche` de 1 dp. En Próximo el próximo
  ómnibus va aparte: número de 17 sp, destino en hasta dos líneas y la hora
  en 34 sp; los dos siguientes, con sus números en `ambar`.
- **Actualizar:** `refresh` en `ambar`, 18 dp dentro de un blanco táctil de
  44 dp. En Parada y Mis paradas va arriba a la derecha; en Próximo, abajo,
  para que el nombre de la parada use todo el ancho.
- **Pie** (`tenue` 11 sp):
  - «Datos de las 20:13», la consulta más vieja de las paradas que muestra
    (Parada suma « · horas estimadas»);
  - «Actualizando…» hasta 30 s después de tocar actualizar, o hasta que
    llegan los datos;
  - si la última consulta falló: `warning` y «No se pudo actualizar. Datos
    de las 19:58.» en `rojoLed`;
  - sin datos todavía: «Tocá para actualizar».
- **Sin ómnibus:** «Sin próximos ómnibus en esta parada» en `etiqueta`
  14 sp. Si el tablero tiene más de 10 min, «Sin datos recientes. Tocá para
  actualizar», y tocarlo actualiza: sus ómnibus pueden haber pasado.
- **Sin paradas guardadas:** el cartel vacío de la app. LEDs apagados al
  11 % (`widget_led_field.xml`), `bus` en `ambar`, «SIN PARADAS» en Doto
  (`drawable-nodpi/widget_sin_paradas.png`, 20 dp de alto) y «Agregá una
  parada en Mis paradas para verla acá.».
- **Letra:** la del sistema (`sans-serif-condensed`), no las fuentes de la
  app. «SIN PARADAS» es una imagen hecha con Doto.
- **Ámbar:** la línea, el cartel de la parada, actualizar y los LEDs. La
  hora nunca: es una estimación ([02-color.md](02-color.md#excepciones-documentadas),
  [12-decisiones.md](12-decisiones.md#los-widgets-de-parada-encienden-la-línea-no-la-hora)).
- **Selector de widgets** (Android 12+): `previewLayout` con datos de
  muestra de las paradas 574 y 3140 (`test/fixtures`).
- **TalkBack:** cada fila es una frase: «Línea 121 a PUNTA CARRETAS,
  alrededor de las 20:14, estimado, accesible». El encabezado dice
  «Parada SAN JOSE y ANDES, 574. Tocá para ver otra parada».

### Qué se toca

- **El nombre de la parada:** muestra la siguiente parada guardada que el
  widget no muestra, en el orden de Mis paradas. Cada widget recuerda la
  suya. Si no hay otra, abre la app.
- **Actualizar** (y «Sin datos recientes»): pide los arribos sin abrir la
  app.
- **El resto del widget:** abre la app. En Mis paradas, «Mi STM» y
  «Recarga» (texto `ambar` en un borde `ambarTenue`, 44 dp de alto,
  `widget_button_bg.xml` y `widget_ic_external.xml`) abren en el navegador
  las mismas páginas que `OfficialSite.miStm` y `OfficialSite.recarga`.

### Las claves de los widgets de parada

Viven en las preferencias de `home_widget` (`HomeWidgetPreferences`). Los
nombres están en constantes de
`StopWidgetsFeed` y de `TimbreStopWidget`.

| Clave | La escribe | Valor |
|---|---|---|
| `stops_saved` | La app (`StopWidgetsFeed.saveStops`): al cargar Mis paradas y en cada consulta de fondo con un widget puesto | JSON `[{"id", "name"}]`, en el orden de Mis paradas |
| `stop_board_{id}` | La app (`StopWidgetsFeed.updateBoards`): después de cada actualización de Mis paradas, en la consulta de fondo y al tocar actualizar | JSON `{"checkedAtMs", "failedAtMs", "arrivals"}` con hasta 6 ómnibus `{"line", "dest", "clock", "dueMs", "acc"}`. `dueMs` es `expectedAt` pasado al reloj del teléfono (más la hora del teléfono al consultar, menos el `fetchedAt` del tablero; sin proxy, `fetchedAt` es el encabezado `Date` de transporteRest), así un teléfono con la hora corrida no saca un ómnibus antes ni después de tiempo; un `destination` vacío se escribe «Línea 121»; `failedAtMs` aparece cuando una consulta falla, y los ómnibus quedan |
| `stops_shown` | El widget | Los ids de las paradas que muestran los widgets puestos, separados por comas |
| `stop_widgets_placed` | El widget | Cuántos widgets de parada hay en la pantalla de inicio |

La parada que eligió cada widget y las horas de actualizar viven aparte, en
las preferencias `timbre_stop_widgets` (`widget_{id}_stops`,
`refresh_tap_ms`, `refresh_asked_ms`).

### Reglas

- **Qué paradas:** las que eligió el widget y siguen guardadas; si no, las
  primeras de Mis paradas. Nunca la misma dos veces.
- **Qué ómnibus:** los del tablero hasta 1 min después de su `dueMs`
  (`EXPIRED_AFTER_MS`, como Mis paradas), por hora. Sin conexión, cada uno
  se va solo a su hora.
- **Redibujo:** una alarma no exacta (`AlarmManager.set`, RTC: no despierta
  el teléfono) a la hora en que se va el primer ómnibus a la vista, cuando
  termina «Actualizando…» o cuando un tablero cumple 10 min. Además,
  `updatePeriodMillis` = 30 min.
- **Datos nuevos:**
  - la app, después de cada actualización de Mis paradas (cada 30 s con la
    pantalla a la vista);
  - la consulta de fondo (`BackgroundWorker.checkAlerts`), al menos cada
    15 min y a cualquier hora, para las paradas de `stops_shown`. Con un
    widget de parada puesto, `BackgroundWorker.sync` mantiene la tarea
    aunque no haya avisos;
  - actualizar: el botón manda `ACTION_REFRESH` al widget, que anota la
    hora y le pide datos a la app (`HomeWidgetBackgroundReceiver`,
    `timbre://refresh`). La app corre `stopWidgetsCallback` en segundo
    plano: pide los tableros de `stops_shown`, los escribe, redibuja y
    registra la tarea de fondo si hay widgets. El widget también pide datos
    solo cuando muestra una parada sin tablero (recién puesto, o al cambiar
    de parada). Como mucho un pedido cada 15 s (`REFRESH_GAP_MS`).
- **Un 429** no cambia nada: ni datos ni error.
- **Con el bloqueo biométrico activado** el widget muestra igual las
  paradas y los horarios: están en la pantalla de inicio, fuera de la app.

### Cómo se prueban

- `test/stop_widgets_feed_test.dart` y `test/background_worker_test.dart`:
  lo que escribe la app.
- `test/brand_assets_test.dart`: los recursos (cada vista que llena el
  provider existe, blancos de 44 dp, ninguna vista que RemoteViews no
  admita, la hora en `papel`).
- `android/app/src/test/.../StopWidgetDataTest.kt`: las reglas, en la JVM.
- `android/app/src/test/.../StopWidgetRenderTest.kt` (Robolectric): pone
  los tres widgets, los llena el provider de verdad y Android infla sus
  RemoteViews, así una vista no admitida falla acá y no en el teléfono.
  Guarda las imágenes en `build/widget-previews/`.

Desde `android/`: `./gradlew :app:testDebugUnitTest`.

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

- **iOS sin widget:** no hay extensión de widget ni App Group.
  `StopWidgetsFeed` intenta escribir igual y atrapa el error.
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
  `android/app/build.gradle.kts`) y el paquete Dart `stm_app`.
- **Widgets en el selector:** «Timbre · Próximo», «Timbre · Parada» y
  «Timbre · Mis paradas», con sus descripciones en `res/values/strings.xml`
  (`widget_*_label`, `widget_*_description`).
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
