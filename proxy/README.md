# MVD Transporte proxy

Cloudflare Worker между приложением и API Intendencia de Montevideo. Приложение знает только
маршруты `/v1`; откуда берутся данные, решает прокси. Если источник умрёт (как умер
`stmonlineRest`), чинится сервер, а не выпускается новая версия в сторы.

Источников два:

- `api.montevideo.gub.uy/transporteRest` — открытый бэкенд Cómo Ir, без авторизации: время
  прибытия, остановки, расписания.
- Официальный API `api.montevideo.gub.uy/api/transportepublico` (OAuth2, ключ владельца на
  портале, см. [docs/REVIEW.md](../docs/REVIEW.md) §2.3): снимок всего парка — кондиционер и
  «cero emisiones» к прибывающим автобусам, позиции автобусов линии, каталоги остановок и линий.
  ETA он сейчас не даёт (`upcomingbuses` всегда пуст), поэтому они остаются из `transporteRest`.

Ключ официального API общий на всех пользователей и разрешает **14 запросов в минуту**. Поэтому в
API ходит только один объект — Durable Object `ImGateway` ([src/im_gateway.js](src/im_gateway.js)),
один на весь прокси, из какой бы локации Cloudflare ни пришёл запрос.

## Маршруты

Только `GET`, без query string. Ответы — JSON.

| Маршрут | Ответ | Кэш |
|---|---|---|
| `/v1/stops/{id}` | `{"id":574,"name":"SAN JOSE y ANDES","lines":["116","117"]}` | 24 ч |
| `/v1/stops/{id}/arrivals` | `{"fetchedAt":"<ISO>","arrivals":[…]}` — ближайшие первыми | 15 с |
| `/v1/stops/{id}/schedule/{day}/{H:MM}` | `{"passes":[{"line":"143","destination":"CIUDADELA","time":"8:09","hhmm":809}]}` | 6 ч |
| `/v1/lines/{line}/buses` | `{"fetchedAt":"<ISO>","buses":[…]}` — автобусы линии с GPS | 15 с |
| `/v1/catalog/stops` | `{"fetchedAt":"<ISO>","stops":[{"id":574,"name":"SAN JOSE y ANDES","location":{"lat":…,"lng":…}}]}` — 4 972 остановки, ~520 КБ | 24 ч |
| `/v1/catalog/lines` | `{"fetchedAt":"<ISO>","variants":[{"id":8,"line":"402","origin":"PLAYA MALVÍN","destination":"URUGUAY Y FLORIDA","subline":"CIUDAD VIEJA - MALVIN","special":false}]}` — ~310 КБ | 24 ч |

- `{id}` — код остановки STM, целое без ведущих нулей, до 7 цифр.
- `{day}` — `weekday`, `saturday` или `sunday`; `{H:MM}` — время, с которого нужно ~50 рейсов
  (расписание идёт через полночь).
- `{line}` — как пишет официальный API: `121`, `D10`, `CE1` (цифры и заглавные латинские, до 6).
- Рейс в `arrivals`:

  ```json
  {"line":"121","destination":"PUNTA CARRETAS","etaMinutes":1,"realTime":true,
   "scheduledTime":"20:14","companyId":50,"location":{"lat":-34.907887,"lng":-56.203384},
   "accessible":true,"accessibilityType":2,
   "vehicle":{"airConditioning":true,"zeroEmission":true}}
  ```

  Без GPS (`realTime:false`) — `location:null`, `companyId:null`, `vehicle:null`. `fetchedAt` —
  когда прокси получил данные; из кэша ответ может быть старше на 15 с.
- `vehicle` — комфорт автобуса из официального API. `true` — подтверждено; `null` — нет данных
  («Sin datos»); `zeroEmission:false` — известен класс выбросов (Euro III/V, «Bajas emisiones»).
  `vehicle:null` у автобуса с GPS — комфорт неизвестен: ключ не настроен, лимит исчерпан,
  координатор не ответил за 2 с или автобуса ещё нет в снимке. ETA при этом отдаются всегда.
