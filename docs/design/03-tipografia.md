# Tipografía

Tres familias, todas dentro de la app: no se descarga ninguna fuente en
tiempo de ejecución. Los archivos están en `assets/fonts/` (subconjunto
latino, licencia SIL OFL 1.1) y se declaran en `pubspec.yaml`. Sus
licencias viajan dentro de la app y se registran en el `LicenseRegistry`
de Flutter (`_registerFontLicenses` en `lib/main.dart`), aunque hoy ninguna
pantalla abre la página de licencias (`showLicensePage`).

Los nombres de familia están en `TimbreFonts` y los estilos en
`TimbreText`, los dos en `lib/ui/theme/timbre_text.dart`. Los valores de
esta página están también en [tokens.json](tokens.json), y
`test/design_tokens_test.dart` comprueba que coincidan con el código.

## Las familias

| Familia | `TimbreFonts` | Pesos incluidos | Para qué |
|---|---|---|---|
| Doto | `doto` = `'Doto'` | 900 (Black) | La matriz de puntos de los carteles: título de página, carteles, minutos con GPS, LLEGANDO. |
| Fira Sans Extra Condensed | `firaCondensed` = `'FiraSansExtraCondensed'` | 600, 700, 800 | Los datos: número de línea, destino, nombre de parada, hora de horario, «min»; las direcciones de la política en Privacidad (600). |
| Fira Sans | `fira` = `'FiraSans'` | 400, 500, 600, 700 | Todo lo que se lee: interfaz, botones, rótulos, novedades, Info. Es la familia por defecto del tema (`fontFamily` en `buildTimbreTheme()`). |

Solo existen esos pesos. Si pedís otro (por ejemplo Doto a 700 o Fira Sans
Extra Condensed a 400), Flutter usa el archivo de peso más cercano, que no
es la letra que pediste.

La excepción son las etiquetas del mapa base del Mapa (calles, barrios,
ciudades): las dibuja `flutter_map_vector_tiles` con el motor de texto de
Flutter y la fuente del sistema (Roboto en Android, SF en iOS), no con Fira.
Del `text-font` del estilo solo toma el peso y la cursiva, y con la app no
viaja ninguna fuente de mapa ([assets/map/README.md](../../assets/map/README.md)).
Lo que la app escribe encima del mapa (la atribución, las notas, las
píldoras de los ómnibus) sí va en Fira.

## Los estilos de `TimbreText`

Tamaño en píxeles lógicos, peso e interlineado (`height`). «Sin color»
quiere decir que el color lo pone el widget o el tema.

### Carteles: Doto

| Estilo | Tamaño / peso / interlineado | Color | Dónde se usa |
|---|---|---|---|
| `pageTitle` | 28 / 900 / 1.1, espaciado 1 | `ambar` | Título de página en `PageTitleBar`, en mayúsculas: «MIS PARADAS», «SERVICIOS», «INFO», «HORARIOS», «PRIVACIDAD». |
| `liveMinutes([size = 30])` | 30 / 900 / 1 | `ambar` | Cifras de `MinutosEnVivo`. `ArrivalRow` lo pide a 26. Un tamaño menor que 19 se sube a 19. |
| `cartel(size, {color = ambar})` | el que se pida / 900 / 1 | `ambar`, o el que se pase | Los carteles: ver la tabla de abajo. Un tamaño menor que 19 se sube a 19. |

Tamaños de `cartel` en el código:

| Tamaño | Dónde | Espaciado |
|---|---|---|
| 19 | «min» de `CartelTira` | 0 |
| 20 | LLEGANDO de `LlegandoChip` (en `tinta` sobre ámbar), cartel de `TimbreEmptyState` («SIN PARADAS», «SIN RUTAS», «SIN PASADAS», «SIN NOVEDADES»; interlineado 1.15) | 1 |
| 22 | TIMBRE MVD de `CartelCompacto` | 1 |
| 22 | «NO OFICIAL» de Info | 1.5 |
| 22 | Destino y LLEGANDO de `CartelTira` | 0 |
| 24 | Día de una novedad sin leer (`_DateTile` en `lib/ui/news_list.dart`) | 0 |
| 26 | Línea de `CartelTira` | 0 |
| 30 | «BLOQUEADA» de la pantalla de bloqueo | 2 |
| 34 | Minutos de `CartelTira` | 0 |
| 24, 26, 30, 44, 72 | `CartelParada`, que hoy no se usa en ninguna pantalla | 0 o 1 |

