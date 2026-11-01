# Contrato /v1: archivos compartidos

Esta carpeta es el contrato /v1 en forma de datos: la usan las pruebas del
proxy (JavaScript) y las de la app (Dart). Si un lado cambia y el otro no, el
otro se pone en rojo.

Acá solo está la mecánica. Qué devuelve cada ruta, las reglas de derivación,
los errores, la caché, la privacidad y el orden de despliegue están en
[docs/design/contrato-v1.md](../../../docs/design/contrato-v1.md).

## Qué hay

```
cases.json          casos compartidos: pedido, upstream simulado, respuesta esperada
direct_masks.json   campos que el modo directo puede no tener
responses/          cuerpos /v1 esperados (goldens), escritos a mano
upstream/           capturas crudas de las fuentes, con fecha
  transporte_rest/    transporteRest: lineas, siguientesParada, horarios (2026-10-19)
  im_api/             API oficial de la IM: buses, busstops, linevariants (2026-10-19)
  im_gateway/         respuestas internas del Durable Object, escritas a mano
  geoserver/          muestra del índice de paradas WFS en CSV (2026-10-27)
  notificacion/       páginas de notificacion/mensajes desde 0, 136, 168 y 172 (2026-10-27)
  pci/                pci buses/control (2026-10-27)
vectors/            entradas y salidas de cada regla de derivación
```

## Cómo la usa cada lado

Cada caso se prueba por tres lados:

1. **Proxy** (`proxy/test/contract.test.js`): simula las fuentes con
   `upstream`, llama al Worker con `request` y exige:
   - el `status` y el `Cache-Control` exactos;
   - `Content-Type: application/json; charset=utf-8`;
   - los encabezados de `headers`;
   - el cuerpo igual a `response`;
   - las URLs pedidas iguales a las de `upstream`.
2. **App en modo directo** (`test/contract/contract_test.dart`): `DirectSource`
   recibe las mismas capturas. Su JSON v1 tiene que ser igual a `response` con
   la máscara de `direct.mask` aplicada. Las URLs pedidas tienen que ser las de
   `direct.upstream`, y un caso de error tiene que dar `direct.failure`.
3. **App en modo proxy** (el mismo archivo): se sirve `response` con `status` y
   `headers` en `https://proxy.test{request}`. `V1Parser` tiene que dar el
   modelo, o el `ApiFailure` de `dart.failure` con `dart.retryAfter`.

Los vectores los corren `proxy/test/rules.test.js` y
`test/contract/rules_test.dart`. Las pruebas de Dart leen esta carpeta por ruta
relativa: corré `flutter test` desde la raíz del repo.

### `fetchedAt`

Los goldens lo traen con un valor de ejemplo. Los dos lados lo sacan de los
dos cuerpos antes de comparar, y aparte verifican que el del cuerpo real tenga
el formato `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`.

### URLs pedidas

Se comparan como texto exacto, sin normalizar (`imm:v_uptu_paradas` no es
`imm%3Av_uptu_paradas`). Se comparan como multiconjunto: se ordenan las dos
listas antes de comparar, porque algunas rutas piden en paralelo. Cada pedido
aparece una vez por cada vez que se hace.

## Formato de `cases.json`

Una lista de casos. Cada caso tiene todos estos campos:

| Campo | Significado |
|---|---|
| `id` | Nombre único, `grupo.detalle`. |
| `request` | Ruta pedida al Worker, siempre con GET. |
| `gateway` | `none`: el Worker no tiene el binding `IM_GATEWAY`. `fake`: el Durable Object se simula con las entradas `https://im-gateway/…` de `upstream`; si el Worker lo llama con otra URL, el caso falla. `real`: un `ImGateway` de verdad, con secretos de prueba y almacenamiento en memoria; sus pedidos al token, a la API de la IM y a geoserver salen por el `fetch` simulado. |
| `status` | Status HTTP exacto. |
| `cacheControl` | `Cache-Control` exacto. |
| `headers` | Otros encabezados de la respuesta que tienen que coincidir exactos, por ejemplo `Retry-After`. `{}` si no hay. |
| `response` | El golden, relativo a esta carpeta. Los errores usan `responses/error_<código>.json`. |
| `upstream` | Cada pedido que sale de lo que se prueba (ver abajo). `[]` si no sale ninguno. |
| `direct` | `null` si la app no tiene equivalente en modo directo. Si no: `upstream` (URLs que pide `DirectSource`, que se responden con las entradas de `upstream` de la misma URL), `mask` (máscaras de esta carpeta) y `failure` (`ApiFailure` esperado, o `null`). |
| `dart` | `null` si la app nunca arma ese pedido (rutas quitadas, hora no canónica, día desconocido). Si no: `failure` (`ApiFailure` esperado, o `null`), `retryAfter` (segundos, o `null`) y `request` (`false` cuando la app no tiene que hacer ningún pedido, en ningún modo). |

