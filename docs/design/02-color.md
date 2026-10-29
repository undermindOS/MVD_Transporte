# Color

Un solo tema, «Noche». Los colores son los 12 tokens de `TimbreColors`
(`lib/ui/theme/timbre_tokens.dart`); en los widgets no se escriben
literales `Color(0x…)`. El mapa base del Mapa tiene seis tonos más, que
viven en su estilo y no en los widgets ([el mapa base](#el-mapa-base)).

## Los tokens

| Token | Valor | Para qué se usa |
|---|---|---|
| `noche` | `#070F22` | Fondo de pantalla (el tablero), app bar, relleno de los campos de texto, filas de novedades ya leídas. Ícono sobre el fondo `rojoLed` de deslizar para borrar. En el Mapa: el fondo del mapa base, el recuadro de «© OpenStreetMap» y el borde que separa las píldoras de los ómnibus. |
| `tinta` | `#0A1A3A` | Paneles: tarjetas, hojas, diálogos, barra de navegación, cartel TIMBRE MVD, pantalla de bloqueo, filas de novedades sin leer, encabezados de hora en Horarios, notas y baldosas de las paradas del Mapa. Único color de texto sobre `ambar`. Acento de las notificaciones. |
| `tintaAlta` | `#13284F` | Lo que se levanta del panel: la fila del ómnibus que esperás, el indicador de la pestaña elegida, snackbar, tooltip, chip sin elegir, pista del switch apagado, botón principal desactivado. |
| `lineaNoche` | `#22396A` | Bordes y divisores. Decoración, nunca texto. |
| `papel` | `#F1ECE2` | Texto principal. Íconos de la app bar (`iconTheme` del tema). |
| `etiquetaCartel` | `#9FB0D0` | Texto secundario y rótulos, subtítulo de la app bar, hora de horario, contorno de la insignia de una línea sin GPS, marcas pasivas: confort, íconos de lista y de campo. |
| `tenue` | `#7F8FB3` | Texto terciario: pistas de los campos, subpestañas y navegación sin elegir, reloj de las filas sin GPS, notas al pie. |
| `ambar` | `#FFB21E` | Luz: ver [la regla del ámbar](#la-regla-del-ámbar). |
| `ambarTenue` | `#C68B1E` | Luz atenuada: «MVD» del cartel TIMBRE MVD, «min» de los minutos en vivo, borde de los botones con contorno y de los paneles de aviso, marca de enlace externo en los mosaicos de Servicios. |
| `ambarClaro` | `#FFE2A3` | El punto más brillante: la línea de barrido y los puntos más claros del candado `LedLock`. No se usa en ningún otro lado. |
| `rojoLed` | `#FF6B57` | Errores y borrado: ver [errores y avisos](#errores-y-avisos). |
| `avisoNoche` | `#2A2210` | Fondo del panel de aviso sobre una lista. |

Dos comentarios de `timbre_tokens.dart` no coinciden con el uso real: el
de `tintaAlta` nombra hojas y campos, pero el tema pinta las hojas con
`tinta` y los campos con `noche`; el de `ambarClaro` nombra el foco, pero
el foco es `ambar`.

### Cómo los reparte el tema

`buildTimbreTheme()` (`lib/ui/theme/timbre_theme.dart`) arma un
`ColorScheme` oscuro con esos tokens. Los roles que más importan:

| Rol | Token |
|---|---|
| `primary` / `onPrimary` | `ambar` / `tinta` |
| `secondary` | `etiquetaCartel` |
| `tertiary` | `ambarTenue` |
| `error` / `onError` | `rojoLed` / `noche` |
| `surface` / `onSurface` | `tinta` / `papel` |
| `onSurfaceVariant` | `etiquetaCartel` |
| `surfaceContainerHigh`, `surfaceContainerHighest` | `tintaAlta` |
| `outline`, `outlineVariant` | `lineaNoche` |
| `inverseSurface` / `onInverseSurface` | `tintaAlta` / `papel` |
| `shadow` | `noche` |
| `scrim` | `noche` al 70 % |
| `surfaceTint` | transparente |
| `scaffoldBackgroundColor`, `canvasColor` | `noche` |

Los diálogos y las hojas de Flutter 3.41 no leen `scrim`: como el tema no
define `barrierColor`, la capa que oscurece la pantalla detrás de ellos es
el `Colors.black54` de Flutter.

## Contrastes

Contraste WCAG 2.x, calculado con los valores de los tokens. El texto
necesita 4.5:1 o más sobre su fondo; los íconos y bordes que llevan
sentido, 3:1. Lo desactivado y lo decorativo no tienen mínimo.

Todas las combinaciones de texto y fondo:

| Texto \ fondo | `noche` | `tinta` | `tintaAlta` | `avisoNoche` |
|---|---|---|---|---|
| `papel` | 16.21 | 14.60 | 12.35 | 13.36 |
| `etiquetaCartel` | 8.72 | 7.85 | 6.64 | 7.19 |
| `tenue` | 5.89 | 5.31 | **4.49** | 4.86 |
| `ambar` | 10.58 | 9.53 | 8.06 | 8.72 |
| `ambarTenue` | 6.46 | 5.82 | 4.93 | 5.33 |
| `rojoLed` | 6.81 | 6.13 | 5.19 | 5.61 |
| `ambarClaro` | 15.14 | 13.64 | 11.54 | 12.48 |
| `lineaNoche` | 1.69 | 1.52 | 1.29 | 1.39 |

Los pares que la app usa de verdad:

| Primer plano sobre fondo | Contraste | Dónde | Mínimo |
|---|---|---|---|
| `papel` / `noche` | 16.21 | Texto sobre la pantalla: filas de Horarios, títulos de novedades leídas | 4.5 |
| `papel` / `tinta` | 14.60 | Nombre de parada, destino, texto de diálogos y hojas | 4.5 |
| `papel` / `tintaAlta` | 12.35 | Snackbar, tooltip, chip sin elegir, destino del ómnibus que esperás | 4.5 |
| `papel` / `avisoNoche` | 13.36 | Texto del aviso de GPS parcial | 4.5 |
| `etiquetaCartel` / `noche` | 8.72 | Subtítulo de la app bar, horas de Horarios, rótulos de los campos | 4.5 |
| `etiquetaCartel` / `tinta` | 7.85 | Número de parada, notas, encabezado de hora, contorno de la insignia sin GPS | 4.5 |
| `etiquetaCartel` / `tintaAlta` | 6.64 | Marcas de confort del ómnibus que esperás | 3 |
| `tenue` / `noche` | 5.89 | Pistas de los campos, subpestañas sin elegir, nota al pie de Novedades | 4.5 |
| `tenue` / `tinta` | 5.31 | Navegación sin elegir, «Líneas · Hacia» de una ruta, reloj de las filas sin GPS | 4.5 |
| `tenue` / `tintaAlta` | 4.49 | Texto del botón principal desactivado, pulgar del switch apagado | sin mínimo (desactivado) |
| `ambar` / `noche` | 10.58 | Título de página, subpestaña elegida, borde y rótulo del campo con foco | 4.5 |
| `ambar` / `tinta` | 9.53 | Minutos en vivo, texto de los botones, navegación elegida | 4.5 |
| `ambar` / `tintaAlta` | 8.06 | Minutos del ómnibus que esperás, acción del snackbar | 4.5 |
| `ambar` / `avisoNoche` | 8.72 | Ícono del panel de aviso, texto del aviso de Novedades | 4.5 |
| `ambarTenue` / `tinta` | 5.82 | «MVD» del cartel, «min», enlace externo en Servicios | 4.5 |
| `ambarTenue` / `tintaAlta` | 4.93 | «min» del ómnibus que esperás | 4.5 |
| `rojoLed` / `tinta` | 6.13 | Nota de error en la tarjeta, errores de los campos en los diálogos | 4.5 |
| `rojoLed` / `tintaAlta` | 5.19 | Ícono del snackbar de error | 3 |
| `rojoLed` / `noche` | 6.81 | Ícono del error de Horarios | 3 |
| `tinta` / `ambar` | 9.53 | LLEGANDO, línea con GPS, botón principal, segmento y chip elegidos, contador | 4.5 |
| `tinta` / `ambarTenue` | 5.82 | Botón «Desbloquear» mientras está abierto el pedido del sistema | 4.5 |
| `noche` / `rojoLed` | 6.81 | Papelera al deslizar para borrar | 3 |
| `ambarClaro` / `tinta` | 13.64 | Barrido del candado de la pantalla de bloqueo | decoración |
| `lineaNoche` / `noche` y `tinta` | 1.69 y 1.52 | Bordes y divisores | decoración |

Pares prohibidos:

- `papel` sobre `ambar`: 1.53:1. Sobre ámbar el texto es siempre `tinta`.
- `ambar` sobre blanco: 1.80:1. Por eso no hay superficies claras.

Lo que hay que saber:

- `tenue` sobre `tintaAlta` da 4.49:1, apenas por debajo de 4.5. Solo se
  usa para lo desactivado y para el pulgar del switch apagado, que no es
  texto. No pongas texto activo `tenue` sobre `tintaAlta`.
- Los bordes `lineaNoche` dan 1.52 a 1.69:1, por debajo de 3:1. Son
  decoración: un campo se reconoce por su rótulo, su ícono y el borde
  ámbar de 2 px con foco; una tarjeta, por su contenido. Si algún día hace
  falta un campo que se reconozca sin rótulo, el borde tiene que subir a
  3:1.
- Algunos comentarios de `timbre_tokens.dart` redondean distinto: dicen
  15:1 para `papel` sobre `tinta` (14.60), 8.6:1 para `etiquetaCartel`
  sobre `noche` (8.72) y 6.2:1 para `rojoLed` sobre `tinta` (6.13). Valen
  los números de esta tabla.

## La regla del ámbar

Ámbar = luz = dato en vivo. Si todo brilla, la luz no dice nada.

Se enciende:

| Qué | Dónde en el código |
|---|---|
| Datos en vivo | `MinutosEnVivo` (punto y cifras), `LlegandoChip`, `LineBadge(live: true)`, `CartelTira`, la campana de `ArrivalRow` cuando esperás ese ómnibus, los ómnibus con GPS del Mapa (píldora o punto de `BusLayer`) |
| Los carteles de la marca | `CartelCompacto` («TIMBRE»; «MVD» en `ambarTenue`), `TimbreText.pageTitle`, «BLOQUEADA» y `LedLock`, «NO OFICIAL» en Info, el cartel de `TimbreEmptyState`, `TimbreBus` |
| La acción principal | `FilledButton`, `ElevatedButton`, `FloatingActionButton` y «Desbloquear»: relleno `ambar`, texto `tinta` |
| Las demás acciones | Texto de `OutlinedButton` y `TextButton` (el borde del primero es `ambarTenue`), acción del snackbar |
| Lo elegido o encendido | Segmento de `TimbreSegmented`, chip elegido, switch encendido, subpestaña elegida, ícono y rótulo de la navegación elegida, mosaicos de Servicios, campana de un aviso activado y la campana de la fila «Aviso N min antes» |
| El foco | Borde del campo con foco (2 px), rótulo flotante, cursor, selección de texto (ámbar al 32 %) |
| El progreso | Indicadores de carga y de deslizar para actualizar |
| Los contadores | Insignia de novedades sin leer en la pestaña Novedades |
| Los avisos | Ícono del panel `avisoNoche`; texto del aviso de Novedades |
| La textura | LEDs apagados de `LedMatrix`: ámbar al 9 a 11 % |
| Los widgets de parada de Android | El número de línea (contorno `ambarTenue`, cifras `ambar`), el cartel `stop` del encabezado, el botón de actualizar, los números de línea de «538 ~20:16 · 144 ~20:17» en Próximo y los LEDs apagados del encabezado (16 %) ([10-superficies.md](10-superficies.md#widgets-de-parada-android)) |

No se enciende:

- Un horario: `TimbreText.scheduleTime` en `etiquetaCartel`,
  `LineBadge(live: false)` en contorno, reloj `tenue`.
- Una fila vieja, después de una actualización fallida o de un tablero que
  llegó hace 1 min o más: `ArrivalRow(stale: true)` muestra «~20:01» como
  estimación, con la insignia apagada y sin campana, aunque esa fila haya
  tenido GPS.
- El encabezado de hora de Horarios (`etiquetaCartel`).
- El texto «Aviso 5 min antes · …» de un aviso: es un ajuste, va en
  `etiquetaCartel`; solo la campana va en ámbar.
- Las marcas pasivas: confort, íconos de lista (`listTileTheme.iconColor`
  es `etiquetaCartel`), íconos de los campos, candado de Info, nota del
  navegador en Servicios.
- La hora estimada de los widgets de Android («~14:32»): `papel`, siempre
  con «~» y reloj ([10-superficies.md](10-superficies.md#widgets-de-parada-android)).
- En el Mapa: las paradas guardadas (`stop` en `papel` sobre `tinta`, con
  borde `etiquetaCartel`), un ómnibus estimado (píldora `tinta` con borde y
  número `etiquetaCartel`, o un aro `etiquetaCartel`), las notas (`tenue`) y
  todo el mapa base.

### Excepciones documentadas

1. **Novedades sin leer.** La fecha de una novedad sin leer va en Doto
   ámbar sobre un recuadro de LEDs (`_DateTile`, `TimbreText.cartel(24)`),
   y arriba del título va «NUEVA» en ámbar (12 px, 700). No son datos en
   vivo: cuentan lo que todavía no leíste, como la insignia de la pestaña,
   y se tratan como contadores. Al leerlas, la fecha pasa a Fira Sans Extra
   Condensed en `etiquetaCartel` y «NUEVA» desaparece. Código:
   `lib/ui/news_list.dart`.
2. **El brillo de `LiveDot`.** El punto de los minutos en vivo lleva su
   propio halo (`BoxShadow` del mismo color al 60 %), además de
   `TimbreShadow.ledGlow`, que es solo de LLEGANDO. Es luz sobre un dato
   en vivo ([06-luz-y-movimiento.md](06-luz-y-movimiento.md)).
3. **La línea en los widgets de parada.** Un widget solo muestra
   estimaciones, pero el número de línea va en ámbar: contorno
   `ambarTenue` de 1.5 dp, nunca relleno (el relleno ámbar es GPS en la
   app), y cifras `ambar`. Es la identidad de la línea, como el cartel de
   la parada; la hora, que es el dato, queda en `papel` con «~» y reloj.
   Código: `android/app/src/main/res/drawable/widget_badge_lit_bg.xml`.

El porqué de las tres está en [12-decisiones.md](12-decisiones.md).

### Donde el código todavía no cumple

- El logotipo de Info escribe « MVD» en `ambar` con Fira Sans Extra
  Condensed (`lib/ui/info_page.dart`), mientras el cartel TIMBRE MVD usa
  Doto y `ambarTenue`.
- Los íconos de los enlaces de Info (`_LinkRow`: política, código fuente,
  contacto) son `ambar`, aunque son marcas pasivas.

## Errores y avisos

Un error dentro de una tarjeta, de un campo o de una pantalla es un LED
rojo. Un aviso sobre una lista es el panel `avisoNoche`.

| Caso | Cómo se ve | Código |
|---|---|---|
| La tarjeta no se pudo actualizar, o la parada ya no existe | Ícono `warning` y texto `TimbreText.subtitle` en `rojoLed` | `_BoardNote` en `lib/ui/stops_page.dart` |
| No se pudo cargar el horario | Ícono `warning` de 24 en `rojoLed`; texto `papel` (`TimbreText.body`, 600) | `lib/ui/schedule_page.dart` |
| Error de un campo en un diálogo | Texto de 13 px en `rojoLed` | Diálogos de `lib/ui/stops_page.dart` |
| Snackbar de error | Fondo `tintaAlta`, ícono `warning` de 20 en `rojoLed`, texto `papel` | `_showError` en `lib/ui/stops_page.dart` |
| Deslizar para borrar | Fondo `rojoLed` con radio 16, papelera `noche` | `_deleteBackground` en `lib/ui/stops_page.dart` |
| GPS parcial de una empresa (menos del 70 % de sus ómnibus) | Panel `avisoNoche`, borde `ambarTenue` de 1 px, radio 12, ícono `signal` en `ambar`, texto `papel` 13 px | `_buildGpsWarning` en `lib/ui/stops_page.dart` |
| Novedades no se pudo actualizar | Panel `avisoNoche`, borde `ambarTenue`, radio 12, ícono `warning` en `ambar`, texto `ambar` (`TimbreText.subtitle`, 600) | `_FailedBanner` en `lib/ui/news_list.dart` |
| El Mapa no se pudo actualizar | Lo mismo que Novedades, con «Reintentar», sobre el mapa | `_FailedBanner` en `lib/ui/map/mapa_page.dart` |
| No se pudo abrir el mapa base | Ícono `warning` de 24 en `rojoLed`; texto `papel` (`TimbreText.body`, 600) | `_BasemapFailed` en `lib/ui/map/mapa_page.dart` |
| La hoja de una parada del Mapa no se pudo actualizar | Ícono `warning` y texto `TimbreText.subtitle` en `rojoLed` | `_SheetNote` en `lib/ui/map/map_sheets.dart` |

Los textos de cada caso están en [07-textos.md](07-textos.md).

## Lo que no es token

Algunas transparencias del ámbar y de `noche` se escriben como literales
junto al widget que las usa:

| Valor | Dónde |
|---|---|
| `ambar` al 11 % | `LedMatrix` de los recuadros: mosaicos de Servicios, lista vacía, fecha sin leer, «NO OFICIAL» en Info |
| `ambar` al 9 % | `LedMatrix` de la pantalla de bloqueo |
| `ambar` al 32 % | Selección de texto (`textSelectionTheme`) |
| `noche` al 70 % | `scrim` del tema |
| `ambar` al 16 %, 45 %, 50 % | Puntos apagados, halo y haz del candado `LedLock` |
| `ambarClaro` al 70 % | Línea de barrido de `LedLock` |
| Color del punto al 60 % | Halo de `LiveDot` |
| Color del ícono al 55 % | Brillo de `PixelIcon(glow: true)` |

El único literal de color completo es `Color(0xFF000000)` en
`lib/ui/widgets/led_matrix.dart`: debajo de un shader, el alfa de la
pintura se multiplica con el del degradé, así que tiene que ser opaca.

El Mapa no agrega transparencias: sus paradas, ómnibus, notas y la
atribución usan los tokens opacos.

### El mapa base

El mapa base se pinta con el estilo «Timbre Noche»
(`assets/map/style_noche.json`, generado desde `tool/map/flavor_noche.json`),
no con widgets, así que la regla de los literales no cambia. Usa los valores
de seis tokens (`noche`, `tinta`, `tintaAlta`, `lineaNoche`,
`etiquetaCartel`, `tenue`) y seis tonos que existen solo en el mapa:

| Nombre | Valor | Para qué |
|---|---|---|
| agua | `#0C1F47` | El agua: un poco más clara y más azul que `noche`, para que se lea la costa |
| autopista | `#2C4880` | Autopistas y rutas, un escalón más claro que `lineaNoche` |
| verde | `#091726` | Parques, bosques y matorrales: `noche` apenas corrido hacia el verde |
| zona | `#09132A` | Hospitales, industrias, escuelas, zonas peatonales, aeródromos: `noche` apenas más claro |
| arena | `#10172A` | Arena y playas, sin amarillo |
| edificio | `#030814` | Los edificios (al 50 % en el estilo), más oscuros que `noche` |

El mapa base no usa `ambar`, `ambarTenue`, `ambarClaro`, `avisoNoche`,
`rojoLed` ni `papel`: el ámbar queda para los ómnibus con GPS que van encima.
`test/map/basemap_assets_test.dart` comprueba que el estilo no tenga otros
colores. La tabla completa, con qué capa usa cada valor y los contrastes,
está en [assets/map/README.md](../../assets/map/README.md).
