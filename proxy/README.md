# Proxy de MVD Transporte

Worker de Cloudflare entre la app y las fuentes de la Intendencia de Montevideo. La app solo
conoce las rutas `/v1`; de dónde sale cada dato lo decide el proxy. Si una fuente se muere (como
pasó con `stmonlineRest`), se arregla el servidor y no hace falta sacar otra versión en las
tiendas.

## Fuentes

- `api.montevideo.gub.uy/transporteRest`: el backend abierto de Cómo Ir, sin credenciales.
  Arribos, nombre y líneas de cada parada, horarios.
- La API oficial `api.montevideo.gub.uy/api/transportepublico` (OAuth2, con la clave del dueño en
  el portal, ver [docs/REVIEW.md](../docs/REVIEW.md) §2.3): la flota entera (aire acondicionado y
  «cero emisiones» de cada ómnibus), el catálogo de paradas y las variantes de línea. Hoy no da
  tiempos de llegada (`upcomingbuses` viene siempre vacío), por eso salen de transporteRest.
- geoserver, capa WFS `imm:v_uptu_paradas`, sin credenciales: las líneas y variantes de cada
  parada, en un CSV de toda la capa (~2,5 MB) una vez por día.
- `api.montevideo.gub.uy/notificacion`: las novedades que muestra Cómo Ir.
- `pci.montevideo.gub.uy/buses/control`: qué parte de los ómnibus de cada empresa manda GPS.

La clave de la API oficial es una sola para todos los usuarios y permite **14 pedidos por
minuto**. Por eso la usa un solo objeto: el Durable Object `ImGateway`
([src/im_gateway.js](src/im_gateway.js)), uno para todo el proxy, venga de donde venga el pedido.
A geoserver también lo llama `ImGateway`, pero sin la clave y sin gastar ese presupuesto.

## Rutas

Solo `GET`, sin query string. Todas las respuestas son JSON (`application/json; charset=utf-8`).

Este README no repite las formas: el contrato está en [contract/v1/](contract/v1/README.md). Ahí
están los cuerpos esperados de cada ruta (`responses/`), las capturas de las fuentes y los casos
que corren las pruebas del proxy y las de la app.

| Ruta | Qué devuelve | Caché |
|---|---|---|
| `/v1/stops/{id}` | nombre, líneas y a dónde va cada una (`directions`) | 24 h; 5 min si todavía no se sabe a dónde van |
| `/v1/stops/{id}/arrivals` | los próximos ómnibus, el más cercano primero: `tripId`, `state`, `expectedAt`, `clockTime`, confort | 15 s |
| `/v1/stops/{id}/schedule/{day}/{H:MM}` | ~50 pasadas del horario teórico desde esa hora | 6 h |
| `/v1/catalog/stops` | todas las paradas (~4 970) con ubicación y líneas, y `linesAvailable` | 24 h; 15 min sin líneas |
| `/v1/news` | las 10 novedades más nuevas | 5 min |
| `/v1/status/gps` | el porcentaje de ómnibus con GPS de cada empresa; `partial` debajo de 70 % | 1 min |

- `{id}`: el código de parada STM, entero sin ceros adelante, de 1 a 9 999 999.
- `{day}`: `weekday`, `saturday` o `sunday`. `{H:MM}`: la hora canónica, `8:05` (no `08:05` ni
  `8:5`), así cada minuto es una sola clave de caché. El horario sigue después de medianoche.
- `fetchedAt` es el reloj del Worker cuando contestó la fuente. Desde la caché puede tener la
  antigüedad del TTL.
- `/v1/lines/{line}/buses` y `/v1/catalog/lines` ya no son públicas (responden 404): la app nunca
  las usó. `ImGateway` las mantiene como rutas internas.

Los errores son `{"error":"<código>"}`:

