# Mapa base de la pestaña Mapa

El mapa base viene dentro de la app: Montevideo y alrededores (Ciudad de la Costa, Las Piedras,
Pando), con el estilo «Timbre Noche». Mover el mapa no le pide nada a ningún servidor. Armado el
2026-10-28.

En la app viajan solo estos dos archivos, los únicos que declara `pubspec.yaml` (este README no):

| Archivo | Bytes | SHA-256 | Qué es |
|---|---|---|---|
| `mvd-20261028.pmtiles` | 14 860 490 | `7f709b47def44df05ddc97e31e0a68158162caecaa85b710ba876ab193835111` | Teselas vectoriales (MVT) de Protomaps, PMTiles v3, bbox `-56.80,-34.97,-55.70,-34.50`, zoom 0–15, compresión gzip |
| `style_noche.json` | 58 489 | `e78b294976dd3907d8ea456837d8b33dbb1c22bb7f3cbd0e06e1d63fe6282f9d` | Estilo MapLibre v8 «Timbre Noche», minificado, 67 capas, sin `sprite` ni `glyphs` |

El generador del estilo está en [`tool/map/`](../../tool/map/): `gen_style.mjs`, `flavor_noche.json` y
un `package.json` con las versiones fijas (más su `package-lock.json`).

Las pruebas de `test/map/basemap_assets_test.dart` comprueban el SHA-256 y los bordes del
`.pmtiles`, y compilan el estilo de verdad: 67 capas, ninguna advertencia del lector y solo los 12
colores del flavor (nada de ámbar).

## Cómo lo usa la app

- `lib/services/map/basemap.dart` (`Basemap.load`) copia el archivo, una sola vez, del paquete de
  la app a `getApplicationCacheDirectory()/map/mvd-20261028.pmtiles`: primero a un `.tmp` y después
  lo renombra. Como el nombre lleva la versión, si el archivo existe está completo. Borra cualquier
  otro `*.pmtiles` o `*.tmp` de esa carpeta. Es la carpeta de caché a propósito: no entra en los
  respaldos de iCloud ni de Android, y si el sistema la vacía, la app vuelve a copiar el archivo.
- `lib/services/map/local_pmtiles_provider.dart` lee las teselas de esa copia y las entrega
  todavía comprimidas: `flutter_map_vector_tiles` las descomprime en sus isolates.
- Los bordes del mapa (`Basemap.bounds`) salen del encabezado del `.pmtiles`, no de una constante.
- El estilo se compila con `ThemeReader`, una sola vez. La fuente `protomaps` se sirve por su
  id con la copia local: la URL `pmtiles://__PMTILES__` del estilo queda como marcador y la app
  nunca la lee. No se usa `StyleReader`: lee los `asset://` solo con `rootBundle` (no con otro
  `AssetBundle`, como el de las pruebas), y si alguna vez no resolviera la fuente, la abriría por
  HTTP. Con `ThemeReader` no hay ningún camino a la red, y la ruta del archivo nunca pasa por una URL.
- El estilo no trae `glyphs`: `flutter_map_vector_tiles` dibuja las etiquetas con el motor de texto
  de Flutter y nunca lee esa clave (el validador de MapLibre tampoco la pide). Las etiquetas salen
  con la fuente del sistema (Roboto en Android, SF en iOS), no con Fira Sans: de `text-font` el
  paquete solo toma el peso (`Medium` → 500) y la cursiva.
- Zoom: el estilo está escrito para teselas de 512 px (MapLibre) y `flutter_map` cuenta el zoom
  con teselas de 256 px. Zoom del estilo = zoom de `flutter_map` − 1 (`TileOffset.maplibre`); las
  conversiones están en `Basemap.fmZoom` y `Basemap.styleZoom`.
- Cerca del borde del bbox, y más allá con zoom alto, no hay teselas y se ve el `background`
  (`noche`): la cámara no sale de `Basemap.bounds`. Por encima de z15 el mapa sobreamplía
  (overzoom) las teselas de z15.

