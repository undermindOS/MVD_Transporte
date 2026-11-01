# Formas y espacio

Radios, espacios, tamaño táctil y bordes. Los tokens están en
`lib/ui/theme/timbre_tokens.dart` (`TimbreRadii`, `TimbreSpace`) y en
[tokens.json](tokens.json). Muchas medidas de los widgets se escriben como
número junto al widget; las que importan están en esta página.

## Radios: `TimbreRadii`

| Token | Valor | Dónde |
|---|---|---|
| `chip` | 6 | Tooltip (`tooltipTheme`). Los chips no lo usan: son píldoras. |
| `badge` | 8 | `LineBadge` y `LlegandoChip`. |
| `control` | 12 | Campos de texto (los tres bordes de `inputDecorationTheme`), paneles de aviso (GPS parcial, Novedades sin actualizar), recuadro «NO OFICIAL» de Info. |
| `button` | 14 | `FilledButton` y `OutlinedButton` desde el tema; la pista de `TimbreSegmented`; `CartelTira`; nota del navegador en Servicios. |
| `card` | 16 | Tarjetas (`cardTheme`: paradas, rutas, Info), fondo de deslizar para borrar, mosaicos de Servicios, cartel de `TimbreEmptyState`, `CartelParada`. |
| `sheet` | 24 | Esquinas de arriba de las hojas (`bottomSheetTheme`) y diálogos (`dialogTheme`). |

### Radios que no son token

| Radio | Dónde |
|---|---|
| 11 | Segmento elegido de `TimbreSegmented` (`lib/ui/widgets/segmented.dart`), dentro de la pista de 14 con 4 de margen. |
| 7 | `LineBadge(compact: true)`, la insignia de Horarios. |
| 10 | Recuadro de la fecha de una novedad (`_DateTile` en `lib/ui/news_list.dart`). |
| 15 | Marco del ícono de la app en Info. |
| 0.41 × tamaño de letra | `CartelCompacto`: unos 9 con la letra de 22. |
| 232 / 1024 del lado | Ícono de la app (`TimbreAppIcon`, `TimbreBusPainter`), igual que el ícono del lanzador ([10-superficies.md](10-superficies.md)). |
| Píldora | Chips (`chipTheme`, radio 999), botón «Desde» de Horarios y «Desbloquear» (`StadiumBorder`). También, por defecto de Material 3: `TextButton`, botones de ícono e indicador de la barra de navegación. |
| 16 | Botón + (`FloatingActionButton`): el tema no le da forma y Material 3 usa 16, igual que `card`. |
| 4 | Snackbar: el radio por defecto de Material 3. |
| 0 | Los píxeles de los íconos, el punto de `LiveDot` y los puntos de `LedLock` son cuadrados. Los LEDs apagados de `LedMatrix`, en cambio, son redondos. |

## Espacios: `TimbreSpace`

| Token | Valor | Dónde |
|---|---|---|
| `xs` | 4 | Entre filas de chips; entre un rótulo («LÍNEAS», «DÍAS») y lo que nombra; margen de abajo del panel de Novedades. |
| `s` | 8 | Entre chips; entre la campana de un aviso y su texto; antes del error de los ajustes del aviso. |
| `m` | 12 | Entre bloques de un diálogo (Agregar ruta); entre «Desde» y «Hasta» de los ajustes del aviso; margen de arriba del panel de Novedades. |
| `l` | 16 | Margen lateral de la pantalla: tarjetas, paneles de aviso, fondo de deslizar para borrar, Info; `titleSpacing` de la app bar; antes de «Guardar» en los ajustes del aviso. |
| `xl` | 24 | Margen lateral del error de Horarios. |
| `touch` | 44 | Tamaño táctil mínimo: ver abajo. |

Medidas que se repiten sin token:

| Medida | Dónde |
|---|---|
| 16 | Margen lateral de Servicios, de `PageTitleBar`, de las filas de Novedades y de los controles de Horarios. Es el mismo valor que `l`, escrito como número. |
| 6 | Margen de arriba y de abajo de cada tarjeta y panel de aviso: 12 entre dos tarjetas. |
| 14 | Margen interno de la tarjeta (encabezado `14, 10, 4, 8`; el 4 a la derecha es porque los botones de ícono ya traen su área de 44), de las filas `ArrivalRow` (14 × 6), de las notas (`_BoardNote`) y sangría de los divisores entre filas. |
| 20 | Margen lateral de las hojas: Estoy esperando, ajustes del aviso, detalle de una novedad. |
| 24 y 32 | Margen de `TimbreEmptyState` (24 a los lados, 32 arriba y abajo). |
| 96 | Espacio al final de las listas de Paradas y Rutas, para que el botón + no tape la última tarjeta. |
| 4 | Margen interno de la pista de `TimbreSegmented` y espacio entre segmentos. |
| 12 y 18 | Mosaicos de Servicios: 12 entre columnas, 18 entre filas. Tres por fila; en una tableta no pasan de 168 de lado. |

