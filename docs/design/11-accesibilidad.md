# Accesibilidad

La app se usa en la calle, caminando, con sol o de noche, y la usa gente de todas las edades y con
cualquier vista. Estas reglas están en el código y varias las revisan las pruebas; no se aflojan.
Donde el código todavía no cumple, la sección final lo dice.

Ver también:
- [02-color.md](02-color.md): la tabla completa de contrastes y la regla del ámbar.
- [03-tipografia.md](03-tipografia.md): los estilos de `TimbreText`, el mínimo de Doto y
  `isLarge`.
- [07-textos.md](07-textos.md): cómo se escriben las frases que escucha el lector de pantalla.
- [08-componentes.md](08-componentes.md) y [09-pantallas.md](09-pantallas.md): cada pieza y cada
  pantalla.
- [06-luz-y-movimiento.md](06-luz-y-movimiento.md): las dos animaciones propias (el candado y
  los ómnibus del Mapa).

## Contraste

- El texto necesita 4.5:1 o más sobre su fondo.
- Las marcas e íconos que dicen algo necesitan 3:1 o más.
- Lo desactivado y lo decorativo no tienen mínimo.

Contraste WCAG 2.x calculado con los valores de `lib/ui/theme/timbre_tokens.dart`:

| Texto \ fondo | `noche` | `tinta` | `tintaAlta` | `avisoNoche` |
|---|---|---|---|---|
| `papel` | 16.21 | 14.60 | 12.35 | 13.36 |
| `etiquetaCartel` | 8.72 | 7.85 | 6.64 | 7.19 |
| `tenue` | 5.89 | 5.31 | **4.49** | 4.86 |
| `ambar` | 10.58 | 9.53 | 8.06 | 8.72 |
| `ambarTenue` | 6.46 | 5.82 | 4.93 | 5.33 |
| `rojoLed` | 6.81 | 6.13 | 5.19 | 5.61 |

Qué par se usa dónde está en [02-color.md](02-color.md). Lo que hay que saber:

- **Sobre ámbar, el texto es siempre `tinta`** (9.53:1): LLEGANDO, la línea con GPS, el botón
  principal, el segmento y el chip elegidos, el contador de novedades. Nunca `papel` (1.53:1) ni
  blanco (1.80:1).
- **`tenue` sobre `tintaAlta` da 4.49:1**, apenas por debajo de 4.5. Solo se usa en lo
  desactivado (el texto de un `FilledButton` desactivado) y en el pulgar del switch apagado, que no
  es texto. No pongas texto activo `tenue` sobre `tintaAlta`.
- **Los bordes `lineaNoche` quedan por debajo de 3:1** (1.29 a 1.69:1). Son decoración. Un campo
  se reconoce por su rótulo, su ícono y, con foco, por el borde ámbar de 2 px (9.53:1 contra el
  diálogo `tinta`, 10.58:1 contra el relleno `noche` del campo). Una tarjeta se reconoce por su
  contenido. Si algún día hace falta un campo que se reconozca sin rótulo, el borde tiene que
  subir a 3:1.
- **El sol.** La pantalla oscura refleja en la calle. Por eso lo importante va con mucho contraste
  (`papel` 16:1, `ambar` 10.6:1) y los minutos en vivo van grandes. Si las opiniones de la tienda
  dicen «no se ve con sol», la respuesta barata es un modo de día con el mismo tema (ver
  [12-decisiones.md](12-decisiones.md)).

### El sentido no depende solo del color

| Qué | Cómo se distingue además del color |
|---|---|
| Ómnibus con GPS | `LineBadge` relleno, el punto `LiveDot` y los minutos en Doto |
| Horario teórico | `LineBadge` de contorno, un reloj y la hora en Fira Sans Extra Condensed |
| Estimado de datos viejos | `LineBadge` de contorno, un reloj y «~» antes de la hora |
| Ómnibus que esperás | la fila levantada (`tintaAlta`) y la campana; el lector agrega «estás esperando este ómnibus» |
| Error | el ícono `warning` y una frase que dice qué pasó y qué hacer |
| Segmento elegido | el lector lo anuncia como elegido (`selected`) |
| Novedad sin leer | el rótulo «NUEVA», el fondo `tinta` y la fecha sobre LEDs; el lector empieza con «Nueva» |

