# Íconos

Un solo juego de íconos: `PixelGlyphs`, 33 glifos de 12 × 12 en
`lib/ui/widgets/pixel_glyphs.dart`, dibujados por `PixelIcon`
(`lib/ui/widgets/pixel_icon.dart`). La app no usa los íconos de Material
(`Icons.`), ni emoji, ni íconos de línea de otros juegos.

## Cómo se dibuja un glifo

- Un `PixelGlyph` son 12 cadenas de 12 caracteres: `#` es un píxel
  encendido, `.` uno apagado.
- `PixelIcon` divide el lado en 12 celdas (`p = tamaño / 12`) y pinta cada
  píxel encendido como un cuadrado de lado `p − 0.14 p`. Ese espacio de
  0.14 celdas entre píxeles es el mismo que separa los puntos de Doto, así
  que íconos y letras se leen como un mismo tablero.
- Los píxeles son cuadrados: nada de esquinas redondeadas ni trazos.
- Parámetros: `size` (si falta, el de `IconTheme`, o 24), `color` (si
  falta, el de `IconTheme`, o `ambar`), `glow` y `semanticLabel`. Sin
  `semanticLabel` el ícono es decoración y el lector de pantalla no lo ve
  (`ExcludeSemantics`); con él, se lee como imagen.

## Tamaños: `TimbreIconSize`

| Token | Valor | Dónde |
|---|---|---|
| `mark` | 14 | Marcas dentro de una fila: confort, campana del ómnibus que esperás, campana y flecha de la fila «Aviso N min antes», origen de una ruta, enlace externo en el rincón de los mosaicos de Servicios. `ArrivalRow` escribe el 14 como número, no con el token. |
| `row` | 20 | Botones con ícono, notas de una tarjeta, paneles de aviso, snackbar de error, íconos de los campos de texto, enlaces de Info. |
| `rowLarge` | 24 | Botón +, candado de Info, error de Horarios. 24 es también el tamaño del `iconTheme` del tema, de la app bar y de la barra de navegación, y el de los botones de ícono (campana de aviso, reloj de Horarios en la tarjeta). |
| `tile` | 48 | Íconos de los mosaicos de Servicios. |

Hay un tamaño sin token: 22, en las subpestañas (Paradas, Rutas,
Novedades), en las paradas de las listas de Agregar parada y en la nota
del navegador de Servicios.

## Color

El color sale del contexto: casi siempre `PixelIcon` lo toma del
`IconTheme` que pone el botón, la barra o la lista.

| Color | Para qué | Ejemplos |
|---|---|---|
| `ambar` | Lo encendido y lo que actúa | Pestaña y subpestaña elegidas, íconos de `OutlinedButton` y `TextButton`, campana de un aviso activado, campana del ómnibus que esperás, mosaicos de Servicios, ícono de los paneles de aviso. |
| `tinta` | Sobre un relleno ámbar | Íconos del botón principal («Avisarme cuando llegue», «Ver más», «Desbloquear») y del botón +. |
| `papel` | Botones de la app bar y botones de ícono | Info, la flecha de atrás, «Ver líneas» en Agregar ruta. |
| `etiquetaCartel` | Marcas pasivas | Confort, origen de una ruta, íconos de los campos, paradas en las listas (`listTileTheme.iconColor`), candado de Info, reloj de Horarios en la tarjeta, flecha de la fila de aviso, nota del navegador. |
| `tenue` | Lo apagado | Pestañas sin elegir, campana sin aviso, reloj de una fila sin GPS o estimada, «Sin ómnibus próximos». |
| `ambarTenue` | Luz atenuada | Enlace externo en el rincón de los mosaicos de Servicios. |
| `rojoLed` | Errores | Notas de error de una tarjeta, snackbar de error, error de Horarios. |
| `noche` | Sobre `rojoLed` | Papelera de deslizar para borrar. |