## Tokens → flavor

Colores de `TimbreColors` (`lib/ui/theme/timbre_tokens.dart`, `docs/design/02-color.md`). En el mapa
base no hay ámbar (`ambar`, `ambarTenue`, `ambarClaro`, `avisoNoche`), ni `rojoLed` ni `papel`: el
ámbar queda para los ómnibus con GPS.

| Token | Valor | Campos del flavor |
|---|---|---|
| `noche` | `#070F22` | `background`, `earth`, `glacier`, `pier`; todos los `*_casing*` (calles, túneles, puentes); todos los halos (`roads_label_minor_halo`, `roads_label_major_halo`, `subplace_label_halo`, `city_label_halo`, `state_label_halo`, `address_label_halo`) |
| `tinta` | `#0A1A3A` | `other`, `minor_service`, `bridges_other`, `tunnel_other`, `tunnel_minor`, `tunnel_link` |
| `tintaAlta` | `#13284F` | `minor_a`, `minor_b`, `bridges_minor`, `tunnel_major`, `tunnel_highway`, `runway` |
| `lineaNoche` | `#22396A` | `major`, `link`, `bridges_major`, `bridges_link`, `railway` (punteado, opacidad 0.5), `boundaries` |
| `etiquetaCartel` | `#9FB0D0` | `roads_label_major`, `subplace_label` (barrios), `city_label` |
| `tenue` | `#7F8FB3` | `roads_label_minor`, `address_label`, `ocean_label`, `state_label`, `country_label` |

Tonos solo del mapa (no son tokens):

| Nombre | Valor | Campos | Por qué |
|---|---|---|---|
| agua | `#0C1F47` | `water` | Tinta azul profunda: un poco más clara y más azul que `noche`, para que la costa se lea |
| autopista | `#2C4880` | `highway`, `bridges_highway` | Un escalón más claro que `lineaNoche` (rutas y accesos) |
| verde | `#091726` | `park_a`, `park_b`, `wood_a`, `wood_b`, `scrub_a`, `scrub_b` | `noche` apenas corrido hacia el verde: parques casi indistinguibles |
| zona | `#09132A` | `hospital`, `industrial`, `school`, `pedestrian`, `aerodrome`, `zoo`, `military` | `noche` apenas más claro |
| arena | `#10172A` | `sand`, `beach` | Gris azulado apenas más cálido, sin amarillo |
| edificio | `#030814` | `buildings` (el estilo lo pinta con opacidad 0.5) | Más oscuro que `noche`: las manzanas quedan hundidas y las calles se leen |

Esos 12 valores son todos los colores del estilo; la prueba del estilo lo comprueba.

Contrastes WCAG sobre `noche`: etiquetas `etiquetaCartel` 8.72:1 y `tenue` 5.89:1 (las dos ≥ 4.5);
calles `tintaAlta` ≈1.3:1, principales `lineaNoche` 1.69:1, autopistas ≈2.2:1 (decoración, de bajo
contraste a propósito). El ámbar `#FFB21E` sobre `noche` da 10.58:1.

Decisiones del flavor:

- Las etiquetas secundarias (calles menores, direcciones, Río de la Plata, departamentos, países) van
  en `tenue`, no en `etiquetaCartel`, para bajar el ruido de la grilla de Montevideo. Para tenerlas
  todas en `etiquetaCartel`, cambiá esos 5 campos del flavor y regenerá.
- Sin `pois` en el flavor no se genera la capa de puntos de interés.
- `landcover` (z0–7, derivada de ESA WorldCover, CC-BY 4.0) queda fuera del flavor: el estilo no la
  dibuja y no hace falta esa atribución. Los datos siguen dentro del `.pmtiles` en z ≤ 7.

## Procedencia

### `mvd-20261028.pmtiles`