## Letra grande

La app se prueba con la letra del sistema hasta 2× (en Android, el tamaño más grande desde
Android 14). Con esa escala no se desborda nada y no se corta lo importante. Los tamaños de
accesibilidad de iOS pasan de 2× y no están probados.

### Desde 150 %: `TimbreText.isLarge`

`TimbreText.isLarge(context)` es verdadero cuando la escala de texto llega a
`TimbreText.largeFrom` (1.5): mide `textScaler.scale(17) >= 17 × 1.5`. Desde ahí cambia la
disposición:

- **`ArrivalRow`:** la hora o los minutos bajan a su propia línea, debajo del destino, alineados a
  la derecha. Si ni así entran, se achican con `FittedBox`; no se cortan.
- **`CartelTira`:** el destino pasa a su propia línea, debajo de la línea y los minutos, con hasta
  3 líneas. Esto pasa también por debajo de 150 % si el destino no entra en 2 líneas al lado de
  los minutos sin partir una palabra (`_fitsInRow`).
- **Subpestañas de Mis paradas:** el `TabBar` se desplaza de costado y cada etiqueta queda entera
  («Paradas», «Rutas», «Novedades»).

### A cualquier escala

- **Título de página:** una sola línea en Doto que se achica a lo ancho (`FittedBox`). Nunca
  termina en «…».
- **Alto de la barra:** `PageTitleBar.preferredSize` se calcula con la escala de texto y con las
  líneas que ocupa el subtítulo al ancho de la pantalla, hasta 4 (`subtitleMaxLines`). Horarios
  muestra el nombre entero de la parada a 2×, también uno del catálogo que necesita tres líneas
  («AV 18 DE JULIO y CIRCUNVALACION DR ENRIQUE TARIGO»).
- **Nombre de parada en la tarjeta:** sin límite de líneas.
- **Destino en las filas** (`ArrivalRow`, fila de Horarios): hasta 2 líneas.
- **Cosas de tamaño fijo que se achican adentro:** el número de línea en `LineBadge`, la hora de
  Horarios (columna de 56), la fecha de una novedad (recuadro de 52 × 56), las etiquetas de
  `TimbreSegmented` y el nombre «Timbre MVD» de Info.
- **Lo que se puede desplazar:** las subpestañas vacías (`_EmptyTab`), las hojas
  (`isScrollControlled` y `SingleChildScrollView`), el diálogo de Agregar ruta y la pantalla de
  bloqueo.

Lo que sí puede terminar en «…»: un destino de más de 2 líneas, la línea «#5109 · 48 m · …» de una
parada cercana después de 2 líneas, el subtítulo de la barra después de 4 líneas o si la pantalla
es más angosta que la medida, y el destino de `CartelParada`, que hoy no se usa.

### Doto nunca por debajo de 19 px

Con menos de 19 px los puntos de Doto dejan de leerse como letras (`TimbreFonts.dotoMinSize`).
Tres mecanismos lo sostienen:

1. `TimbreText.cartel(size)` y `TimbreText.liveMinutes(size)` nunca devuelven menos de 19 px.
   `CartelCompacto` sube su propio tamaño a 19 si le piden menos.
2. Con la letra del sistema más chica que 1×, `MediaQuery.withClampedTextScaling(minScaleFactor:
   1)` evita que el texto Doto se achique por debajo de su tamaño en: `LlegandoChip`,
   `CartelTira` (todo el cartel), el cartel de `TimbreEmptyState`, «NO OFICIAL» de Info y
   `CartelCompacto`. Este último además no crece más de 1.3× (`maxScaleFactor: 1.3`).
3. El resto del texto Doto no tiene ese límite, pero es tan grande que a 0.85× (la escala más
   chica de Android) sigue arriba de 19 px: el título de página (28 → 23.8), los minutos de
   `ArrivalRow` (26 → 22.1), el día de una novedad sin leer (24 → 20.4) y «BLOQUEADA» (30 → 25.5).

`test/cartel_test.dart` lo prueba a 0.85×.

## Lectores de pantalla

TalkBack y VoiceOver escuchan una frase completa por cada cosa, no pedazos sueltos.