Pendiente: los íconos de los enlaces de Info (`_LinkRow` en
`lib/ui/info_page.dart`) son `ambar`, aunque son marcas pasivas
([02-color.md](02-color.md#donde-el-código-todavía-no-cumple)).

## Brillo: `glow`

`PixelIcon(glow: true)` pinta debajo de los píxeles una copia de su color
al 55 %, desenfocada `1.1 × p`. Es la luz de un LED encendido y solo la
tiene lo que está «prendido»:

- el ícono de la pestaña elegida en la barra de navegación (`selectedIcon`
  en `lib/ui/home_page.dart`);
- la campana de un aviso activado (`_AlertButton` en
  `lib/ui/stops_page.dart`);
- los íconos de los mosaicos de Servicios (`lib/ui/services_page.dart`).

El resto de la luz del sistema está en
[06-luz-y-movimiento.md](06-luz-y-movimiento.md).

## Los 33 glifos

14 se dibujaron para Timbre. Los otros 19 son de pixelarticons (Gerrit
Halfmann, licencia MIT), pasados a la grilla de 12 × 12; en el código
llevan `(pixelarticons)` en su comentario. La licencia está en
`assets/licenses/MIT-pixelarticons.txt` y se registra junto con las de las
fuentes (`_registerFontLicenses` en `lib/main.dart`); hoy ninguna pantalla
abre la página de licencias.

Tamaño y color de cada uso, en ese orden.

| Glifo | Origen | Qué es | Dónde se usa |
|---|---|---|---|
| `bus` | Timbre | Frente de un ómnibus | Pestaña Mis paradas de la navegación (24); campo «Número de parada» de Agregar parada (20, `etiquetaCartel`); nota «Sin ómnibus próximos» de la tarjeta (20, `tenue`). |
| `info` | Timbre | Info | Botón Info de la app bar (24, `papel`). |
| `stop` | Timbre | Una parada: el cartel con un ómnibus arriba del poste | Subpestaña Paradas (22); origen en la tarjeta de una ruta (14, `etiquetaCartel`); paradas cercanas y resultados por calles en Agregar parada (22, `etiquetaCartel`); campo «Parada de origen» de Agregar ruta (20, `etiquetaCartel`). |
| `clock` | Timbre | Horario | Botón Horarios de la tarjeta (24, `etiquetaCartel`); botón «Desde» de Horarios (20, `ambar`); hora de una fila sin GPS o estimada en `ArrivalRow` (14, `tenue`). |
| `bell` | Timbre | Aviso apagado | Campana de una parada o ruta sin aviso (`_AlertButton`, 24, `tenue`); «Dejar de esperar» en la hoja Estoy esperando (20, `ambar`); mosaico Avisos de Servicios (48, `ambar`, brillo). |
| `bellRing` | Timbre | Aviso encendido, Estoy esperando | Campana de un aviso activado (`_AlertButton`, 24, `ambar`, brillo); fila «Aviso N min antes» (14, `ambar`); «Avisarme cuando llegue» (20, `tinta`); marca del ómnibus que esperás en `ArrivalRow` (14, `ambar`, se lee «Esperando»). |
| `plus` | Timbre | Agregar | Botón + de Paradas y Rutas (24, `tinta`). |
| `trash` | Timbre | Borrar | Fondo de deslizar para borrar (24, `noche` sobre `rojoLed`, se lee «Eliminar»). |
| `warning` | Timbre | Error o aviso | Snackbar de error y notas de error de la tarjeta (20, `rojoLed`); error de Horarios (24, `rojoLed`); panel «No se pudo actualizar» de Novedades (20, `ambar`). |
| `accessible` | Timbre | Ómnibus accesible | Marca de confort en `ArrivalRow` y en `CartelParada` (14, `etiquetaCartel`). |
| `snow` | Timbre | Aire acondicionado | Marca de confort en `ArrivalRow` y en `CartelParada` (14, `etiquetaCartel`). |
| `route` | Timbre | Rutas guardadas | Subpestaña Rutas (22); campo «Destino» de Agregar ruta (20, `etiquetaCartel`). |
| `live` | Timbre | Un LED encendido: dato con GPS | Sin uso. El punto de los minutos en vivo es `LiveDot`, no este glifo. |
| `code` | Timbre | Código fuente | Sin uso. La fila «Código fuente» de Info usa `external`. |
| `grid` | pixelarticons | Servicios | Pestaña Servicios de la navegación (24). |
| `back` | pixelarticons | Atrás | Flecha de las pantallas apiladas (Info, Privacidad, Horarios), desde `actionIconTheme` del tema (24, `papel`). |
| `external` | pixelarticons | Se abre fuera de la app | Rincón de los mosaicos de Servicios (14, `ambarTenue`); nota del navegador en Servicios (22, `etiquetaCartel`); «Código fuente» en Info (20, `ambar`); «Ver más» de una novedad (20, `tinta`). |
| `card` | pixelarticons | Mi STM | Mosaico Mi STM de Servicios (48, `ambar`, brillo). |
| `money` | pixelarticons | Recarga | Mosaico Recarga de Servicios (48, `ambar`, brillo). |
| `map` | pixelarticons | Cómo Ir | «Ver en Cómo Ir» de la tarjeta (20, `ambar`); mosaico Cómo Ir de Servicios (48, `ambar`, brillo). |
| `lock` | pixelarticons | Bloqueo biométrico | Fila «Bloqueo biométrico» de Info (24, `etiquetaCartel`). |
| `unlock` | pixelarticons | Desbloquear | Botón «Desbloquear» de la pantalla de bloqueo (24, `tinta`). |
| `mail` | pixelarticons | Contacto | Fila «Contacto» de Info (20, `ambar`). |
| `news` | pixelarticons | Novedades | Subpestaña Novedades (22), con la insignia de no leídas. |
| `gps` | pixelarticons | Paradas cercanas | «Paradas cercanas» en Agregar parada (20, `ambar`). |
| `chevronRight` | pixelarticons | Ver más opciones | Al final de la fila «Aviso N min antes» (14, `etiquetaCartel`); «Política de privacidad» en Info, que abre una pantalla de la app (20, `ambar`). |
| `chevronDown` | pixelarticons | Desplegar | «Ver las N» bajo las filas de una tarjeta (20, `ambar`). |
| `minus` | pixelarticons | Plegar | «Ver menos» (20, `ambar`). |
| `close` | pixelarticons | Cerrar | Ícono de cierre del tema (`closeButtonIconBuilder`). Hoy ninguna pantalla muestra un botón de cierre. |
| `check` | pixelarticons | Hecho | Sin uso. |
| `search` | pixelarticons | Buscar | Campo «Buscar por calles» de Agregar parada (20, `etiquetaCartel`); botón «Ver líneas» de Agregar ruta (20, `papel`). |
| `bolt` | pixelarticons | Cero emisiones | Marca de confort en `ArrivalRow` y en `CartelParada` (14, `etiquetaCartel`). |
| `signal` | pixelarticons | Calidad del GPS | Panel de GPS parcial sobre Paradas y Rutas (20, `ambar`). |

Las pestañas de la navegación son `ambar` con brillo cuando están
elegidas y `tenue` cuando no; las subpestañas, `ambar` y `tenue` sin
brillo.

## La parada es un cartel, no un marcador de mapa

Una parada siempre se dibuja con `stop`: el cartel con un ómnibus arriba
del poste. Un marcador de mapa dice «un lugar en el mapa», y la app no
muestra mapas. El porqué está en [12-decisiones.md](12-decisiones.md).

## Fuera de `PixelGlyphs`

- **Selector de hora.** `showTimePicker` (botón «Desde» de Horarios y
  «Desde» y «Hasta» de los ajustes del aviso) muestra el botón de Flutter
  para pasar del reloj al teclado, con los íconos de Material
  `Icons.keyboard_outlined` e `Icons.access_time`. Es el único ícono de
  Material que aparece en pantalla. `showTimePicker` acepta
  `switchToInputEntryModeIcon` y `switchToTimerEntryModeIcon` para
  cambiarlos.
- **Widget de Android.** `widget_ic_clock.xml`, `widget_ic_route.xml` y
  `widget_ic_external.xml` son copias vectoriales de `clock`, `route` y
  `external`, con el mismo espacio de 0.14 celdas. Si cambiás uno de esos
  glifos, rehacé su vector ([10-superficies.md](10-superficies.md)).
- **Notificaciones e ícono de la app.** Usan el ómnibus de Timbre, no un
  glifo de este juego ([10-superficies.md](10-superficies.md)).

## Cómo agregar un ícono

1. Buscá primero en la tabla: `live`, `code` y `check` ya existen y no se
   usan.
2. Dibujalo en la grilla de 12 × 12, con el mismo grosor de línea que los
   glifos vecinos. El archivo dice que se generó desde el juego de píxeles
   de Timbre, pero el generador no está en el repositorio: el glifo se
   escribe a mano, fila por fila.
3. Agregalo a `PixelGlyphs` con un comentario `///` que diga dónde se usa.
   Si viene de pixelarticons, terminá el comentario con
   `(pixelarticons)`.
4. Usalo con `PixelIcon`, con un tamaño de `TimbreIconSize` y sin color
   fijo si el `IconTheme` ya da el correcto. Si el ícono dice algo que no
   dice el texto de al lado, dale un `semanticLabel`.
5. Sumalo a la tabla de esta página.