`CartelCompacto` no llama directamente a `cartel` con un número fijo:
recibe `fontSize` (22 por defecto) y también lo sube a 19 si es menor.

### Datos: Fira Sans Extra Condensed

| Estilo | Tamaño / peso / interlineado | Color | Dónde se usa |
|---|---|---|---|
| `stopName` | 20 / 700 / 1.1 | `papel` | Nombre de la parada en su tarjeta, destino de una ruta («→ Centro»), parada elegida en Agregar ruta, título de la hoja de ajustes del aviso. |
| `lineBadge` | 19 / 800 / 1.2 | sin color | Número de `LineBadge`: `tinta` sobre ámbar con GPS, `etiquetaCartel` en contorno sin GPS. La insignia compacta de Horarios lo usa a 17. |
| `destination` | 18 / 700 / 1.05 | `papel` | Destino del ómnibus: a 17 en `ArrivalRow` y en las filas de Horarios (hasta 2 líneas), a 20 en la hoja Estoy esperando de un viaje sin GPS. A 18, tal cual, no se usa. |
| `minuteUnit` | 14 / 700 / 1 | `ambarTenue` | «min» después de los minutos en vivo (`MinutosEnVivo`). |
| `scheduleTime` | 22 / 600 / 1, cifras tabulares | `etiquetaCartel` | Hora de horario: a 22 en Horarios, a 20 en las filas sin GPS y en las estimadas de `ArrivalRow` («20:17», «~20:17»). Nunca en Doto. |

### Lectura: Fira Sans

