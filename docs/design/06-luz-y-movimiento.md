# Luz y movimiento

El tablero es oscuro y está lleno de LEDs apagados. Solo se enciende lo
que está pasando, y casi nada se mueve.

## El tablero: `LedMatrix`

`LedMatrix` (`lib/ui/widgets/led_matrix.dart`) pinta una grilla de LEDs
apagados: puntos redondos de `dot` px de diámetro cada `pitch` px, con el
mismo margen a los dos lados, en `color` con la opacidad `opacity`. Es
solo textura: no responde al toque (`IgnorePointer`) y el lector de
pantalla no la ve (`ExcludeSemantics`).

Con `fadeFrom`, los puntos van de plenos en ese lado a nada en el opuesto.
Debajo de ese degradé el código pinta con un negro opaco
(`Color(0xFF000000)`): el alfa de la pintura se multiplica con el del
degradé, y con un color al 10 % los puntos desaparecerían. Es el único
literal de color de los widgets.

| Dónde | Paso / punto | Opacidad | Degradé |
|---|---|---|---|
| App bar (`buildTimbreAppBar` en `lib/ui/widgets/timbre_app_bar.dart`) | 6 / 2 | `TimbreOpacity.ledUnlit` (0.1) | Plenos a la derecha (`AlignmentDirectional.centerEnd`), nada a la izquierda: el cartel TIMBRE MVD y el título quedan sobre fondo limpio. |
| Ícono de la app (`TimbreAppIcon` en `lib/ui/widgets/timbre_bus.dart`) | lado / 32 y lado × 10 / 1024 | 0.1 | No |
| Mosaicos de Servicios, cartel de `TimbreEmptyState`, fecha de una novedad sin leer, recuadro «NO OFICIAL» de Info | 6 / 2 | 0.11 | No |
| Pantalla de bloqueo (`lib/ui/lock_screen.dart`) | 8 / 2.4 | 0.09 | No |

Todas usan `ambar`. Las opacidades 0.11 y 0.09 se escriben como número
junto al widget, no son token.

## Luz de LED

Hay brillo solo donde hay algo encendido. Cada caso calcula el suyo:

