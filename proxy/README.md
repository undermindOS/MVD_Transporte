# MVD Transporte proxy

Cloudflare Worker между приложением и API Intendencia de Montevideo. Приложение знает только
маршруты `/v1`; откуда берутся данные, решает прокси. Если источник умрёт (как умер
`stmonlineRest`), чинится сервер, а не выпускается новая версия в сторы.

Сейчас источник один — `api.montevideo.gub.uy/transporteRest` (открытый бэкенд Cómo Ir, без
авторизации). Переход на официальный OAuth-API (`/api/transportepublico`, см.
[docs/REVIEW.md](../docs/REVIEW.md) §2.3) — следующий шаг: секрет будет жить только в
секретах Worker, контракт `/v1` для приложения не изменится.

## Маршруты

Только `GET`, без query string. Ответы — JSON.

| Маршрут | Ответ | Кэш |
|---|---|---|
| `/v1/stops/{id}` | `{"id":574,"name":"SAN JOSE y ANDES","lines":["116","117"]}` | 24 ч |
| `/v1/stops/{id}/arrivals` | `{"fetchedAt":"<ISO>","arrivals":[…]}` — ближайшие первыми | 15 с |
| `/v1/stops/{id}/schedule/{day}/{H:MM}` | `{"passes":[{"line":"143","destination":"CIUDADELA","time":"8:09","hhmm":809}]}` | 6 ч |

- `{id}` — код остановки STM, целое без ведущих нулей, до 7 цифр.
- `{day}` — `weekday`, `saturday` или `sunday`; `{H:MM}` — время, с которого нужно ~50 рейсов
  (расписание идёт через полночь).
- Рейс в `arrivals`:

  ```json
  {"line":"494","destination":"DELTA DEL TIGRE","etaMinutes":8,"realTime":true,
   "scheduledTime":"19:06","companyId":10,"location":{"lat":-34.897755,"lng":-56.12432},
   "accessible":false,"accessibilityType":1}
  ```

  Без GPS (`realTime:false`) — `location:null`, `companyId:null`. `fetchedAt` — когда прокси
  получил данные; из кэша ответ может быть старше на 15 с.

Ошибки — `{"error":"<code>"}`:

| Статус | `error` | Когда | Кэш |
|---|---|---|---|
| 400 | `bad_request` | query string, неизвестный `day`, время вне 0:00–23:59 | нет |
| 404 | `not_found` | неизвестный маршрут или некорректный `{id}` | нет |
| 404 | `stop_not_found` | остановки нет в сети STM | 1 ч |
| 405 | `method_not_allowed` | не `GET` | нет |
| 429 | `rate_limited` | превышен лимит по IP, `Retry-After: 60` | нет |
| 502 | `upstream_error` | `transporteRest` ответил ошибкой или непонятным телом | нет |
| 504 | `upstream_timeout` | `transporteRest` не ответил за 8 с | нет |

## Кэш и лимит

- **Workers Caching** (`"cache": {"enabled": true}` в `wrangler.jsonc`): Cloudflare проверяет
  кэш до запуска Worker и хранит ответ столько, сколько сказано в его `Cache-Control`.
  Одновременные промахи по одному URL выполняют Worker один раз — тысяча человек на одной
  остановке дают один запрос к IMM раз в 15 с на дата-центр. Кэш свой у каждой версии Worker:
  после деплоя он пустой.
- **Лимит по IP** — 300 запросов в минуту (`ratelimits` в `wrangler.jsonc`), считается в
  каждой локации Cloudflare отдельно и **только на промахах кэша**: попадания отдаются без
  запуска Worker и до IMM не доходят. Лимит защищает `transporteRest` (и будущую квоту
  официального API), а не тариф Cloudflare: запрос, получивший 429, тоже оплачивается.
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

Локальный сервер на `http://127.0.0.1:8787` ходит в настоящий `transporteRest`. Лимит работает
локально, кэш — нет (`wrangler dev` не отдаёт `Cf-Cache-Status`): кэш проверяется после деплоя.

```bash
npm run dev
```

## Деплой

Один раз — вход в аккаунт Cloudflare (откроется браузер):

```bash
npx wrangler login
```

```bash
npm run deploy
```

Wrangler напечатает адрес вида `https://mvd-transporte-proxy.<subdomain>.workers.dev`.
Проверка кэша — два запроса подряд, во втором `cf-cache-status: HIT`:

```bash
curl -sI https://mvd-transporte-proxy.<subdomain>.workers.dev/v1/stops/3140/arrivals
```

Бесплатный тариф Workers — 100 000 запросов в сутки (сброс в 00:00 UTC), сверх лимита
Cloudflare отвечает ошибкой 1027, и приложение покажет «не удалось проверить». С включённым
кэшем попадания тоже считаются запросами, но не тратят CPU.

## Приватность

Прокси видит IP клиента и номера остановок. В коде IP используется только как ключ лимита и
нигде не сохраняется; в лог (`console.error`) пишется только путь к `transporteRest` при его
ошибке. Workers Logs в `wrangler.jsonc` не включены — прежде чем включать, проверить, что они
записывают о запросах. Когда приложение перейдёт на прокси, обновить
[docs/privacy-policy.md](../docs/privacy-policy.md) и раздел Data safety в Google Play.