| Estilo | Tamaño / peso / interlineado | Color | Dónde se usa |
|---|---|---|---|
| `dialogTitle` | 20 / 700 / 1.2 | `papel` | Título de los diálogos (`dialogTheme.titleTextStyle`), de la hoja de una novedad y de la política en Privacidad (estos dos, con interlineado 1.25). |
| `buttonLarge` | 17 / 700 / 1.2 | sin color | Botón principal, `FilledButton` desde el tema: «Avisarme cuando llegue», «Guardar», «Ver más». «Desbloquear» reemplaza el estilo por uno propio de 18 / 700 (ver abajo). |
| `body` | 15 / 400 / 1.2 | `papel` | Texto de diálogos y snackbars (desde el tema); texto completo de una novedad (1.5); títulos de los enlaces de Info (500); «Avisarme cuando falten» (600); error de Horarios (600); texto de la pantalla de bloqueo (1.4, en `etiquetaCartel`). |
| `button` | 15 / 700 / 1.2 | sin color | `OutlinedButton` y `TextButton` desde el tema; segmentos de `TimbreSegmented` (700 el elegido, 600 los otros); botón «Desde» de Horarios (600). |
| `subtitle` | 14 / 400 / 1.2 | `etiquetaCartel` | Subtítulo de `PageTitleBar` («Sitios oficiales, en tu navegador»); notas dentro de una tarjeta (`_BoardNote`, con su color); línea bajo el cartel de la hoja Estoy esperando; resumen de una novedad y detalle de `TimbreEmptyState` (1.4); párrafos de Info y de Privacidad y nota del navegador en Servicios (1.45, en `papel`); panel de Novedades sin actualizar (600, en `ambar`). |
| `tabLabel` | 13 / 700 / 1.2 | sin color | Subpestaña elegida (`tabBarTheme.labelStyle`), en `ambar`. Las otras usan un estilo propio del tema: 13 / 500 en `tenue`. |
| `caption` | 12.5 / 400 / 1.2 | `etiquetaCartel` | Línea bajo una parada en las listas («#5109 · 48 m · 124, 125»); «Líneas: … · Hacia: …» de una ruta (en `tenue`); notas de la hoja Estoy esperando y de los ajustes del aviso (1.4). |
| `navLabel` | 12 / 700 / 1.2 | sin color | Barra de navegación (`navigationBarTheme`): la elegida a 700 en `ambar`, las otras a 500 en `tenue`. |
| `sectionLabel` | 12 / 700, espaciado 1.44 | `etiquetaCartel` | Rótulo en mayúsculas: «FUENTE DE DATOS» en Info, las secciones de Privacidad («RESUMEN»), «LÍNEAS» y «HACIA» en Agregar ruta, «DÍAS» en los ajustes del aviso. No define interlineado. |
| `cartelLabel` | 12 / 700, espaciado 1.44 | `etiquetaCartel` | «PRÓXIMO» de `CartelParada` (y «Actualizado HH:MM», a 500 sin espaciado). Mismos valores que `sectionLabel`; hoy no se ve en ninguna pantalla. |

## Doto: nunca por debajo de 19 px

`TimbreFonts.dotoMinSize` = 19: 13 px de altura de letra, lo más chico en
que los puntos todavía se leen como letras. Por eso:

- `TimbreText.liveMinutes` y `TimbreText.cartel` suben a 19 cualquier
  tamaño menor, y `CartelCompacto` hace lo mismo con su `fontSize`.
- Lo que no entra a 19 px no va en Doto: se escribe en Fira. Ningún
  horario ni estimación usa Doto, a ningún tamaño.

El tamaño del estilo no alcanza: si el sistema usa una letra más chica que
la normal, Flutter achica también el Doto. Los carteles chicos llevan
`MediaQuery.withClampedTextScaling(minScaleFactor: 1)`, que no deja bajar
la escala de 1:

| Dónde | Doto | Límite |
|---|---|---|
| `CartelCompacto` (`lib/ui/widgets/cartel.dart`) | 22 | entre 1 y 1.3: el cartel TIMBRE MVD tampoco crece más de 1.3× |
| `LlegandoChip` | 20 | desde 1 |
| `CartelTira`, entero | 19 a 34 | desde 1 |
| Cartel de `TimbreEmptyState` (`lib/ui/widgets/empty_state.dart`) | 20 | desde 1 |
| «NO OFICIAL» en `lib/ui/info_page.dart` | 22 | desde 1 |

Los demás Doto no tienen límite porque ni a la escala más chica del sistema
(0.85 en Android, alrededor de 0.82 en iOS) bajan de 19: el título de
página (28 da unos 23), «BLOQUEADA» (30), los minutos de `ArrivalRow` (26
da unos 21) y el día de una novedad sin leer (24 da unos 19.7).

Algunos Doto están dentro de un `FittedBox` que los achica si no entran:
el título de página, la hora de `ArrivalRow` y de `CartelTira` cuando
bajan a su propia línea, y el día de una novedad. Eso pasa solo con letra
grande, cuando el texto ya mide mucho más de 19 px.

## Letra grande

La letra del sistema puede crecer hasta 2× (Android 14 en adelante, y los
tamaños de accesibilidad de iOS) y nada se corta.

`TimbreText.largeFrom` = 1.5. `TimbreText.isLarge(context)` es verdadero
cuando `MediaQuery.textScalerOf(context).scale(17)` llega a 17 × 1.5. Desde
ahí:

- `ArrivalRow` baja la hora a su propia línea, debajo del destino y
  alineada al final.
- `CartelTira` pone el destino en su propia línea, debajo de la línea y
  los minutos, con hasta 3 líneas. Debajo de 1.5× hace lo mismo cuando el
  destino no entra en dos líneas al lado de los minutos sin partir una
  palabra (`_fitsInRow`).
- Las subpestañas de Mis paradas (Paradas, Rutas, Novedades) se
  desplazan de costado (`isScrollable` en `lib/ui/stops_page.dart`).

A cualquier escala:

- La app bar crece con la letra: `PageTitleBar.preferredSize` se calcula
  con el `textScaler` de la página.
- El título de página nunca termina en «…»: si no entra, se achica al
  ancho (`FittedBox`).
- El subtítulo de la app bar ocupa hasta 4 líneas
  (`PageTitleBar.subtitleMaxLines`): un nombre de parada del catálogo
  puede necesitar tres a 2×. En Horarios el número de parada
  (`subtitleTrailing`) nunca se corta.
- El destino ocupa hasta 2 líneas en `ArrivalRow` y en Horarios.
- Los textos de los segmentos, la insignia de línea y la hora de Horarios
  se achican dentro de su lugar en vez de perder letras.

Las pruebas de layout corren con las fuentes reales a 1×, 1.3× y 2×
([11-accesibilidad.md](11-accesibilidad.md)).

## Mayúsculas y cifras

- Los carteles van en mayúsculas en pantalla y en palabras normales para
  el lector de pantalla. `PageTitleBar` escribe `title.toUpperCase()` y le
  da al lector el título tal cual; `TimbreEmptyState` muestra `sign` y lee
  `message`.
- Los nombres de paradas y destinos van como los manda la fuente
  («SAN JOSE y ANDES»); el lector los oye con `spokenName`
  ([07-textos.md](07-textos.md)).
- Solo `scheduleTime` usa cifras tabulares (`FontFeature.tabularFigures()`):
  las horas de Horarios quedan alineadas en columna.

## Tamaños fuera de la escala

Estos textos tienen un `TextStyle` propio en vez de un estilo de
`TimbreText`. Se dejaron así para no cambiar cómo se ven; si se toca uno,
lo mejor es llevarlo a un estilo existente o agregar uno nuevo a
`TimbreText`.

| Tamaño | Dónde |
|---|---|
| 12 | «NUEVA» (700, espaciado 0.72, `ambar`) y mes de la fecha (700, espaciado 0.96) en `lib/ui/news_list.dart`; nota «Publicadas por la Intendencia de Montevideo (Cómo Ir).» (`tenue`). |
| 13 | Número de parada en la tarjeta y origen de una ruta; texto del panel de GPS parcial (interlineado 1.4); fila «Aviso N min antes» (700); notas y errores de los diálogos; «Horarios teóricos, sin ubicación GPS» y «Después de medianoche» (600) en Horarios; textos chicos de Info y de los mosaicos de Servicios; fecha en el detalle de una novedad; rótulos de confort de `CartelParada`; «#574» en la hoja de una parada del Mapa. Del tema: etiqueta de los chips (500), tooltip, subpestañas sin elegir (500). |
| 15 | Número de línea en las píldoras de los ómnibus del Mapa (`TimbreText.lineBadge` a 15, Fira Sans Extra Condensed 800), pintado en el atlas de `BusLayer`. |
| 16 | «Bloqueo biométrico» (600) en Info; título de los mosaicos de Servicios (700); títulos dentro del texto de una novedad (`lib/ui/safe_html.dart`, 700). El tema define 16 / 700 para `ElevatedButton` y `SegmentedButton`, que la app no usa. |
| 17 | Título de una novedad (600 leída, 700 sin leer, interlineado 1.25); subtítulo de Horarios con la parada (`_stopLine`: Fira Sans Extra Condensed 700, `etiquetaCartel`). |
| 18 | Títulos de sección de Servicios (700); texto de «Desbloquear» (700). |
| 19 | `appBarTheme.titleTextStyle` (700). No se ve: el título de la app bar es `CartelCompacto`. |
| 20 | Encabezado de hora de Horarios, «20 h» (Fira Sans Extra Condensed 800, `etiquetaCartel`). |
| 26 | Día de una novedad leída (Fira Sans Extra Condensed 800, `etiquetaCartel`). |
| 34 | Logotipo «Timbre MVD» de Info (Fira Sans Extra Condensed 800, « MVD» a 700 en `ambar`). El cartel TIMBRE MVD usa Doto y `ambarTenue`: ver [02-color.md](02-color.md#donde-el-código-todavía-no-cumple). |

## Cómo agregar un estilo

1. Agregalo a `TimbreText` con un comentario que diga dónde se usa.
   Usá una familia y un peso de la tabla de arriba.
2. Si es Doto, que nunca baje de 19 y que tenga
   `withClampedTextScaling(minScaleFactor: 1)` si 0.82 × su tamaño queda
   debajo de 19.
3. Sumalo a `tokens.json` (grupo `text`) y al mapa `_styles` de
   `test/design_tokens_test.dart`.
4. Anotalo en esta página. El resto del proceso está en el
   [README](README.md#cómo-proponer-un-cambio).