Los textos con interlineado propio también hacen espacio: notas a 1.4,
párrafos de Info a 1.45, texto de una novedad a 1.5
([03-tipografia.md](03-tipografia.md)).

## Tamaño táctil

Todo lo que se toca mide por lo menos `TimbreSpace.touch` = 44 × 44. Las
filas tienen alto mínimo, no alto fijo: con letra grande crecen.

| Alto | Qué |
|---|---|
| 44 | `TextButton` y botones de ícono (44 × 44 desde el tema); segmentos de `TimbreSegmented`; fila «Aviso N min antes»; filas de Horarios; botón «Desde» de Horarios; íconos de los campos (`_FieldIcon`, 44 × 44). |
| 48 | `OutlinedButton` desde el tema. El tema también da 48 a `ElevatedButton` y `SegmentedButton`, que la app no usa. |
| 52 | Botón principal (`FilledButton`), fila de ómnibus (`ArrivalRow`), filas de enlaces de Info (`_LinkRow`). |
| 56 | «Desbloquear» (220 × 56). |
| 72 | Barra de navegación (`navigationBarTheme.height`); subpestañas con ícono y texto (el alto de Flutter para ese caso). |

Material agranda a 48 × 48 el área que responde al toque de chips,
switches y botones de ícono aunque se vean más chicos: en teléfonos,
`materialTapTargetSize` es `padded` por defecto y el tema no lo cambia.

## Bordes

| Borde | Dónde |
|---|---|
| 1 px `lineaNoche` | Tarjetas, hojas y diálogos; borde de abajo de la app bar; pista de los segmentos; `CartelTira`; cartel de `TimbreEmptyState`; recuadro «NO OFICIAL» y marco del ícono en Info; nota del navegador; filas de Horarios y de Novedades; divisores (`dividerTheme`); campos sin foco; switch apagado. |
| 1.5 px | Borde `ambarTenue` de `OutlinedButton` y del botón «Desde»; contorno `etiquetaCartel` de `LineBadge` sin GPS; recuadro `lineaNoche` de la fecha de una novedad. |
| 2 px `ambar` | Campo con foco. |
| 1 px `ambarTenue` | Paneles de aviso (`avisoNoche`). |
| Sin borde | `CartelCompacto`, barra de navegación, mosaicos de Servicios, `LlegandoChip`, chips (`side: BorderSide.none`), snackbar, pantalla de bloqueo. |

Los bordes `lineaNoche` son decoración (1.52 a 1.69:1): un campo se
reconoce por su rótulo, su ícono y el borde ámbar con foco
([02-color.md](02-color.md#contrastes)).

## Sin sombras

El tema pone elevación 0 en la app bar, la barra de navegación, las
tarjetas, el snackbar, el botón + y `ElevatedButton`, y
`surfaceTintColor` transparente en tarjetas, hojas, diálogos y navegación.
El color de sombra del esquema es `noche`, el mismo del fondo, así que
ningún panel proyecta una sombra visible. Lo que se levanta del panel
cambia de color (`tintaAlta`), no de altura.

La única sombra es luz: el brillo de LLEGANDO y de `LiveDot`
([06-luz-y-movimiento.md](06-luz-y-movimiento.md)).

## La tarjeta de parada

Una parada guardada es un tablero chico (`_buildStopCard` y `_Board` en
`lib/ui/stops_page.dart`):

1. **Panel.** `Card` del tema: `tinta`, radio 16, borde de 1 px
   `lineaNoche`, con 16 a los lados y 6 arriba y abajo.
2. **Encabezado** (`14, 10, 4, 8`). A la izquierda, el nombre
   (`TimbreText.stopName`) y debajo el número «#N» (13 px,
   `etiquetaCartel`). A la derecha, el reloj (abre Horarios) y la campana
   del aviso, los dos botones de ícono de 44.
3. **Fila del aviso**, solo si el aviso está activado: «Aviso N min antes ·
   días y horas», de 44 de alto como mínimo. Abre los ajustes.
4. Divisor de lado a lado.
5. **Filas `ArrivalRow`**, de 52 de alto como mínimo, separadas por
   divisores con 14 de sangría. Se ven 3; si hay más (hasta 6), «Ver las N»
   las muestra todas y «Ver menos» las vuelve a plegar. Si no hay filas, una
   nota (`_BoardNote`): cargando, sin ómnibus o un error
   ([08-componentes.md](08-componentes.md)).
6. Divisor y «Ver en Cómo Ir» (`TextButton`), alineado a la derecha.

Se borra deslizando hacia la izquierda: detrás aparece el fondo `rojoLed`
con radio 16 y la papelera. El lector de pantalla tiene la acción «Borrar»
en el encabezado.

La tarjeta de una ruta es igual, sin el reloj y sin «Ver en Cómo Ir». Su
encabezado tiene el origen (ícono `stop` de 14 y el nombre a 13 px en
`etiquetaCartel`), «→ destino» en `TimbreText.stopName` y, si se eligieron,
«Líneas: … · Hacia: …» en `TimbreText.caption` `tenue`.