- El build diario de Protomaps más nuevo en `https://build-metadata.protomaps.dev/builds.json` al
  2026-10-28: `https://build.protomaps.com/20261028.pmtiles` (subido 2026-10-28T08:54:55.754Z,
  139 207 195 021 bytes, basemap v4.15.2, b3sum
  `80c033b8056c02392f5362c5d08a1ceee5fdf35ea9657e7d2b1248549feaa777`). Esas URLs desaparecen a la
  semana.
- Datos de OSM al `planetiler:osm:osmosisreplicationtime` 2026-10-28T04:00:00Z (secuencia 123813),
  planetiler 0.10.2.
- Herramienta: go-pmtiles **v1.31.2** (2026-07-22), `go-pmtiles-1.31.2_Darwin_arm64.zip` de
  `https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles-1.31.2_Darwin_arm64.zip`.
  - El release no publica un archivo de checksums. Antes de ejecutar nada, el SHA-256 del zip se
    comparó con el `digest` que GitHub da para ese asset en la API de releases:
    `40528f7f616fcbf91207cd48c8fc023d213f6d86c0cbf1f748732803d1880f3d` (coincide).
  - Binario `pmtiles` (Mach-O arm64) SHA-256
    `9037562a73ae619c67976d50a892566caf72c0323b55e1c3e10598897f35313a`, firmado «Developer ID
    Application: Brandon Liu (WNSC27EEHU)»; `pmtiles version` →
    `pmtiles 1.31.2, commit a3e4951ea6a0477b784c27c1dcbfd9c130878c5a`.

El recorte, tal cual se corrió:

```sh
pmtiles extract https://build.protomaps.com/20261028.pmtiles mvd.pmtiles \
  --bbox=-56.80,-34.97,-55.70,-34.50 --maxzoom=15
# 51 pedidos HTTP, 16 MB transferidos, 7347 teselas direccionadas, 5363 entradas, 5020 contenidos únicos
pmtiles show mvd.pmtiles
pmtiles verify mvd.pmtiles   # «Completed verify», exit 0
cp mvd.pmtiles assets/map/mvd-20261028.pmtiles
```

`pmtiles show`: spec 3, tile type mvt, bounds (-56.80,-34.97)–(-55.70,-34.50), zoom 0–15, center
(-56.25,-34.735), clustered true, **internal compression gzip, tile compression gzip**, name
«Protomaps Basemap», version 4.15.2, attribution `© OpenStreetMap`. El directorio raíz (5363
entradas) entra en los primeros 16 KiB y no hay directorios hoja.

### `style_noche.json`

Paquetes npm, con las versiones fijas de `tool/map/package.json` y `tool/map/package-lock.json`,
instalados con `--ignore-scripts`:

| Paquete | Versión | integrity |
|---|---|---|
| `@protomaps/basemaps` | 5.7.2 | `sha512-K1Yk6bWdULulYg+R2QRVXx4NzJZan5YQhpejEG0c1/sXruJrfPIPZuakpf3jwAgVmjIRVQwAv+yRafDeN0aaUQ==` |
| `@maplibre/maplibre-gl-style-spec` (solo para validar) | 26.4.4 | `sha512-hG4RZR4PBd/+6A3ODdZ3AnQRF106ZQk1y3bhwDg8bH/A4Oz2tnRUJVVWs9BZa6gXZ1d3UKe89C+Mm+olGBELvA==` |

Node v22.22.3, npm 10.9.8. `flavor_noche.json` SHA-256
`765e2ee478511bfbb8fc3d88ec5c29b676a426b996eecf9748e7b9148dd2a60d`.

`gen_style.mjs` llama `layers('protomaps', flavor, {lang: 'es'})`, arma el estilo v8 (nombre «Timbre
Noche», fuente `protomaps`, sin `sprite` ni `glyphs`), lo valida con `validateStyleMin` (0 errores) y lo
escribe minificado. Como no hay sprite, además:

- saca `roads_oneway` (solo dibuja la flecha `arrow`, z ≥ 16) y `roads_shields` (escudos de ruta);
- saca `icon-image`/`icon-size` de `places_locality` (el punto de las localidades en z < 8); el
  texto queda.