### Una frase por fila

- Cada fila, tarjeta o mosaico es un solo nodo:
  `Semantics(label: frase, excludeSemantics: true)`, con `container: true` cuando tiene que ser un
  nodo aparte.
- `excludeSemantics` también se lleva la acción de tocar del `InkWell` de adentro. Por eso, si la
  cosa se puede tocar, el `Semantics` lleva su propio `onTap`; si no, deja de funcionar con el
  lector. Lo cumplen `ArrivalRow`, las filas de Agregar parada, `_NewsRow`, los mosaicos de
  Servicios, `_LinkRow` de Info, cada segmento de `TimbreSegmented`, las paradas del Mapa y su
  «© OpenStreetMap».
- Una fila que no se puede tocar no se anuncia como botón: `ArrivalRow` pone `button: onTap !=
  null`, así que una fila estimada no es botón.
- Lo decorativo no se escucha: `PixelIcon` sin `semanticLabel`, `LedMatrix`, `TimbreBus` y
  `LedLock` van envueltos en `ExcludeSemantics`.
- Los ómnibus del Mapa son pintura (`BusLayer`, un `CustomPaint`): el lector no los recorre uno
  por uno. Lo que dicen está en la frase de cada parada, que cuenta cuántos vienen, y en las hojas.
  El mapa base tampoco se escucha.
- Los carteles en mayúsculas se escuchan como frase normal: «MIS PARADAS» se lee «Mis paradas»,
  «SIN PARADAS» se lee «Sin paradas guardadas», «BLOQUEADA» se lee «Aplicación bloqueada». Las
  secciones de Privacidad se leen como están en el archivo: «RESUMEN» se lee «Resumen».

### Con la app bloqueada, solo el bloqueo

Mientras está la pantalla de bloqueo, el lector no llega a nada de la app: `AppLock` la deja
debajo dentro de un `Offstage`, que la saca del árbol de semántica, junto con las páginas, hojas,
diálogos y snack bars abiertos. La pantalla de bloqueo es una pantalla aparte para el lector
(`Semantics(scopesRoute: true)`), como una página.

### Las frases

