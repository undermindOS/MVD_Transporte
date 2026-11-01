# Cómo rearmar `assets/rutas/horarios.bin`

`build_horarios.py` arma el horario del planificador de viajes a partir de tres fuentes abiertas de
la Intendencia de Montevideo (detalle, fechas y licencia en `assets/rutas/README.md`). Usa solo la
biblioteca estándar de Python 3; corrélo con `python3 -I` (no carga nada de la carpeta en la que
estás ni de la de los datos).

## 1. Bajá las fuentes

En una carpeta nueva y vacía, fuera del repositorio. Con `--download` el script las baja él mismo
(con el User-Agent `MVD-Transporte (github.com/undermindOS/MVD_Transporte)`) y toma la fecha de la
fuente del `Last-Modified` del zip:

```sh
python3 -I tool/rutas/build_horarios.py --download /tmp/rutas-$(date +%Y%m%d) \
    --out assets/rutas/horarios.bin
```

O a mano, con las mismas URL:

```sh
mkdir /tmp/rutas && cd /tmp/rutas
UA='MVD-Transporte (github.com/undermindOS/MVD_Transporte)'
WFS='https://geoserver.montevideo.gub.uy/geoserver/ows?service=wfs&version=2.0.0&request=GetFeature&outputFormat=application/json'
curl -A "$UA" -o uptu_pasada_variante.zip \
    https://datos-abiertos.montevideo.gub.uy/uptu_pasada_variante.zip
curl -A "$UA" -o wfs_v_uptu_lsv_destinos.json \
    "$WFS&typeNames=imm:v_uptu_lsv_destinos&propertyName=cod_variante,desc_linea,desc_variante"
curl -A "$UA" -o wfs_v_uptu_paradas.json \
    "$WFS&typeNames=imm:v_uptu_paradas&srsName=EPSG:4326&propertyName=cod_ubic_parada,calle,esquina,the_geom"
```

El zip pesa unos 10,6 MB, la capa de paradas unos 11 MB y la de variantes 0,3 MB.

## 2. Armá el archivo

```sh
cd -  # de vuelta en el repositorio
python3 -I tool/rutas/build_horarios.py \
    --pasadas /tmp/rutas/uptu_pasada_variante.zip \
    --destinos /tmp/rutas/wfs_v_uptu_lsv_destinos.json \
    --paradas /tmp/rutas/wfs_v_uptu_paradas.json \
    --out assets/rutas/horarios.bin
```

Sin `--source-date`, la fecha de la fuente es la del CSV dentro del zip; sin `--built-at`, la de
hoy. Tarda unos 5 segundos. Al final cuenta, en la salida de error, qué guardó, qué descartó y qué
reparó (filas por tipo de día, colas pegadas, paradas sin coordenadas, rutas, bytes).

Con las mismas fuentes y las mismas fechas el archivo sale idéntico byte a byte (gzip sin hora).

## 3. Después

- Actualizá la tabla, las fechas y los números de `assets/rutas/README.md`.
- Corré `flutter test test/rutas/`: la prueba del archivo real arma un viaje de Pocitos a Ciudad
  Vieja y tiene que encontrar al menos dos opciones.
- Si cambia el formato, subí `VERSION` en el script y `TransitData.version` en
  `lib/services/rutas/transit_data.dart`, y rearmá también el archivo de prueba:

```sh
python3 -I tool/rutas/build_horarios.py --pasadas test/fixtures/rutas/pasadas_mini.csv \
    --destinos test/fixtures/rutas/destinos_mini.json \
    --paradas test/fixtures/rutas/paradas_mini.json \
    --out test/fixtures/rutas/horarios_mini.bin --built-at 20261101 --source-date 20261031
```