| Qué | Cómo | Dónde |
|---|---|---|
| `TimbreShadow.ledGlow` (`led-glow`) | `BoxShadow` `ambar` al 35 % (`#59FFB21E`), desenfoque 12, sin desplazamiento | Solo `LlegandoChip`: LLEGANDO es el único estado encendido entero, placa ámbar con letras `tinta`. |
| Halo de `LiveDot` | El punto cuadrado mide la mitad de `size` (6 px con el tamaño por defecto, 12). Su `BoxShadow`: su color al 60 %, desenfoque `0.45 × size` (5.4 px) | Los minutos en vivo: `MinutosEnVivo` y `CartelTira` (12), `CartelParada` (16). |
| `PixelIcon(glow: true)` | Copia del ícono al 55 %, desenfocada `1.1 × p` (p = lado de una celda) | Pestaña elegida de la navegación, campana de un aviso activado, mosaicos de Servicios ([04-iconos.md](04-iconos.md#brillo-glow)). |
| Resplandor del ícono de la app | El ómnibus desenfocado `0.022 × lado` con opacidad 0.45, debajo del ómnibus nítido | `TimbreAppIcon` (Info). |
| Halo de `LedLock` | Los puntos encendidos desenfocados `0.7 × paso`, `ambar` al 45 % (hasta 90 % en el destello del cierre) | El candado de la pantalla de bloqueo. |

`ledGlow` es la única sombra con token. El halo de `LiveDot` es una
excepción documentada: es luz sobre un dato en vivo, como LLEGANDO
([02-color.md](02-color.md#excepciones-documentadas),
[12-decisiones.md](12-decisiones.md)). Una sombra que no sea luz de algo
encendido no entra en el sistema.

Nada parpadea: `LiveDot` y LLEGANDO están quietos. Los minutos cambian
cuando llega un tablero nuevo.

## Opacidades: `TimbreOpacity`

| Token | Valor | Dónde |
|---|---|---|
| `ledUnlit` | 0.1 | LEDs apagados de `LedMatrix` por defecto: app bar e ícono de la app. |
| `pressSplash` | 0.16 | Onda del toque: `ambar` al 16 % (`splashColor` del tema y mosaicos de Servicios). |
| `pressHighlight` | 0.08 | Resaltado debajo de la onda: `ambar` al 8 % (`highlightColor` del tema y mosaicos de Servicios). |

Tocar algo lo enciende un poco: el tema usa `InkRipple.splashFactory` con
esos dos valores. Los mosaicos de Servicios repiten los colores en su
`InkWell` y pintan el fondo con `Ink` para que la onda se vea encima.

Las demás transparencias se escriben junto a su widget. La lista completa
está en [02-color.md](02-color.md#lo-que-no-es-token).

## Movimiento

### Animaciones propias

El proyecto escribió dos animaciones: el candado de la pantalla de bloqueo y
el movimiento de los ómnibus del Mapa.

#### `LedLock`: el candado

El candado de la pantalla de bloqueo (`lib/ui/widgets/led_lock.dart`):

- **El candado.** 13 × 18 puntos cuadrados con un paso de 8 (104 × 144
  px); cada punto mide 0.8 del paso. El ojo de la cerradura queda en LEDs
  apagados (`ambar` al 16 %).
- **El encendido** (`_intro`, 1400 ms). Una ola en diagonal, de arriba a
  la izquierda hacia abajo a la derecha, enciende el cuerpo (del 0 al 45 %
  del tiempo) y después el arco abierto (del 30 al 55 %). El arco baja de a
  una fila, como una animación de LEDs (del 60 al 80 %), y al cerrarse el
  halo da un destello (del 80 al 100 %).
- **El barrido.** Después, una línea de puntos `ambarClaro` recorre el
  candado de arriba abajo cada 3.6 s: barre en el primer cuarto (0.9 s) y
  descansa el resto.
- **Mientras está abierto el pedido del sistema** (`scanning`, que
  `LockScreen` activa al tocar «Desbloquear»): el barrido se repite cada
  0.9 s sin pausa y suma un haz de lectura, una línea `ambarClaro` al 70 %
  sobre un halo `ambar` al 50 %. El botón queda desactivado, en
  `ambarTenue`, hasta que el pedido se cierra.
- **Reducir movimiento.** Si `MediaQuery.maybeDisableAnimationsOf(context)`
  es verdadero, el candado aparece ya cerrado y quieto: sin ola y sin
  barrido.

El candado es decoración: el lector de pantalla oye «Aplicación
bloqueada» del cartel «BLOQUEADA».

#### Los ómnibus del Mapa

`BusLayer` (`lib/ui/map/bus_layer.dart`) mueve los ómnibus de un tablero al
siguiente:

- **El movimiento.** Cuando llega un tablero con posiciones nuevas, cada
  ómnibus se desliza desde donde está dibujado hasta su posición nueva en
  1000 ms (`BusLayer.moveDuration`), con `Curves.easeInOut`. Un solo
  `AnimationController` mueve a todos, y cada cuadro repinta solo la capa de
  los ómnibus (su propio `RepaintBoundary`). Un tablero con las mismas
  posiciones no reinicia un movimiento en curso.
- **Lo que no se mueve.** Un ómnibus nuevo aparece en su lugar y uno que ya no
  está desaparece en el acto, sin fundido. El mapa no gira, así que las
  píldoras siempre quedan derechas. Nada parpadea.
- **Fuera de la vista.** Con el Mapa tapado, en otra pestaña o con la app
  bloqueada, `TickerMode` lo deja sin animar y cada ómnibus salta a su
  posición. Los primeros tableros al volver también saltan: se movieron
  mientras no estaba.
- **Reducir movimiento.** Si `MediaQuery.maybeDisableAnimationsOf(context)`
  es verdadero, cada ómnibus salta a su posición nueva y queda quieto; un
  movimiento en curso termina donde iba.

Los ómnibus son pintura: el lector de pantalla los escucha en la frase de
cada parada ([11-accesibilidad.md](11-accesibilidad.md)).

### Lo que se mueve por Flutter

La app no cambia las animaciones de Material: la onda del toque, la
entrada de las pantallas apiladas, las hojas y los diálogos, el indicador
de las subpestañas, el switch, los indicadores de carga y deslizar para
actualizar se mueven como en cualquier app de Flutter. El mapa del Mapa se
arrastra, se acerca y sigue de largo al soltarlo como lo hace `flutter_map`
(todos sus gestos menos girar); el encuadre de las paradas, al abrirlo y
cuando se ubica una parada más, es un salto, sin animación.

Si algún día se agrega otra animación propia, que haga lo mismo que
`LedLock` y los ómnibus del Mapa con reducir movimiento: quedarse en su
estado final, quieta.