| Status | `error` | Cuándo | Caché |
|---|---|---|---|
| 400 | `bad_request` | query string, `day` desconocido, hora mayor que 23 | no |
| 404 | `not_found` | ruta desconocida, `{id}` inválido, hora no canónica | no |
| 404 | `stop_not_found` | la parada no existe en la red STM | 1 h |
| 405 | `method_not_allowed` | no es `GET` (`Allow: GET`) | no |
| 429 | `rate_limited` | se pasó el límite por IP; `Retry-After: 60` | no |
| 500 | `internal_error` | un error inesperado del proxy | no |
| 502 | `upstream_error` | la fuente contestó un error o algo que no se entiende (también pci con una lista vacía), o la API oficial rechazó el secreto | no |
| 503 | `upstream_busy` | se terminó el presupuesto de la API oficial en este minuto, o contestó 429; `Retry-After` | no |
| 503 | `not_configured` | faltan los secretos `IM_CLIENT_ID`/`IM_CLIENT_SECRET` o el binding `IM_GATEWAY` | no |
| 504 | `upstream_timeout` | la fuente no contestó a tiempo: transporteRest 8 s, notificacion 5 s por página, pci 5 s, API oficial 10 s | no |

Un error de una fuente nunca se devuelve como una lista vacía.

## ImGateway: una clave para todos

- **Hibernación.** Sin timers ni sockets, el objeto se duerme a los 10 s sin pedidos y pierde la
  memoria (documentación de Cloudflare, «Durable Object Lifecycle»). Todo lo que tiene que
  sobrevivir va a su almacenamiento (SQLite).
- **Presupuesto.** 12 pedidos por minuto, con la ventana desde :00 como la de la IM; quedan 2 para
  que el dueño pruebe a mano con la misma clave. Pasado el presupuesto, o después de un `429`, el
  objeto no llama a la API hasta que termine la ventana. El contador se guarda (una escritura por
  pedido a la API); si no, después de dormirse empezaría de cero.
- **Token.** Vive 5 minutos y se reutiliza; ante un `401`/`403` se pide uno nuevo, una sola vez.
  Los pedidos que lo necesitan a la vez comparten uno.
- **Flota** (`GET /buses`, ~4 s). Una para todos. Se considera fresca 15 s; más vieja se sirve en
  el momento y se carga otra en segundo plano. Varios pedidos a la vez disparan una sola carga.
  Así a la API llegan como mucho 4 flotas por minuto, y solo mientras hay pedidos.
- **Confort** (aire acondicionado, «cero emisiones»). Es del vehículo: en 842 ómnibus no cambió
  entre dos fotos de la flota. El objeto lo junta de todas las flotas y lo guarda cada 5 minutos
  (≤ 288 escrituras por día). Después de dormirse, el primer pedido sale del almacenamiento y la
  flota se carga en segundo plano (verificado: tras 12–25 s sin pedidos, respuesta en menos de 1 s
  con el confort de todos los ómnibus con GPS). Solo el primer pedido después de un deploy llega
  sin confort.
- **Catálogos** (paradas y variantes de línea). Una vez por día; si falla la carga, se sirve una
  copia de hasta 7 días.
- **Índice de paradas.**
  - Sale del CSV de geoserver: las líneas de cada parada y sus variantes (`cod_variante`, que es
    el `lineVariantId` de la API oficial). Con las variantes de línea de la API oficial (1 pedido)
    arma `directions`: una por línea y destino, con sus `variantIds`.
  - El pedido a geoserver no pasa por la clave: no usa token, no gasta presupuesto y anda aunque
    la API esté bloqueada.
  - Se arma como mucho una vez por día, una sola vez aunque lleguen muchos pedidos juntos. Se sirve
    hasta 7 días y, pasadas 24 h, se rearma en segundo plano. Si el armado falla, se reintenta a
    los 15 minutos. Si fallaron solo las variantes, queda guardado como incompleto (sin
    `directions`) y también se reintenta a los 15 minutos.
  - Se guarda en 64 partes (`stopmeta:{id % 64}`) más `stopmeta:info`: unas 65 escrituras por
    armado. Después de dormirse, la metadata de una parada se lee de una parte, sin ningún pedido.
  - `/v1/catalog/stops` espera hasta 20 s el primer armado. Si no hay índice, contesta
    `linesAvailable: false` con `lines: []` en cada parada, y el Worker lo guarda 15 minutos en
    vez de un día.
  - `/v1/stops/{id}` pide la metadata en paralelo con transporteRest y la espera como mucho 2 s.
    Si falla, tarda o está incompleta, contesta `directions: []` con 5 minutos de caché, y la app
    arma los destinos con los arribos, como antes.

