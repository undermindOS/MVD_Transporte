# Horarios del planificador de viajes

`horarios.bin` es el horario de los ómnibus urbanos del STM con el que la app arma los viajes de A a
B en el teléfono (`lib/services/rutas/`). Calcular un viaje no le pide nada a ningún servidor: ni
los lugares ni los viajes salen del teléfono. Es el único archivo de esta carpeta que declara
`pubspec.yaml` (este README no viaja).

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `horarios.bin` | 227 187 | `759cdba6aa8ee8db348776b96df2d4132a30e036126087a6edadec0bd86cc658` |

Armado el 2026-11-01 con `tool/rutas/build_horarios.py` (cómo rearmarlo: `tool/rutas/README.md`;
el formato está documentado al principio del script). Sin comprimir son 1 128 029 bytes.

## Fuentes

Datos abiertos de la Intendencia de Montevideo, sin claves:

| Qué | De dónde | Bajado | Fecha de la fuente |
|---|---|---|---|
| Pasadas por parada (`uptu_pasada_variante.zip`, 10 599 809 bytes, un CSV de 60 953 092 bytes) | `https://datos-abiertos.montevideo.gub.uy/uptu_pasada_variante.zip` | 2026-10-31 | CSV del 2026-10-31 00:05 (fecha dentro del zip; el servidor lo regenera cada día) |
| Variante → línea (1498 variantes, capa `imm:v_uptu_lsv_destinos`) | WFS `https://geoserver.montevideo.gub.uy/geoserver/ows` | 2026-10-31 | — |
| Paradas: punto y calles (43 339 filas parada × variante, capa `imm:v_uptu_paradas`, EPSG:4326) | el mismo WFS | 2026-11-01 | — |

Catálogo: «Horarios de ómnibus urbanos, por parada (STM)», «Transporte colectivo: paradas, puntos
de control y recorridos de ómnibus» y «Líneas de ómnibus, origen y destino» en
`catalogodatos.gub.uy`.

**Licencia:** Licencia de Datos Abiertos de Uruguay, Intendencia de Montevideo
(`assets/licenses/datos-abiertos-im.txt`). Los horarios son teóricos: la Intendencia los estima con
la velocidad promedio de los ómnibus y la distancia entre paradas.

## Qué tiene

- 4921 paradas, todas las que aparecen en el horario: número del STM (`cod_ubic_parada`), punto en
  micro-grados y nombre «{calle} y {esquina}» como lo escribe la Intendencia («SAN JOSE y ANDES»).
  Ninguna parada del horario quedó sin coordenadas. Ocho tienen solo una calle (se usa esa) y dos
  (23993 y 23994) ninguna: se llaman «Parada 23993» y «Parada 23994».
- 138 líneas («121», «D10», «CA1»…) y sus 1089 variantes con horario (todas tienen línea en el WFS).
- 37 859 viajes en 8902 rutas: una ruta junta los viajes de una variante con las mismas paradas y
  los mismos minutos entre ellas, así ningún viaje pasa a otro (RAPTOR lo necesita). Las rutas
  comparten 1077 secuencias de paradas.
- Por ruta y tipo de día (hábil, sábado, domingo) las salidas desde la primera parada, en minutos
  desde la medianoche del día en que sale el viaje: pasan de 1440 cuando el viaje sigue después de
  la medianoche.

## Cómo se leyó el CSV

`tipo_dia` es el del día en que el ómnibus pasa por la parada, y cada día lo cuenta a su manera:

- **Hábil** trae los viajes enteros, también después de la medianoche, con `N` (la hora vuelve a
  `0`: se suma 1440).
- **Sábado** repite como `S` las colas de los viajes del viernes que pasan la medianoche (249
  grupos). Se descartan: hábil ya las tiene.
- **Domingo** trae como `S` las colas de los viajes del sábado (226): se pegan al viaje del sábado.
- Las pasadas `*` (24 572 filas) son del lunes de madrugada: o la cola de un viaje del domingo
  que sigue después de la medianoche (190), o un viaje del servicio nocturno del domingo que sale
  después de la medianoche (298, entre las 00:00 y las 03:59). Quedan en el domingo con 1440
  minutos más. Por eso los lunes no corren los viajes hábiles que salen antes de las 04:00
  (`mondayCutoff` = 240): los reemplaza ese servicio del domingo.
- Si dentro de un viaje la hora retrocede menos de 12 horas, es un redondeo y queda la anterior
  (no pasó en este CSV).

No hay calendario de feriados: el tipo de día sale del día de la semana.