- Автобус в `buses`:

  ```json
  {"companyId":50,"busId":111,"variantId":2779,"destination":"PUNTA CARRETAS",
   "location":{"lat":-34.909443,"lng":-56.207848},"speedKmh":21,
   "updatedAt":"2026-10-19T22:51:57.000Z","airConditioning":true,"zeroEmission":false}
  ```

  `companyId` — те же коды, что в `arrivals` (10 COETC, 20 COME, 50 CUTCSA, 70 UCOT);
  `variantId` — `lineVariantId` официального API и `shape_id` в GTFS.

Ошибки — `{"error":"<code>"}`:

| Статус | `error` | Когда | Кэш |
|---|---|---|---|
| 400 | `bad_request` | query string, неизвестный `day`, время вне 0:00–23:59 | нет |
| 404 | `not_found` | неизвестный маршрут или некорректный `{id}`/`{line}` | нет |
| 404 | `stop_not_found` | остановки нет в сети STM | 1 ч |
| 405 | `method_not_allowed` | не `GET` | нет |
| 429 | `rate_limited` | превышен лимит по IP, `Retry-After: 60` | нет |
| 502 | `upstream_error` | источник ответил ошибкой или непонятным телом, официальный API отверг секрет | нет |
| 503 | `upstream_busy` | бюджет официального API на эту минуту исчерпан или он ответил 429, `Retry-After` | нет |
| 503 | `not_configured` | нет секретов `IM_CLIENT_ID`/`IM_CLIENT_SECRET` | нет |
| 504 | `upstream_timeout` | `transporteRest` не ответил за 8 с, официальный API — за 10 с | нет |

## ImGateway: ключ на всех

- **Сон.** Без таймеров и сокетов объект засыпает через 10 с без запросов и теряет память
  (документация Cloudflare, «Durable Object Lifecycle»). Поэтому всё, что должно пережить сон, —
  в его хранилище (SQLite).
- **Бюджет** — 12 запросов в минуту, окно с :00, как у IM; 2 оставлены владельцу для ручных
  проверок тем же ключом. Сверх бюджета или после `429` объект не ходит в API до конца окна.
  Счётчик хранится в хранилище (одна запись на запрос к API), иначе после сна он начинался бы с нуля.
- **Токен** живёт 5 минут и переиспользуется; на `401`/`403` берётся новый один раз.
- **Снимок парка** (`GET /buses`, ~4 с) — один на всех. Свежим считается 15 с; старше —
  отдаётся сразу, а новый грузится в фоне. Несколько одновременных запросов вызывают одну загрузку.
  Поэтому к API уходит не больше 4 снимков в минуту и только пока есть запросы.
- **Комфорт** (кондиционер, «cero emisiones») — свойство машины: у 842 автобусов между двумя
  снимками он не менялся. Объект накапливает его по всем снимкам и раз в 5 минут сохраняет в
  хранилище (≤ 288 записей в сутки). После сна первый запрос отвечается из хранилища, а снимок
  догружается в фоне (проверено: после 12–25 с простоя ответ < 1 с, комфорт у всех автобусов с
  GPS). Без комфорта остаётся только самый первый запрос после деплоя.
- **Каталоги** — раз в сутки, при ошибке отдаётся копия до 7 дней.

## Кэш и лимит

- **Workers Caching** (`"cache": {"enabled": true}` в `wrangler.jsonc`): Cloudflare проверяет
  кэш до запуска Worker и хранит ответ столько, сколько сказано в его `Cache-Control`.
  Одновременные промахи по одному URL выполняют Worker один раз — тысяча человек на одной
  остановке дают один запрос к IMM раз в 15 с на дата-центр. Кэш свой у каждой версии Worker:
  после деплоя он пустой.
- **Лимит по IP** — 300 запросов в минуту (`ratelimits` в `wrangler.jsonc`), считается в
  каждой локации Cloudflare отдельно и **только на промахах кэша**: попадания отдаются без
  запуска Worker и до IMM не доходят. Лимит защищает источники, а не тариф Cloudflare: запрос,
  получивший 429, тоже оплачивается.