En el peor caso se gastan 4 (flota) + 1 (paradas) + 1 (variantes) = 6 unidades por minuto, debajo
de las 12 del presupuesto.

## Caché y límite

- **Workers Caching** (`"cache": {"enabled": true}` en `wrangler.jsonc`): Cloudflare mira la
  caché antes de correr el Worker y guarda cada respuesta lo que diga su `Cache-Control`. Varios
  pedidos a la misma URL que no están en caché corren el Worker una sola vez: mil personas en la
  misma parada dan un pedido a la IM cada 15 s por centro de datos. Cada versión del Worker tiene
  su propia caché: después de un deploy arranca vacía.
- **Límite por IP**: 300 pedidos por minuto (`ratelimits` en `wrangler.jsonc`), contado en cada
  ubicación de Cloudflare por separado y **solo cuando no hay caché**: los aciertos se contestan
  sin correr el Worker y no llegan a la IM. El límite protege a las fuentes, no el plan de
  Cloudflare: un pedido que recibe 429 también se cobra.
- La documentación de Cloudflare no recomienda usar la IP como clave: las compañías de celular
  ponen a muchos clientes detrás de una misma dirección (CGNAT). Por eso el límite es generoso: un
  usuario necesita ~2 pedidos por minuto por parada (actualiza cada 30 s), y 300 alcanzan para
  decenas detrás de una misma IP. Si los usuarios empiezan a recibir 429, subí `limit`.

## Privacidad: logs apagados

- **Regla: los logs del Worker están apagados.** `wrangler.jsonc` no tiene bloque
  `observability`, y no hay que agregarlo: Workers Logs guardaría cada pedido, con la ruta (que
  lleva el número de parada) y la IP. Antes de prender cualquier registro, fijate qué guarda.
- Lo único que se escribe (`console.error`) son textos fijos `<fuente>: <tipo>`, por ejemplo
  `transporteRest: HTTP 500`, `geoserver: TimeoutError` o `internal: TypeError`: sin URL, sin ruta
  y sin IP.
- El proxy ve la IP del cliente y los números de parada. La IP solo sirve de clave para el límite
  y no se guarda. A `ImGateway` no llega: ahí van solo números de ómnibus y de parada.
- Ningún encabezado de las fuentes llega al cliente (por ejemplo, las cookies de F5).
- Las versiones de la app con proxy no mandan coordenadas a ningún lado: «Paradas cercanas» se
  calcula en el teléfono con el catálogo.
- La política de privacidad y la sección Data safety de las tiendas:
  [docs/privacy-policy.md](../docs/privacy-policy.md), [docs/store-listing.md](../docs/store-listing.md).

## Pruebas

Hace falta Node.js 22 o más nuevo. Las pruebas no tienen dependencias:

```bash
npm test
```

- `test/contract.test.js` corre los casos compartidos con la app (`contract/v1/cases.json`):
  status y `Cache-Control` exactos, cuerpo igual al esperado y URLs pedidas a las fuentes.
- `test/rules.test.js` corre los vectores de cada regla de derivación (`contract/v1/vectors/`),
  los mismos que corre la app.
- Para cambiar el contrato, seguí la lista de [contract/v1/README.md](contract/v1/README.md).

## Correrlo en tu máquina

```bash
npm install
```

Para la API oficial, poné la clave del portal en `proxy/.dev.vars` (el archivo está en
`.gitignore`):

```
IM_CLIENT_ID=<ID de cliente>
IM_CLIENT_SECRET=<Secreto del Cliente>
```

Sin la clave anda todo menos lo de la API oficial: el confort viene en `null`, el catálogo da
`503 not_configured` y las paradas salen sin `directions` (5 minutos de caché). El servidor local
en `http://127.0.0.1:8787` usa las fuentes de verdad y gasta el mismo presupuesto de 14 pedidos
por minuto. El límite y el Durable Object funcionan en local; la caché no (`wrangler dev` no
manda `Cf-Cache-Status`), así que la caché se prueba después del deploy.