| Dónde | Lo que se escucha | Código |
|---|---|---|
| Ómnibus con GPS | «Línea 121 a Punta Carretas, llega en 12 minutos, con GPS, accesible, aire acondicionado, cero emisiones» | `ArrivalRow._sentence` |
| En la parada | «Línea 121 a Punta Carretas, llegando, con GPS» | `ArrivalRow._sentence` |
| Horario teórico | «Línea 144 a Cementerio del Norte, horario 20:01, sin GPS» | `ArrivalRow._sentence` |
| Estimado de datos viejos | «Línea 116 a Pocitos, alrededor de las 20:01, estimado» | `ArrivalRow._sentence` |
| El ómnibus que esperás | la frase de su estado y «, estás esperando este ómnibus» | `ArrivalRow._sentence` |
| Encabezado de tarjeta de parada | «Parada 574, San Jose y Andes», con la acción «Borrar»; una parada sin nombre, «Parada 574» | `_stopPhrase` |
| Encabezado de tarjeta de ruta | «De San Jose y Andes a Trabajo, líneas 116, 121, hacia Pocitos», con la acción «Borrar» | `_routePhrase` |
| Fila del aviso | su texto, como botón: «Aviso 5 min antes · Siempre» | `_buildAlertSettingsRow` |
| Campana, reloj, + e Info | «Activar avisos» o «Desactivar avisos»; «Horarios»; «Agregar parada» o «Agregar ruta»; «Info» | `tooltip` de cada botón |
| Cartel de «Estoy esperando» | «Línea 121 a Punta Carretas, llega en 12 minutos, con GPS» | `CartelTira` |
| Debajo del cartel | «San Jose y Andes, con GPS»; sin GPS, «Según horario 20:17, sin GPS todavía, San Jose y Andes» | `_showWaitSheet` |
| Parada cercana | «Parada 5109, Andes y Av 18 de Julio, a 48 metros, líneas 124, 124 SD, 125», como botón | `_buildNearbyTile` |
| Parada por calles | «Parada 574, San Jose y Andes», como botón | `_buildMatchTile` |
| Campos obligatorios de Agregar ruta | «Parada de origen, obligatorio», «Destino, obligatorio» | `semanticsLabel` del rótulo |
| Título de Ajustes de aviso | «Parada 574, San Jose y Andes» o «De San Jose y Andes a Trabajo», como encabezado | `spokenTitle` |
| Chips de días | «Lunes» a «Domingo» | `_dayNames` |
| `TimbreSegmented` | el nombre del grupo («Tipo de día», «Minutos antes de que llegue») y cada segmento como botón, con su estado de elegido | `segmented.dart` |
| Barra de Horarios | «Horarios de la parada 574, San Jose y Andes», como encabezado | `SchedulePage` |
| Encabezado de hora | «Las 20», como encabezado | `_HourHeader` |
| Pasada de Horarios | «23:31, línea 145 a Plaza España» | `_PassRow` |
| Novedad | «Nueva. 2 de octubre. Título. Resumen», como botón | `_NewsRow._sentence` |
| Contador de Novedades | «1 novedad sin leer», «10 novedades sin leer» | `StopsPage.build` |
| Carteles vacíos | «Sin paradas guardadas», «Sin rutas guardadas», «Sin novedades», «Sin pasadas para este horario» | `TimbreEmptyState.message` |
| Placa de la barra | «Timbre MVD» | `CartelCompacto` |
| Mosaico de Servicios | «Mi STM. Saldo y movimientos de tu tarjeta. Abre el sitio oficial en el navegador», como botón | `_SiteTile` |
| Aviso de Info | «Aplicación no oficial. No está afiliada con la Intendencia de Montevideo, el STM ni ninguna empresa de transporte.» | `InfoPage` |
| Enlaces de Info | «Código fuente, github.com/undermindOS/MVD_Transporte, se abre en el navegador»; «Contacto, daniil@khrestenkov.com, se abre en tu app de correo»; «Política de privacidad», sin «se abre en», porque abre una pantalla de la app | `_LinkRow` |
| Bloqueo biométrico | la fila entera junto con la llave (`MergeSemantics`) | `InfoPage` |
| Pantalla de bloqueo | «Aplicación bloqueada», como encabezado | `LockScreen` |
| Privacidad | el título del archivo y cada sección («Resumen»), como encabezados; la viñeta de una lista no se escucha | `PrivacyPolicyPage` |
| Widget de Android | «Línea 116 a POCITOS, alrededor de las 14:32, estimado» | `MVDTransporteWidgetProvider.kt` |
| Parada del Mapa | «Parada 574, San Jose y Andes, 2 ómnibus con GPS en camino», como botón; con uno, «1 ómnibus con GPS en camino»; sin ninguno, «sin ómnibus con GPS en camino»; con un tablero viejo, «2 ómnibus en camino, estimado»; sin tablero de menos de 5 min, o con uno viejo y ningún ómnibus, solo «Parada 574, San Jose y Andes» | `_StopMarker._phrase` |
| Atribución del Mapa | «© OpenStreetMap», como enlace | `_Attribution` |
| Hoja de un ómnibus del Mapa | «Línea 117 a Punta Carretas», como encabezado; cada parada, «A la parada 574, San Jose y Andes, llega en 4 minutos, con GPS», «…, llegando, con GPS» o «…, alrededor de las 19:56, estimado» | `BusSheet`, `_EtaRow._sentence` |
| Hoja de una parada del Mapa | «Parada 574, San Jose y Andes», como encabezado; las filas, como `ArrivalRow` | `StopSheet` |

Las marcas de confort se escuchan solo cuando el dato es `true`. Con proxy pueden ser
«accesible», «aire acondicionado» y «cero emisiones»; sin proxy, solo «accesible».

Son encabezados: el título de página, la barra de Horarios, los encabezados de hora, el título de
Ajustes de aviso, «Tu tarjeta STM» y «Para moverte» en Servicios, el título y las secciones de
Privacidad, el título de las hojas del Mapa y «BLOQUEADA».

### Borrar sin deslizar

Deslizar una tarjeta para borrarla no sirve con el lector. Por eso el encabezado de cada tarjeta
lleva la acción personalizada «Borrar» (`_deleteAction`), que hace lo mismo que deslizar.