- Документация Cloudflare не рекомендует ключ по IP: мобильные операторы сажают много абонентов
  на один адрес (CGNAT). Отсюда щедрый лимит: одному пользователю нужно ~2 запроса в минуту на
  остановку (обновление раз в 30 с), 300 — запас на десятки абонентов за одним IP. Если
  пользователи начнут получать 429 — поднять `limit`.

## Запуск

Нужен Node.js 22+.

```bash
npm install
```

```bash
npm test
```

Для локального сервера положите ключ портала в `proxy/.dev.vars` (файл в `.gitignore`):

```
IM_CLIENT_ID=<ID de cliente>
IM_CLIENT_SECRET=<Secreto del Cliente>
```

Без него всё работает, кроме данных официального API (`vehicle:null`, `503 not_configured`).
Локальный сервер на `http://127.0.0.1:8787` ходит в настоящие источники и тратит тот же бюджет
14 запросов в минуту. Лимит и Durable Object работают локально, кэш — нет (`wrangler dev` не отдаёт
`Cf-Cache-Status`): кэш проверяется после деплоя.

```bash
npm run dev
```

Приложение на симуляторе iOS ходит в него так:

```bash
flutter run --dart-define=MVD_PROXY_URL=http://127.0.0.1:8787
```

## Деплой

Один раз — вход в аккаунт Cloudflare (откроется браузер):

```bash
npx wrangler login
```

Один раз — ключ портала в секреты Worker (Wrangler спросит значение):

```bash
npx wrangler secret put IM_CLIENT_ID
```

```bash
npx wrangler secret put IM_CLIENT_SECRET
```

```bash
npm run deploy
```

Wrangler напечатает адрес вида `https://mvd-transporte-proxy.<subdomain>.workers.dev`.
Первый деплой создаёт Durable Object `ImGateway` (миграция `v1` в `wrangler.jsonc`).
Проверка кэша — два запроса подряд, во втором `cf-cache-status: HIT`:

```bash
curl -sI https://mvd-transporte-proxy.<subdomain>.workers.dev/v1/stops/3140/arrivals
```

Проверка официального API — у автобусов с GPS появляется `vehicle` (первый запрос после деплоя
может прийти без него):

```bash
curl -s https://mvd-transporte-proxy.<subdomain>.workers.dev/v1/lines/117/buses
```

Сборки приложения для сторов — с этим адресом:

```bash
flutter build appbundle --dart-define=MVD_PROXY_URL=https://mvd-transporte-proxy.<subdomain>.workers.dev
```

Если секрет перевыпущен на портале («Regenerar»), повторить `wrangler secret put IM_CLIENT_SECRET`:
до этого прокси отвечает без комфорта, а `/v1/lines`, `/v1/catalog` — `502`.

Бесплатный тариф Workers — 100 000 запросов в сутки (сброс в 00:00 UTC), сверх лимита
Cloudflare отвечает ошибкой 1027, и приложение покажет «не удалось проверить». С включённым
кэшем попадания тоже считаются запросами, но не тратят CPU. Durable Objects на бесплатном тарифе —
только с SQLite-хранилищем (так и настроено), 100 000 записанных строк в сутки: `ImGateway` пишет
не больше 12 в минуту (≤ 17 280 в сутки при непрерывной нагрузке). Запрос к `ImGateway` идёт на
каждом промахе кэша `arrivals` с автобусами с GPS и на `/v1/lines`, `/v1/catalog`.

## Приватность

Прокси видит IP клиента и номера остановок. В коде IP используется только как ключ лимита и
нигде не сохраняется; в `ImGateway` IP не попадает вовсе — туда идут только номера автобусов.
В лог (`console.error`) пишутся только путь к источнику и текст ошибки. Workers Logs в
`wrangler.jsonc` не включены — прежде чем включать, проверить, что они записывают о запросах.
Политика конфиденциальности и раздел Data safety обновлены под прокси:
[docs/privacy-policy.md](../docs/privacy-policy.md), [docs/store-listing.md](../docs/store-listing.md).