Lo que se sacó queda anotado en el `metadata` del estilo. Ninguna capa pide imágenes (0
`icon-image`).

## Cómo regenerar

### El estilo

```sh
cd tool/map
npm ci --ignore-scripts
npm run estilo   # escribe ../../assets/map/style_noche.json y muestra capas, errores y colores
```

`npm run estilo` es `node gen_style.mjs <@protomaps/basemaps dist/esm/index.js>
<@maplibre/maplibre-gl-style-spec dist/index.mjs> flavor_noche.json ../../assets/map/style_noche.json`.
Con estas versiones y este flavor sale el mismo archivo, byte por byte. Después corré
`flutter test test/map/basemap_assets_test.dart` y, si cambió algo a propósito, actualizá esa prueba
y el SHA-256 de este README.

### Las teselas

1. Bajá go-pmtiles (verificá el zip como arriba) y elegí el build más nuevo de
   `https://build-metadata.protomaps.dev/builds.json`.
2. Recortá con el mismo bbox y el mismo zoom máximo, con la fecha del build en el nombre:
   `pmtiles extract https://build.protomaps.com/<AAAAMMDD>.pmtiles mvd-<AAAAMMDD>.pmtiles
   --bbox=-56.80,-34.97,-55.70,-34.50 --maxzoom=15`, y después `pmtiles verify`.
3. Poné el archivo nuevo en `assets/map/` y borrá el viejo, en un commit solo para él.
4. Cambiá el nombre en `Basemap.archiveAsset` (`lib/services/map/basemap.dart`), en `pubspec.yaml` y
   en `test/map/basemap_assets_test.dart`, junto con el SHA-256 y los bordes que comprueba esa prueba.
   Actualizá la procedencia de este README.

En el teléfono, la primera vez que se abre el Mapa con la versión nueva, la app copia el archivo
nuevo y borra la copia vieja.

## Lo que no viaja en la app, y por qué

- **Glifos PBF** (`glyphs/`, ~820 KB de Noto Sans): este motor dibuja el texto con Flutter y nunca
  los lee.
- **`stops.json`** (458 KB, las 4974 paradas): la app no necesita todas las paradas. Las
  coordenadas de las paradas guardadas salen del catálogo de paradas (con el proxy) o del WFS
  `imm:v_uptu_paradas`, pedidas por número (en modo directo), y quedan guardadas en el teléfono.
  Tampoco viaja `build_stops.py`, que solo armaba ese archivo.
- **La vista previa** (`_preview/index.html` con MapLibre GL JS y `serve.mjs`): solo sirvió para
  revisar el estilo en un navegador; no está en el repositorio.
- **`landcover`** y **POI**: el estilo no los dibuja (ver «Decisiones del flavor»).

## Licencias

- **Teselas (`mvd-20261028.pmtiles`)**: obra producida a partir de OpenStreetMap, bajo
  [ODbL](https://opendatacommons.org/licenses/odbl/); agua y costa de osmdata.openstreetmap.de
  (ODbL); Natural Earth (dominio público). La app tiene que mostrar **«© OpenStreetMap»** sobre el
  mapa, siempre visible, sin tocar nada (`Basemap.attribution`, que sale de la fuente del estilo), y
  al tocarlo abrir `https://www.openstreetmap.org/copyright`. La capa `landcover` (ESA WorldCover,
  CC-BY 4.0) viene en el archivo pero no se usa.
- **Estilo (`style_noche.json`, `tool/map/flavor_noche.json`)**: diseño de mapa derivado de
  `@protomaps/basemaps` 5.7.2, cuyo diseño visual es
  [CC0](https://creativecommons.org/publicdomain/zero/1.0/) (el código del paquete es BSD-3-Clause).
  Está modificado y por eso **no se llama Protomaps**, como pide la guía de Protomaps para las
  versiones modificadas: se llama «Timbre Noche». El id `protomaps` de la fuente nombra el esquema de
  las teselas, no el estilo.
- Sin glifos en la app no hace falta la licencia OFL de Noto Sans.