### Nombres de la API en palabras: `spokenName`

Los nombres de parada y los destinos llegan en mayúsculas («AV ITALIA y PROPIOS», «PUNTA
CARRETAS»). Algunos lectores deletrean las palabras en mayúsculas letra por letra. `spokenName`
(`lib/ui/spoken_text.dart`) los pasa a palabras con mayúscula inicial solo para el lector; la
pantalla sigue en mayúsculas.

- Cada palabra va en minúscula con la primera letra en mayúscula: «AV ITALIA y PROPIOS» → «Av
  Italia y Propios».
- Las partículas quedan en minúscula si no van primero: a, al, de, del, e, el, en, la, las, los,
  o, y. Una «Y» mayúscula entre dos calles se puede leer como la letra.
- No agrega tildes: «SAN JOSE» se lee «San Jose».
- Pasan por `spokenName` los nombres de parada (también el origen de una ruta) y los destinos de
  los ómnibus. No pasan los números de línea ni el destino de una ruta, que lo escribiste vos.

## Tamaño táctil

Todo lo que se toca mide al menos 44 × 44 (`TimbreSpace.touch`). Una fila de ómnibus mide al menos
52 de alto.

| Elemento | Mínimo | Dónde se fija |
|---|---|---|
| `IconButton` (campana, reloj, Info, volver) | 44 × 44 | `iconButtonTheme` en `timbre_theme.dart` |
| `TextButton` («Ver en Cómo Ir», «Ver las N», «Reintentar») | 44 × 44 | `textButtonTheme` |
| `OutlinedButton` y `ElevatedButton` | 48 de alto | `outlinedButtonTheme`, `elevatedButtonTheme` |
| `FilledButton` (botón principal) | 52 de alto | `filledButtonTheme` |
| Segmento de `TimbreSegmented` | 44 de alto | `segmented.dart` |
| Fila «Aviso N min antes» | 44 de alto, todo el ancho de la tarjeta | `_buildAlertSettingsRow` |
| «Desde H:MM» en Horarios | 44 de alto | `schedule_page.dart` |
| `ArrivalRow` | 52 de alto | `arrival_row.dart` |
| Enlaces de Info | 52 de alto | `_LinkRow` |
| «Desbloquear» | 220 × 56 | `lock_screen.dart` |
| Chips y switches | 48 de alto: el tema no cambia `materialTapTargetSize`, así que en el teléfono vale el área táctil de Material | valor por defecto de Flutter |
| Botones «Mi STM» y «Recarga» del widget | 44 dp de alto | `res/layout/mvd_transporte_widget.xml` |
| Parada del Mapa | 44 × 44, con la baldosa de 26 en el medio | `_StopMarker` en `mapa_page.dart` |
| «© OpenStreetMap» | 44 × 44 | `_Attribution` en `mapa_page.dart` |
| Fila de la hoja de un ómnibus del Mapa | 52 de alto | `_EtaRow` en `map_sheets.dart` |

La fila de Horarios también mide 44 de alto, aunque no se toca. El ícono de un campo ocupa una caja
de 44 × 44 (`_FieldIcon`), pero no es un botón.

Un ómnibus del Mapa no llega a 44: se toca dentro de su píldora más 4 px de cada lado (unos 33 de
alto) o a 14 px de su punto (`BusLayer`). La misma información está en la parada, que sí mide
44 × 44.

## Movimiento

Hay dos animaciones propias: el candado de la pantalla de bloqueo y el movimiento de los ómnibus
del Mapa. Con «reducir movimiento» del sistema (`MediaQuery.disableAnimations`), `LedLock` se queda
quieto y cerrado, y cada ómnibus salta a su posición nueva. Lo prueban
`test/lock_screen_test.dart` y `test/map/bus_layer_test.dart`.

## Pruebas

Las pruebas de disposición usan las fuentes reales (`loadBundledFonts()`) en una pantalla de
teléfono de 390 × 844 (`usePhoneScreen()`), las dos en `test/support/layout.dart`. Un desborde o un
texto cortado hace fallar la prueba.

