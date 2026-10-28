# Timbre MVD: sistema de diseño

Timbre MVD es una app no oficial para los ómnibus de Montevideo. Su imagen
es el cartel de una parada: un tablero oscuro, LEDs apagados, y en ámbar
solo lo que está pasando ahora. Estas reglas valen para todo lo que se
agrega a la app y también para su ícono, el splash, el widget de Android y
las notificaciones.

## El código manda

El sistema vive en el código Flutter de este repositorio:

| Archivo | Qué tiene |
|---|---|
| `lib/ui/theme/timbre_tokens.dart` | Colores, radios, espacios, opacidades, tamaños de ícono y la sombra: `TimbreColors`, `TimbreRadii`, `TimbreSpace`, `TimbreOpacity`, `TimbreIconSize`, `TimbreShadow`. |
| `lib/ui/theme/timbre_text.dart` | Las familias (`TimbreFonts`) y los estilos de texto (`TimbreText`, con `isLarge` y `largeFrom`). |
| `lib/ui/theme/timbre_theme.dart` | `buildTimbreTheme()`: el tema Material 3 oscuro que reparte esos valores a botones, campos, hojas, diálogos y navegación. |
| `lib/ui/widgets/` | Los componentes propios: carteles, fila de ómnibus, insignia de línea, íconos de píxeles, tablero de LEDs, candado. |

Estas páginas describen el código. Si una página y el código no
coinciden, vale el código y hay que corregir la página. Cada valor de
estas páginas se revisó contra el código; cuando el código todavía no
cumple una regla, la página lo dice.

[`tokens.json`](tokens.json) es el espejo legible por máquina de los
tokens y de los estilos de `TimbreText`. `test/design_tokens_test.dart` lo
compara con las constantes de Dart: si un valor difiere, o si un token
existe de un solo lado, la prueba falla.

Este sistema es la traducción del que se armó en claude.ai, en ruso,
corregida para que coincida con el código. Esa versión la actualiza el
dueño del proyecto; si difiere de esta, vale esta.

## Índice

Lenguaje visual:

- [01-principios.md](01-principios.md): las cinco reglas (tablero, ámbar =
  luz, siempre oscuro, píxel, legible para todos) y lo que no se hace.
- [02-color.md](02-color.md): los 12 colores y para qué sirve cada uno, la
  tabla de contrastes, la regla del ámbar con sus excepciones, errores
  frente a avisos.
- [03-tipografia.md](03-tipografia.md): Doto, Fira Sans Extra Condensed y
  Fira Sans; todos los estilos de `TimbreText`; el mínimo de 19 px y la
  letra grande.
- [04-iconos.md](04-iconos.md): los 33 íconos de `PixelGlyphs` y dónde se
  usa cada uno, tamaños, colores y brillo.
- [05-formas-y-espacio.md](05-formas-y-espacio.md): radios, espacios,
  tamaño táctil, bordes y la tarjeta de parada.
- [06-luz-y-movimiento.md](06-luz-y-movimiento.md): el tablero de LEDs,
  los brillos, las opacidades y la única animación.

Contenido e interfaz:

- [07-textos.md](07-textos.md): voz, vocabulario, formatos de hora y el
  catálogo de estados y errores.
- [08-componentes.md](08-componentes.md): cada componente y qué campo del
  modelo y de /v1 muestra.
- [09-pantallas.md](09-pantallas.md): cada pantalla, sus estados, de dónde
  sale cada dato y cuándo se refresca.
- [10-superficies.md](10-superficies.md): ícono, splash, fondo de ventana,
  widget, notificaciones y tiendas.
- [11-accesibilidad.md](11-accesibilidad.md): contraste, letra grande,
  lectores de pantalla, tamaño táctil y pruebas.
- [12-decisiones.md](12-decisiones.md): por qué el sistema es así. Leelo
  antes de cambiar una regla.
- [13-en-el-codigo.md](13-en-el-codigo.md): mapa de archivos de la
  interfaz, los datos, los modelos y las pruebas.

Datos:

- [contrato-v1.md](contrato-v1.md): el contrato /v1 entre la app y el
  proxy, el modo directo, la caché, los errores y la privacidad.
- [pantalla-a-datos.md](pantalla-a-datos.md): de cada dato en pantalla
  hasta su campo en la fuente.
- [tokens.json](tokens.json): espejo de los tokens, verificado por prueba.

## Cómo proponer un cambio

Un cambio de diseño va en un solo PR, con estas cuatro partes:

1. **Código.** El token nuevo o cambiado en `timbre_tokens.dart`, o el
   estilo en `timbre_text.dart`, con un comentario que diga dónde se usa.
   Para un color de texto, anotá su contraste sobre los fondos donde va.
   En los widgets no se escriben literales `Color(0x…)`, solo tokens; la
   única excepción hoy es el negro opaco del shader en
   `lib/ui/widgets/led_matrix.dart`.
2. **`tokens.json`.** La misma entrada, con `dart`, `value` (o los campos
   del estilo) y `usage`.
3. **Prueba.** El token en el mapa que corresponde de
   `test/design_tokens_test.dart`. Si el cambio toca la disposición, las
   pruebas de layout con fuentes reales en una pantalla de 390 × 844 a 1×,
   1.3× y 2× (`loadBundledFonts()` y `usePhoneScreen()` en
   `test/support/layout.dart`).
4. **Documentación.** La página de `docs/design/` que corresponde, y la
   tabla de contrastes de [02-color.md](02-color.md) si cambió un color.

Antes de pedir revisión, corré desde la raíz del repositorio:

```bash
flutter analyze
flutter test
```

`flutter test` tiene que correr desde la raíz: `design_tokens_test.dart` y
las pruebas del contrato leen sus archivos por ruta relativa.

Si el cambio se ve en la app, sumá una línea en español bajo
`[Unreleased]` en `CHANGELOG.md`.
