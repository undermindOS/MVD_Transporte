# Principios

Cinco reglas para todo lo que se agrega a la app, a su ícono, al splash, al
widget y a las notificaciones. El porqué de cada una está en
[12-decisiones.md](12-decisiones.md).

## 1. Un tablero, no una copia de la app oficial

Cada pantalla es un tablero con carteles. El que abre la app ve de entrada
en qué se diferencia: los minutos con GPS se encienden como en el cartel
de la parada.

En el código:

- Mis paradas, Servicios, Info y Horarios arrancan con `buildTimbreAppBar`
  (`lib/ui/widgets/timbre_app_bar.dart`): el cartel TIMBRE MVD
  (`CartelCompacto`) y el título de página (`PageTitleBar`) sobre los LEDs
  apagados de `LedMatrix`. La pantalla de bloqueo no tiene barra: es
  entera un tablero, con el cartel TIMBRE MVD abajo.
- Una parada guardada es un tablero chico (`_Board` en `lib/ui/stops_page.dart`):
  nombre y número, horario y campana, y abajo sus próximos ómnibus en
  filas `ArrivalRow`.

## 2. Ámbar = luz = dato en vivo

`TimbreColors.ambar` se enciende solo donde algo está pasando o donde vos
actuás:

- los datos en vivo: minutos con GPS (`MinutosEnVivo`), LLEGANDO
  (`LlegandoChip`), la insignia de una línea con GPS (`LineBadge`), el
  ómnibus que estás esperando;
- la acción principal (botón con relleno, botón +);
- lo elegido y lo encendido: segmento, chip, pestaña, switch, aviso
  activado;
- el foco de un campo;
- los contadores.

Todo lo demás no brilla. Un horario, una estimación o una fila vieja
nunca van en ámbar, aunque antes hayan tenido GPS. La regla completa, con
sus excepciones documentadas, está en [02-color.md](02-color.md#la-regla-del-ámbar).

## 3. Siempre oscuro

No hay tema claro. `lib/main.dart` pasa un solo tema,
`buildTimbreTheme()`, con `Brightness.dark`, y no define `darkTheme` ni
`themeMode`: la app se ve igual con el teléfono en modo claro o en modo
oscuro.

- Fondo de pantalla: `noche`. Paneles (tarjetas, hojas, diálogos,
  navegación, el cartel TIMBRE MVD): `tinta`.
- No hay superficies blancas en ningún lado: hasta `inverseSurface` del
  tema es `tintaAlta`.
- Fuera de la app también: el ícono, el splash, el fondo de la ventana de
  Android y el widget son el mismo tablero oscuro
  ([10-superficies.md](10-superficies.md)).

## 4. El píxel es el material

Las letras de los carteles (Doto), los íconos y el candado de la pantalla
de bloqueo están hechos de puntos cuadrados con un pequeño espacio entre
ellos. El tablero que tienen debajo es una grilla de LEDs apagados.

- Íconos: `PixelIcon` dibuja los glifos de 12 × 12 de `PixelGlyphs`, con
  un espacio de 0.14 celdas entre píxeles, como los puntos de Doto
  ([04-iconos.md](04-iconos.md)).
- La app no usa íconos de Material, emoji ni íconos de línea de otros
  juegos. Los íconos no se redondean ni se dibujan con trazos.
- Tablero: `LedMatrix`; candado: `LedLock`
  ([06-luz-y-movimiento.md](06-luz-y-movimiento.md)).

## 5. Legible para todos

La app se usa en la calle, caminando, con cualquier edad y cualquier
vista.

- El texto tiene un contraste de 4.5:1 o más sobre su fondo
  ([02-color.md](02-color.md#contrastes)).
- La letra grande del sistema no corta nada: las pruebas de layout corren
  a 1×, 1.3× y 2× y fallan si algo desborda o termina en «…»
  ([11-accesibilidad.md](11-accesibilidad.md)).
- Cada fila tiene una sola frase para TalkBack y VoiceOver.
- El sentido no depende solo del color. Con GPS: insignia llena, punto
  encendido (`LiveDot`) y cifras Doto. Sin GPS: insignia en contorno,
  reloj y cifras Fira.

## Lo que no se hace

- Símbolos oficiales: el escudo de Montevideo, la bandera, el Sol de
  Mayo, los logos de STM, de la Intendencia o de las empresas de ómnibus.
  La app no es oficial, y las tiendas toman esos símbolos como una
  afiliación falsa.
- Franjas amarillas y negras, o bloques amarillos planos sobre negro: en
  Uruguay son los colores de un cuadro de fútbol. El ámbar es solo la luz
  de los LEDs sobre el azul noche.
- Ámbar sobre blanco, y superficies claras en general.
- Doto para horarios o estimaciones, y Doto por debajo de 19 px
  ([03-tipografia.md](03-tipografia.md)).
- Un sentido que dependa solo del color.
- «…» en el título de una página, o texto cortado con la letra grande.