| Prueba | Qué revisa | Escalas |
|---|---|---|
| `test/stops_layout_test.dart` | las filas del tablero; la nota de error con los estimados; el cartel de «Estoy esperando» con «PUNTA CARRETAS» y «DELTA DEL TIGRE» | 1×, 1.3×, 2× |
| `test/stops_layout_test.dart` | las etiquetas de las subpestañas enteras | 2× |
| `test/screens_test.dart` | Horarios: el nombre entero de la parada y el destino en 2 líneas | 1×, 1.3×, 2× |
| `test/screens_test.dart` | Horarios: un nombre de parada de tres líneas, entero y dentro de la barra | 2× |
| `test/screens_test.dart` | Servicios, Novedades, Horarios e Info sin desborde; la barra con subtítulo; el título más largo | 2× |
| `test/stop_search_layout_test.dart` | Agregar parada con la búsqueda por calles | 2× |
| `test/lock_screen_test.dart` | la pantalla de bloqueo sin desborde; el candado quieto con movimiento reducido | 2× |
| `test/privacy_policy_test.dart` | Privacidad sin desborde hasta la última sección; «geoserver.montevideo.gub.uy» en una sola línea | 2× |
| `test/map/mapa_layout_test.dart` | el Mapa: el cartel vacío, las notas, el panel de error, el error del mapa base, la atribución y las dos hojas, con todas sus palabras | 1×, 1.3×, 2× |
| `test/cartel_test.dart` | Doto nunca por debajo de 19 px | 0.85× |

Las frases del lector se prueban con `find.bySemanticsLabel` en `cartel_test`, `stops_page_test`,
`stops_board_test`, `screens_test`, `stop_search_test`, `news_tab_test`, `proxy_bff_test`,
`lock_screen_test`, `privacy_policy_test` y `map/mapa_page_test`. Si cambiás una frase, cambiá
también la prueba que la busca.

### Antes de dar por terminada una pantalla o un componente

- [ ] Prueba de disposición a 1×, 1.3× y 2× con `loadBundledFonts()` y `usePhoneScreen()`.
- [ ] Una frase por fila con `Semantics(label:, excludeSemantics: true)`, y `onTap` si se toca.
- [ ] Nombres de la API pasados por `spokenName` en la frase.
- [ ] Todo lo que se toca, de 44 × 44 o más.
- [ ] Texto con 4.5:1 o más sobre su fondo; íconos con sentido, 3:1.
- [ ] Doto de 19 px o más, también con la letra más chica del sistema.
- [ ] El sentido no depende solo del color.

## Lo que hoy no está resuelto

- **El widget de Android** lee el destino en mayúsculas («Línea 116 a POCITOS, …»): el proveedor
  en Kotlin no tiene un equivalente de `spokenName`.
- **`CartelTira` con destino vacío** dice «Línea 121 a , llega en 12 minutos, con GPS». La hoja de
  «Estoy esperando» cuida el destino vacío solo para los ómnibus sin GPS.
- **La barra de Horarios** de una parada guardada sin nombre dice «Horarios de la parada 574,
  Parada 574»: no usa la regla de `_stopPhrase`.
- **La fila del aviso** se lee tal como se ve, con abreviaturas y signos: «Aviso 5 min antes · Lun
  a Vie 7:30–8:30». No tiene una frase propia.
- **No hay pruebas automáticas de contraste ni de tamaño táctil** (`meetsGuideline` no se usa). La
  tabla de contrastes se calcula a mano; `test/design_tokens_test.dart` solo revisa que los
  valores de `tokens.json` sean los del código.
- **Huecos en las pruebas de disposición.** Servicios, Novedades, Info, Privacidad, Agregar parada y
  la pantalla de bloqueo se prueban solo a 2×. Agregar ruta, Ajustes de aviso y el detalle de una
  novedad no tienen prueba de disposición.
- **Los tamaños de accesibilidad de iOS**, más grandes que 2×, no están probados.
- **Privacidad en un teléfono angosto.** A 2× en una pantalla de 360 de ancho,
  «geoserver.montevideo.gub.uy» se parte en dos líneas en medio de la palabra; desde 375 entra en
  una. No se corta nada. La prueba usa 390 de ancho.
- **Los bordes `lineaNoche`** quedan por debajo de 3:1 (ver «Contraste»).