```bash
npm run dev
```

La app en el simulador de iOS lo usa así:

```bash
flutter run --dart-define=MVD_PROXY_URL=http://127.0.0.1:8787
```

## Prueba de humo

`scripts/smoke.js` pide cada ruta de los casos del contrato que contestan 200 y verifica el status,
el `Cache-Control`, el `Content-Type` y las claves del cuerpo contra los esperados. Los valores no
los compara, porque son datos en vivo. No necesita dependencias:

```bash
node scripts/smoke.js http://127.0.0.1:8787
```

Al lado de cada ruta muestra con qué caso coincidió. `stop.574.degraded` o `catalog.nolines`
quieren decir que el proxy anda, pero sin `directions` o sin líneas. Contra `wrangler dev` las
fuentes ven tu IP, así que no prueba nada sobre F5/BigIP: lo que importa es correrlo contra el
Worker desplegado.

## Deploy

### Orden: proxy primero

1. Desplegá el proxy (pasos abajo).
2. Corré `node scripts/smoke.js https://mvd-transporte-proxy.<subdominio>.workers.dev`. Si delante
   de geoserver, notificacion o pci hay un F5/BigIP que bloquea las IP de Cloudflare, acá se ve:
   las novedades y el GPS dan 502, el catálogo sale sin líneas y las paradas sin `directions`.
3. Recién después, las versiones de la app con `MVD_PROXY_URL` apuntando a ese Worker.

### Pasos

Una sola vez, entrá a la cuenta de Cloudflare (se abre el navegador):

```bash
npx wrangler login
```

Una sola vez, guardá la clave del portal en los secretos del Worker (Wrangler pide el valor):

```bash
npx wrangler secret put IM_CLIENT_ID
```

```bash
npx wrangler secret put IM_CLIENT_SECRET
```

```bash
npm run deploy
```

Wrangler muestra una dirección del tipo `https://mvd-transporte-proxy.<subdominio>.workers.dev`.
El primer deploy crea el Durable Object `ImGateway` (migración `v1` en `wrangler.jsonc`). Para
probar la caché, pedí dos veces seguidas; la segunda tiene que traer `cf-cache-status: HIT`:

```bash
curl -sI https://mvd-transporte-proxy.<subdominio>.workers.dev/v1/stops/3140/arrivals
```

Para probar la API oficial, los ómnibus con GPS tienen que traer `airConditioning` y
`zeroEmission` (el primer pedido después del deploy puede venir sin ellos):

```bash
curl -s https://mvd-transporte-proxy.<subdominio>.workers.dev/v1/stops/574/arrivals
```

Las versiones para las tiendas se compilan con esa dirección:

```bash
flutter build appbundle --dart-define=MVD_PROXY_URL=https://mvd-transporte-proxy.<subdominio>.workers.dev
```

Si regenerás el secreto en el portal («Regenerar»), repetí `wrangler secret put IM_CLIENT_SECRET`.
Mientras tanto el proxy contesta sin confort y el catálogo da `502`; desde el próximo armado del
índice, las paradas salen sin `directions`.

### Límites del plan gratis

- Workers: 100 000 pedidos por día (se reinicia a las 00:00 UTC). Pasado eso, Cloudflare contesta
  el error 1027 y la app muestra su error genérico. Con la caché prendida, los aciertos también
  cuentan como pedidos, pero no gastan CPU.
- Durable Objects: en el plan gratis solo con almacenamiento SQLite (así está configurado) y
  100 000 filas escritas por día. `ImGateway` escribe una por pedido a la API (≤ 12 por minuto,
  ≤ 17 280 por día con carga continua), ≤ 288 por día de confort y ~65 por armado del índice de
  paradas.
- Se llama a `ImGateway` en cada pedido sin caché de arribos con ómnibus con GPS, de
  `/v1/stops/{id}` y de `/v1/catalog/stops`.
- El CSV de geoserver se lee dentro del Durable Object: ~50 ms de CPU en Node la primera vez
  (2026-10-27). Medilo después del deploy.