Una entrada de `upstream` tiene la `url` exacta y una sola de estas claves:

- `file`: el cuerpo es ese archivo, relativo a esta carpeta;
- `body`: el cuerpo es ese texto;
- `throw: "timeout"`: el pedido falla por tiempo. En JS es un `DOMException`
  llamado `TimeoutError`; en Dart, un `TimeoutException`.

Puede tener además `status` (200 si falta) y `headers`.

Con `gateway: "fake"`, los pedidos internos al Durable Object
(`https://im-gateway/…`) también se listan. Con `real` no se listan, porque el
Durable Object es parte de lo que se prueba.

Los códigos `method_not_allowed` y `rate_limited` no tienen caso: se prueban
con las tablas de `proxy/test/index.test.js`, igual que la query string.
`internal_error` tampoco tiene caso.

## Máscaras

`direct_masks.json` lista las únicas máscaras permitidas. Los dos lados
verifican que las de cada caso estén en esa lista.

- `arrivals[].campo`: en cada elemento de `arrivals`, ese campo pasa a `null`.
- `campo`: si en el golden es una lista, pasa a `[]`; si no, a `null`.

## Vectores

Cada archivo de `vectors/` tiene esta forma:

```json
{"rule": "nombreDeLaRegla", "notes": ["…"], "cases": [{"in": …, "out": …}]}
```

`notes` explica la regla y las decisiones que fijan los casos. Las dos
implementaciones (`proxy/src/rules.js` y `lib/services/api/contract_rules.dart`)
tienen que dar `out` para cada `in`.

| Archivo | Regla | `in` | `out` |
|---|---|---|---|
| `int_coercion.json` | `toIntLoose` | cualquier valor JSON | entero o `null` |
| `text_trim.json` | `trimText` | texto | texto |
| `line_order.json` | `compareLines` | lista de líneas | la lista ordenada |
| `stop_name.json` | `stopName` | `[calle, esquina]` | texto o `null` |
| `arrival.json` | `arrival` | `{row, fetchedAt}` | elemento de `arrivals` o `null` |
| `news_link.json` | `newsLink` | texto o `null` | texto o `null` |
| `gps_status.json` | `gpsOperator` | elemento crudo de pci | `{company, percent, partial}` o `null` |
| `stop_id.json` | `stopId` | entero | `true` o `false` |
| `schedule_path.json` | `schedulePath` | `{stopId, day, hour, minute}` | `{proxyPath, directUrl}` |

## Capturas

- Las capturas de `transporte_rest/` e `im_api/` son las que antes estaban en
  `proxy/test/fixtures/`. Las de `notificacion/` y `pci/` son respuestas en vivo
  del 2026-10-27.
- `geoserver/stop_index_sample.csv` trae filas de las paradas 546, 574, 3140 y
  6325, las mismas de `im_api/im_busstops.json`:
  - las de 574 vienen de una consulta con `cod_variante`;
  - las otras vienen del volcado completo, sin `cod_variante`.
  La columna `ordinal` sobra a propósito: el lector tiene que tolerar columnas
  de más. Las líneas terminan en CRLF, como las manda geoserver.
- `im_gateway/` se escribió a mano a partir de `im_api/` y `geoserver/`.
- Todos los archivos están en UTF-8. En Dart, servilos como bytes UTF-8
  (`http.Response.bytes`), no como `String`.
- No se guarda ningún encabezado de las fuentes (por ejemplo, las cookies de F5).

## Para cambiar el contrato

1. Cambiá primero `docs/design/contrato-v1.md`.
2. Escribí a mano el golden en `responses/` y verificalo contra `upstream/`.
3. Si cambia una regla, cambiá sus vectores en el mismo commit que las dos
   implementaciones.
4. Agregá o ajustá casos en `cases.json`: al menos uno por ruta nueva y uno
   por código de error nuevo.
5. Corré los dos lados: `cd proxy && npm test`, y `flutter test` desde la raíz.
6. Una máscara nueva va en `direct_masks.json`, con su motivo en
   `contrato-v1.md`.

## Evolución

Mientras no haya una versión pública, /v1 puede cambiar en el lugar. Desde la
primera versión pública, /v1 solo suma campos o rutas; lo que rompa va a /v2.
