# Session Log

## 2026-10-17 — ревью, миграция API, исправление багов

### What was done
- Полный анализ приложения + исследование API Intendencia de Montevideo (Cómo Ir, официальный API, WFS, открытые данные), правовые рамки.
- Обнаружено: оба эндпоинта нативной части мертвы (`stmonlineRest/nextETA` → 400, `transporteRest/variantes` → 500) — ETA, алерты и виджет не работали.
- Миграция на `api.montevideo.gub.uy/transporteRest/{siguientesParada,lineas}`; 21 исправление (см. CHANGELOG, docs/REVIEW.md §4).
- Учтена дельта параллельной сессии ревью (виджет-кнопки, try вокруг виджета, регистр линий, текст атрибуции).
- Тесты переписаны: 18/18; `flutter analyze` чисто; `flutter build apk --debug` собирается.

### Current state
- What works: API-клиент проверен на живых данных (остановка 3140); unit/widget тесты; debug APK.
- What's broken/pending: не проверено на устройстве (эмулятор `Medium_Phone_API_36.1` — «No initial system image», Xcode не выбран). iOS фон/виджет не настроены. Изменения не закоммичены.

### Next steps
- Ручная проверка на Android: геолокация в Cómo Ir, кнопки виджета, биометрия с PIN, фоновые алерты.
- Решения владельца (docs/REVIEW.md §5): applicationId, release keystore, иконка, WebView vs Custom Tabs, ComoIrScraper, Hive → hive_ce.
- Регистрация на api.montevideo.gub.uy + прокси для официального API; письмо pci@imm.gub.uy.

### Key decisions made
- Использован открытый `transporteRest` (бэкенд Cómo Ir), а не официальный OAuth-API: секрет нельзя класть в приложение, нужен прокси — это отдельная задача.
- Атрибуция без ссылки на Licencia de Datos Abiertos: живые ETA — сервис, не открытый набор данных.
- Не менял applicationId, иконку, архитектуру вкладок — продуктовые решения.

## 2026-10-17 (позже) — проверка на iOS-симуляторе

### What was done
- Коммит 808b92e на ветке `fix/api-migration-review`, запушен в origin (PR не создан — прервано пользователем ради проверки на iOS).
- CocoaPods 1.17.0 установлен в `~/.gem` (brew не работает на macOS 27; для Ruby 2.6 закреплены ffi 1.16.3, activesupport 6.1.7.10 и др.).
- iOS не собирался → deployment target 15.0 + post_install в Podfile.
- Найден и исправлен вечный «Cargando...» при гибели WebContent; тест воспроизводит.
- На симуляторе проверены «Mis paradas», ошибки, уведомления, Info, перезапуск.

### Current state
- What works: всё нативное на iOS-симуляторе; 20/20 тестов; analyze чисто.
- What's broken/pending: WebKit в симуляторе падает у всех (среда) — WebView-страницы не проверены; новые изменения не закоммичены.

### Next steps
- Закоммитить iOS-фиксы, создать PR в undermindOS/MVD_Transporte.
- Обновить Flutter (lipo `-verify_arch` в Xcode 27).

## 2026-10-17 (вечер) — системный браузер вместо WebView (`feat/custom-tabs`)

### What was done
- Ветка `feat/custom-tabs` от `fix/api-migration-review` (0f73dd0), worktree
  `.claude/worktrees/optimistic-antonelli-e27470/MVD_Transporte`.
- Mi STM, Recarga, Cómo Ir, Avisos — плитки во вкладке «Servicios», открываются через `url_launcher`
  (`inAppBrowserView` = Custom Tabs / SFSafariViewController); главная — «Mis paradas».
- «Ver en Cómo Ir» на карточке остановки (тот же API `onOpenStopInComoIr`, что в `claude/nearby-stops-comoir`).
- Удалены `BalanceScraper`, `ComoIrScraper`, баланс в виджете, WebView-зависимости, `permission_handler`.
- Кнопки виджета «Mi STM»/«Recarga» открывают сайт в браузере (PendingIntent ACTION_VIEW).

### Current state
- What works: analyze чисто, 20/20 тестов; iOS-симулятор: тап «Mi STM» открывает SFSafariViewController.
- What's broken/pending: Android не проверен (эмулятор не стартует). Конфликты при слиянии с
  `claude/nearby-stops-comoir`: `webview_page.dart` (переименован в `home_page.dart` — брать нашу версию),
  импорты `stops_page.dart`, `CHANGELOG.md`, `SESSION.md`, `test/widget_test.dart`.

### Next steps
- Решение владельца по биометрическому замку (docs/REVIEW.md §5.1).
- Проверка на Android-устройстве: Custom Tabs, кнопки виджета, возврат без повторной блокировки.

### Key decisions made
- `url_launcher`, не `flutter_custom_tabs`: first-party, кастомизация не нужна; WebView-фолбэк
  `url_launcher` обойдён проверкой `supportsLaunchMode` + `<queries>` CustomTabsService.
- На iOS показ SFSafariViewController ставит приложение на паузу (проверено) → возврат из браузера
  не блокирует повторно, если пауза началась ≤ 3 с после открытия.
- Разрешения геолокации оставлены: нужны ветке «Paradas cercanas».

## 2026-10-17 (позже) — функции на открытых данных Cómo Ir (ветка feat/open-data-features)

### What was done
- «Novedades» (новости IM, `notificacion/mensajes`), ♿ на чипе рейса, экран «Horarios»
  (`siguientesParada/{id}/{tipoDia}/{H:MM}`), предупреждение «Datos GPS parciales» (`pci…/buses/control`).
- Перепроверены все эндпоинты curl'ом; живые ответы сохранены в `test/fixtures/`.
- Находка: `notificacion/mensajes` отдаёт 10 сообщений с `id > N` в порядке хранения; листание по
  максимальному id (как в Cómo Ir) теряет сообщения → поиск «верхнего окна» по `count`.

### Current state
- What works: `flutter analyze` чисто, `flutter test` 53/53; iOS-симулятор с живым API — новости,
  деталь, «Ver más» → Safari, «Horarios» и смена дня, ♿ (остановка 4018), баннер GPS (подставленный статус).
- What's broken/pending: не закоммичено в main, не запушено. Ветка `claude/nearby-stops-comoir`
  правит те же места `stops_page.dart` (импорты, шапка карточки) — при слиянии будут простые конфликты.

### Next steps
- Слить с `claude/nearby-stops-comoir`, решить конфликты в `stops_page.dart`/`CHANGELOG.md`/`SESSION.md`.
- README: перечислить новые источники данных.

### Key decisions made
- HTML новостей — разбор `package:html` в текст, без WebView/JS; ссылки только http(s), в системном браузере.
- Без фонового опроса: только по открытию/pull-to-refresh, с минимальными интервалами и кэшем.
- Непрочитанные = `idMensaje` больше последнего прочитанного; при первом открытии все новые.

## 2026-10-17 — Paradas cercanas (WFS) + «Ver en Cómo Ir»

### What was done
- «Paradas cercanas» в диалоге «Agregar parada»: геолокация по нажатию → WFS
  `imm:v_uptu_paradas` (BBOX 400 м, lon,lat) → группировка по `cod_ubic_parada`, сортировка по расстоянию.
  Выбор → существующий `_addStop` (`resolveStop` → `saveStop`).
- «Ver en Cómo Ir» на карточке остановки → вкладка Cómo Ir с `/comoir/parada?numero={id}`.
- Тесты: `nearby_stops_service_test.dart` (фикстура — живой ответ WFS), `stops_page_test.dart`
  (диалог → список → сохранение; отказ в разрешении; кнопка), WebView-связка в `widget_test.dart`. 33/33.

### Current state
- What works: analyze чистый, тесты зелёные, debug APK собирается, живой WFS отвечает на URI из Dart
  (центр — 32 остановки в 400 м, Colón — 17).
- What's broken/pending: на устройстве не проверено (диалог разрешения, реальный GPS, загрузка deep link
  в WebView). Работа в отдельном worktree `claude/nearby-stops-comoir`, не закоммичено.

### Next steps
- Ручная проверка на Android/iOS; коммит после разрешения владельца.

### Key decisions made
- Разрешение через `Geolocator.requestPermission`, а не permission_handler: на iOS permission_handler
  требует макрос `PERMISSION_LOCATION` в Podfile, его нет.
- Радиус 400 м: в центре 8 КБ gzip, в пригороде остановки находятся (Colón — 17).
- Сохранение по-прежнему через `transporteRest/lineas` — название/линии из того же источника, что и ETA.

## 2026-10-17 (вечер) — правовой пакет, шаг 1 плана

### What was done
- Ветка `chore/store-compliance` от `fix/api-migration-review` (PR #1 открыт).
- Иконка: старая содержала герб Монтевидео (прямо указано в assets/README.md) → белый автобус на синем; адаптивная иконка и сплэш на прозрачном переднем плане; проверено на iOS-симуляторе.
- docs/store-listing.md, docs/privacy-policy.md (Ley 18.331), docs/carta-imm.md (не отправлено).
- Параллельно идут сессии: Custom Tabs вместо WebView, функции на открытых API IM, «Paradas cercanas» (33fd963).

### Next steps
- Закоммитить ветку; шаг 2 плана — слить PR #1 и ветки фич (по подтверждению).
- После Custom Tabs: ссылка на политику в Info, опубликовать политику (GitHub Pages).
- Решить лицензию репозитория (сейчас публичный без LICENSE).

## 2026-10-18 — слияние, applicationId, автообновление ETA, «Estoy esperando» (ветка feat/live-eta-waiting)

### What was done
- `main` перемотан на `integration/features` (fast-forward, локально; origin/main не обновлён).
- `applicationId`/namespace/Kotlin-пакет → `com.liberontech.stmapp` (как iOS bundle id); `home_widget`
  ищет класс виджета по `packageName`, поэтому пакет перенесён вместе с ID. APK проверен aapt2.
- Автообновление ETA раз в 30 с на переднем плане + сразу при возврате из фона (без спиннера).
- «Estoy esperando»: тап по плашке рейса → порог 3/5/10 мин. Android — `flutter_foreground_task` 10.0.0,
  тип `dataSync`, опрос раз в 30 с; iOS — напоминание `zonedSchedule` на прогнозное время.
- AppDelegate: делегат `UNUserNotificationCenter`, иначе iOS не показывает уведомления при открытом приложении.

### Current state
- What works: analyze чисто, 77/77 тестов (мутации ключевых мест ловятся); debug APK собирается,
  в манифесте служба с `dataSync`; iOS-симулятор (свой iPhone 17 Pro 3FAB5A9F…): шторка, колокольчик,
  системный запрос уведомлений, напоминание доставлено в фоне, ожидание переживает уход в фон,
  завершается по GPS при возврате.
- What's broken/pending: Android-служба не проверена на устройстве (эмулятор не стартует).
  iOS-напоминание — по прогнозу: при задержке автобуса приходит раньше. Плагин на iOS пишет в лог
  «BGTask … not advertised in Info.plist» при уходе в фон (не падение).

### Next steps
- Проверка на Android-устройстве: служба, кнопка «Dejar de esperar», Doze, Android 14/15.
- Play Console: декларация FGS `dataSync` + видео (текст в docs/store-listing.md).
- Push `main` и ветки — по подтверждению.

### Key decisions made
- Пакет `flutter_foreground_task` (~180★; пакетов с 1000+★ нет) — выбор владельца.
- Рейс идентифицируется линией + направлением + ожидаемым временем (у рейсов по расписанию нет id).
- На Android уведомление только по автобусу с GPS (как периодические алерты).

## 2026-10-19 — прокси на Cloudflare Workers (шаг 1 перехода на официальный API)

### What was done
- Сверка документации API IM: в Swagger `publictransport` 9 эндпоинтов, все требуют OAuth2 (без токена 403);
  приложение ни один не использует. В основном checkout (ветка `feat/live-eta-waiting`, не закоммичено)
  дополнен docs/REVIEW.md §2.3: `/buses/linevariants/{lineVariantId}`, схема `upcomingbuses` в Swagger.
- Ветка `feat/cf-proxy` от `main` (worktree `.claude/worktrees/cf-proxy/MVD_Transporte`): `proxy/` —
  Worker с маршрутами `/v1/stops/{id}`, `/arrivals`, `/schedule/{weekday|saturday|sunday}/{H:MM}`
  поверх `transporteRest` в собственном формате; Workers Caching (15 с / 24 ч / 6 ч), лимит 300/мин с IP.
- 25 тестов `node:test` на живых ответах (мутационная проверка: ловят снятые проверки); `wrangler dev`
  против живого `transporteRest`: маршруты, `stop_not_found`, 400/404, 429 после ~300 запросов.

### Current state
- What works: прокси локально, тесты зелёные.
- What's broken/pending: не задеплоен (нужен `wrangler login` владельца); кэш локально не работает —
  проверить `cf-cache-status: HIT` после деплоя. Приложение на прокси не переключено. Не закоммичено.

### Next steps
- Деплой → проверка кэша → шаг 2: `MvdApiService` на `/v1` (включая фоновые задачи), privacy policy,
  Data safety. Затем регистрация на портале и смена источника в прокси на официальный API.

### Key decisions made
- Workers Caching, а не Cache API: Cache API на `*.workers.dev` не работает и не объединяет запросы.
- Один entrypoint без «шлюза»: шлюз удвоил бы оплачиваемые запросы; лимит по IP считается на промахах
  кэша — этого достаточно, чтобы защитить IMM.
- Лимит по IP щедрый (300/мин): документация Cloudflare предупреждает о CGNAT на мобильных сетях.
- Токен IM (на будущее): канонический `…/auth/realms/pci/protocol/openid-connect/token` (мануал + OIDC
  discovery); короткий `/token` из Swagger тоже отвечает.

## 2026-10-19 (вечер) — официальный API IM через прокси (ветка feat/official-api)

### What was done
- Ключ портала владельца (приложение «MVD Transporte», план Basico) проверен на всех 9 эндпоинтах.
  Работают `/buses` (весь парк), `/busstops`, `/linevariants`, GTFS; сломаны `upcomingbuses` (всегда
  `[]`), `/busstops/{id}/lines` (400), `/buses/geo` (500). **Лимит — 14 запросов в минуту на ключ**
  (окно от :00). Факты — docs/REVIEW.md §2.3 и память проекта `mvd-api-endpoints`.
- Ветка `feat/official-api` от `feat/live-eta-waiting` + слияние `feat/cf-proxy` (конфликты только в
  CHANGELOG/SESSION — оставлены обе стороны). Worktree `.claude/worktrees/official-api/MVD_Transporte`.
- Прокси v0.2.0: Durable Object `ImGateway` (токен, бюджет 12/мин в хранилище, общий снимок парка
  ≤ раз в 15 с, stale-while-revalidate, комфорт машин в хранилище), `vehicle` в arrivals,
  `/v1/lines/{line}/buses`, `/v1/catalog/{stops,lines}`. 59 тестов `node:test`, мутации ловятся.
- Приложение: `MVD_PROXY_URL` (dart-define) → все запросы `MvdApiService` через `/v1`; ❄️/⚡ на плашке.
  88 тестов, analyze чисто, 5 мутаций ловятся.
- Документация: REVIEW §2.3 и §6, proxy/README, README, CHANGELOG, privacy-policy, store-listing.

### Current state
- What works: `wrangler dev` с живым ключом — 40 запросов за 25 с → 3 запроса `/buses`; комфорт у
  128/128 автобусов с GPS; после 12–40 с простоя ответ < 1 с с комфортом. iOS-симулятор (свой
  `MVD official-api` F0AA39A7…) с `MVD_PROXY_URL=http://127.0.0.1:8787`: остановка 4018 добавлена
  через прокси, плашки CE1 ♿❄️⚡, 21 ❄️⚡, D11/187 ♿❄️; «Horarios» через `/v1`.
- What's broken/pending: прокси не задеплоен (нужны `wrangler login` и `wrangler secret put` владельца).
  Android и фоновые задачи через прокси на устройстве не проверены. Не закоммичено (кроме merge-коммита).
  Первый запрос после деплоя приходит без комфорта (хранилище пустое).

### Next steps
- Владелец: деплой прокси, затем адрес Worker в сборках (`--dart-define=MVD_PROXY_URL=…`).
- Перевыпустить секрет на портале после деплоя («Regenerar» → `wrangler secret put IM_CLIENT_SECRET`) —
  он попал в скриншот в чате.
- Письмо в pci@imm.gub.uy (docs/carta-imm.md): сломанные `upcomingbuses`, `/lines`, `/geo`, лимит.
- Дальше на тех же данных: поиск остановки по улицам (`/v1/catalog/stops`), карта линии
  (`/v1/lines/{line}/buses`), GTFS офлайн.

### Key decisions made
- ETA остаются из `transporteRest` — официальный `upcomingbuses` пуст.
- Один Durable Object на весь прокси: 14/мин на ключ нельзя делить между локациями Cloudflare.
- Durable Object засыпает через 10 с простоя (не 70–140 с — то для объектов с таймерами/сокетами),
  поэтому бюджет и комфорт в его хранилище; найдено по трассам `wrangler dev` (новый токен каждые ~25 с).
- Показывается только подтверждённое «да»: «Sin datos» ≠ «нет кондиционера».
- `MVD_PROXY_URL` с прямым режимом по умолчанию — чтобы сборки не ломались до деплоя прокси.

## 2026-10-26 — документация и GitHub на испанском (ветка docs/es)

### What was done
- Ветка `docs/es` от `feat/live-eta-waiting` (PR #3), worktree `.claude/worktrees/docs-es/MVD_Transporte`.
- На риоплатский испанский переведены README, CHANGELOG, docs/REVIEW.md (с русского) и LOGO_SETUP.md,
  STM_APP_SETUP.md, assets/README.md (с английского). docs/carta-imm, privacy-policy, store-listing уже были на испанском.
- GitHub: описание репозитория и topics на испанском; заголовки и описания PR #1–#3 переведены
  (оригиналы сохранены в scratchpad сессии, не в репо).
- Скрипт-сверка с HEAD: `code`, URL, блоки кода, число заголовков/строк таблиц/пунктов списков совпадают.

### Current state
- What works: переводы закоммичены, PR открыт с базой `feat/live-eta-waiting`.
- What's broken/pending: в основной рабочей копии есть незакоммиченная правка docs/REVIEW.md (3 строки
  про `upcomingbuses`/`linevariants/{id}`, на русском, из другой сессии) — в перевод не вошла; при коммите
  будет конфликт с docs/es.

### Next steps
- После слияния PR #3 — сменить базу PR docs/es на `main`.
- Новые записи CHANGELOG, тексты PR и документацию писать на испанском.

### Key decisions made
- SESSION.md и шаблонный README в ios/ не переводятся; сообщения коммитов остаются на английском.
- В CHANGELOG заголовок `[Unreleased]` оставлен на английском (его ищут инструменты релиза), разделы — Agregado/Cambiado/Corregido/Eliminado.
- STM_APP_SETUP.md переведён как есть, хотя описывает старую версию с WebView.

## 2026-10-27 — Timbre на всё приложение, прокси как BFF, документация дизайна (ветка feat/timbre-bff)

### What was done
- База: `claude/street-search` + влитая `feat/alert-schedule-lines`, перекрашенная в Timbre (5e63ddb).
- Контракт /v1 сначала: `proxy/contract/v1` (24 случая, golden-ответы, 148 векторов, снимки источников) —
  общий для прокси и приложения; правила дважды: `proxy/src/rules.js` и `lib/services/api/contract_rules.dart`.
- Прокси (0.3.0): формы под экраны (`tripId`, `state`, `expectedAt`, `clockTime`), `/v1/news`, `/v1/status/gps`,
  индекс остановок из CSV geoserver в Durable Object (64 части), `directions` у остановки, линии в каталоге,
  логи `<источник>: <вид>`, удалены `/v1/lines/{line}/buses` и `/v1/catalog/lines`, `scripts/smoke.js`.
- Приложение: слой `lib/services/api/` (ApiResult/ApiFailure, V1Parser, ProxySource/DirectSource), прямой
  режим сохранён; «Paradas cercanas» с прокси считается на телефоне; опрос только на видимом экране;
  оценки «~H:MM» для старого табло; виджет по `expectedAt`; «Estoy esperando» по `tripId`; RouteAlert поле 11.
- UI доведён до правил Timbre (ámbar только для живого, Doto ≥ 19, ошибки rojoLed с voseo, TalkBack-фразы).
- Ревью 5 измерений + адверсарная проверка: 13 находок, 8 подтверждены и исправлены (+2 моих хвоста).
- Документация: влит `docs/es`; `docs/design/` (13 разделов, `contrato-v1.md`, `pantalla-a-datos.md`,
  `tokens.json` + `test/design_tokens_test.dart`); политика приватности, store listing, REVIEW; CHANGELOG на испанском.
- Артефакт дизайн-системы Dkqro485d1MznZZtSmigAy (рус.) сверен с кодом, версия 5, новый раздел 5-Contract.

### Current state
- What works: прокси `npm test` 313/313, `flutter analyze` чисто, `flutter test` 474/474, `flutter build apk --debug`.
- What's broken/pending: прокси не задеплоен — F5/BigIP может блокировать Cloudflare к geoserver/notificacion/pci;
  проверка только `scripts/smoke.js` после деплоя. Устройства не проверялись (нет эмулятора), iOS не собирался.
  transporteRest сейчас отвечает 500 на `siguientesParada/6325` (кейс `arrivals.empty`) — smoke покажет FAIL.

### Next steps
- Владелец: деплой прокси → `smoke.js` → сборка с `MVD_PROXY_URL`.
- Решения владельца: текст «FUENTE DE DATOS» в Info для сборки с прокси; ссылка на политику приватности
  в приложении (`privacyPolicyUrl` не передаётся); другая остановка для `arrivals.empty`; перерисовка виджета
  по AlarmManager через 2 мин после ómnibus; блокировка не закрывает Horarios/Info (найдено чтением кода).
- Превью компонентов в артефакте сняты до /v1 (CartelTira, PageTitleBar, нет состояния «оценка»).

### Key decisions made
- Без batch-маршрута, без переключения прокси→прямой во время работы, сборка с прокси не ходит в Intendencia.
- Старое табло — оценка без янтаря: после ошибки до 5 мин; без ошибки через 1 мин по часам телефона, с 5 мин спиннер.
- Каталог без линий на телефоне живёт 15 мин и не заменяет копию с линиями.
- Записи фиксов ревью свёрнуты в существующие пункты CHANGELOG (баги внутри одной невыпущенной партии).

## 2026-10-27 (вечер) — блокировка на всё приложение, политика приватности в приложении, тестовые сборки

### What was done
- По решениям владельца: в Info для сборки с прокси — фраза про сервер проекта (и строка про кондиционер только с прокси);
  экран «Privacidad» рендерит `docs/privacy-policy.md` (ассет, свой мини-рендерер Markdown, blockquote скрыт), дата 27.10.2026.
- `AppLock` в `MaterialApp.builder` над навигатором: под блокировкой скрыты страницы, листы, диалоги, snackbar;
  блокировка только после paused/hidden; все внешние запуски через `ExternalApps.launch` (браузер, почта, «Ver más», настройки).
- Ревью каждой ветки + интеграция (fd86cc2, запушено в PR #5): прокси 313, analyze чисто, flutter 493/493.
- Эмулятор: свой AVD `MVD_Transporte_API_36.1` (google_apis, образ playstore у Medium_Phone неполный), emulator-5556;
  emulator-5554 (Liberon_API) — чужая сессия. Release-APK (прямой режим) установлен и проверен: Info, Privacidad.

### Current state
- What works: `build/app/outputs/flutter-apk/app-release.apk` (57.4 МБ, без MVD_PROXY_URL, подписан debug-ключом).
- What's broken/pending: блокировку на эмуляторе проверить можно только с PIN экрана; в прямой сборке пункт «Resumen»
  политики про сервер-посредник неверен (политика рассчитана на сборки с прокси); юр. проверка политики не сделана.

### Next steps
- Владелец тестирует на эмуляторе и телефоне; затем деплой прокси → smoke → сборка с MVD_PROXY_URL.

## 2026-10-28 — Mapa: исследование и прототип двух картодвижков
### What was done
- Исследование: у Cómo Ir нет карты всего парка; он рисует только GPS-автобусы у выбранной остановки (transporteRest siguientesParada). Весь парк есть только через официальный API `/buses` в прокси.
- Решения владельца: фаза 1 — сохранённые остановки и автобусы, которые к ним едут (прямой режим); фаза 2 — весь город через `/v1/buses` после деплоя прокси. Подложка лежит внутри приложения (вырез Protomaps). Движок выбирается по скриншотам двух прототипов.
- Подложка: вырез Protomaps 20261028 (14,86 МБ, z0-15, Монтевидео с Costa, Las Piedras и Pando). Стиль «Timbre Noche» без янтаря. Происхождение и лицензии описаны в scratchpad `mapa-assets/README.md`.
- Прототипы:
  - ветка `spike/mapa-maplibre` (b44dae2), maplibre_gl 0.27.1;
  - ветка `spike/mapa-fluttermap` (d983e7d), flutter_map 8.3.2 + flutter_map_vector_tiles 2.10.1.
  - Ничего не запушено.
- Скриншоты сделаны на Android (новый AVD `MVD_mapa_spike_API_36.1`) и на iOS-симуляторе «MVD mapa spike». Сравнения лежат во внешнем `.claude-docs/mapa-spike/compare/`.
### Current state
- What works:
  - Оба движка рисуют одну и ту же подложку, живые автобусы и шторку автобуса на Android и iOS.
  - Оба собираются на Xcode 27.1.
- What's broken/pending:
  - 1000 автобусов: flutter_map двигает их плавно, maplibre на Android — рывками (4-8 шагов).
  - Размер APK: maplibre +43 МБ, flutter_map +13 МБ.
  - На z12 значки закрывают весь город — нужен порог «точки/значки» или кластеры.
  - Цифры кадров сняты на перегруженном Mac, нужна проверка на реальном телефоне.
  - Побочный эффект: на AVD `MVD_Transporte_API_36.1` (там PIN на экране блокировки) установленное приложение заменено сборкой 4c6e428.
### Next steps
- Владелец выбирает движок → фаза 1 в `feat/mapa`: `location` в контракте /v1 arrivals, координаты остановок, вкладка Mapa, тесты, документация на испанском.
### Key decisions made
- Решение «La app no dibuja mapas ni ubicaciones» отменяется, документы переписываются вместе с кодом.
- Иконки и подложку Cómo Ir не копируем: подложка из OSM/Protomaps, значки свои, Timbre.

## 2026-10-28 — Mapa, фаза 1: вкладка на flutter_map
### What was done
- Владелец выбрал flutter_map. Спецификация фазы 1 лежит в scratchpad сессии (design-phase1.md, slice-m-brief.md).
- Три основы сделаны в отдельных ветках, прошли ревью и влиты в feat/mapa (4f0f965):
  - `mapa/contract`: в /v1 у каждого прибытия есть `location`. Правило записано дважды (rules.js и contract_rules.dart), есть векторы и golden-файлы, V1Parser терпит отсутствие поля.
  - `mapa/stop-locations`:
    - `BusStop.hasLocation`;
    - координаты сохраняются при выборе остановки из списка;
    - `StopLocationsService.fillMissing`: с прокси берёт координаты из каталога, без прокси — WFS по номеру (CQL_FILTER), раз в 10 минут на остановку.
  - `mapa/basemap`: в git лежат `assets/map/mvd-20261028.pmtiles` (14,86 МБ) и стиль «Timbre Noche», плюс `LocalPmTilesProvider`, `Basemap` и генератор в `tool/map/`.
- Вкладка Mapa:
  - `MvdApiService.latestBoards`;
  - `lib/ui/map/` (map_buses, bus_layer, map_sheets, mapa_page);
  - третья вкладка с глифом `streets`; строится при первом открытии, работает только когда активна, обёрнута в TickerMode.
- Ревью вкладки (поведение, дизайн, тесты) нашло 5 серьёзных замечаний, все исправлены.
- Документация на испанском: decisiones, pantallas, iconos, color, movimiento, accesibilidad, código, privacy-policy (дата 2026-10-28), store-listing, Info, carta-imm, REVIEW, README, CHANGELOG.
- Проверено на эмуляторе 5556 (AVD MVD_mapa_spike_API_36.1, release APK 37,26 МБ, было 21,74) и на симуляторе «MVD mapa spike».
  - Падений, ANR и ошибок Flutter нет.
  - Найдено и исправлено: камера подстраивалась только под первую найденную остановку (52925d7, тест mapa_camera_test).
### Current state
- What works: 616 тестов Flutter, 325 тестов прокси, analyze чистый. Вкладка работает на Android и iOS. Ничего не запушено.
- What's broken/pending:
  - исправление камеры проверено только тестом, на устройстве не перепроверялось;
  - таблички автобусов перекрывают друг друга, маркеры остановок и подписи подложки;
  - возраст данных считается по fetchedAt: в сборке с прокси телефон со спешащими часами покажет автобусы тусклыми;
  - Mapa не передаёт данные в «Estoy esperando»;
  - экрана лицензий нет;
  - коммит b146306 без scope.
### Next steps
- Решения владельца: исправлять ли часы (receivedAt в latestBoards), подключать ли BusWait к Mapa, делать ли экран лицензий, куда открывать PR (feat/timbre-bff или main), проверять ли на его телефоне.
- Убрать влитые рабочие копии mapa-contract, mapa-stops, mapa-basemap и спайковые рабочие копии.
### Key decisions made
- Без companyId и busId в контракте: автобус опознаётся по tripId `bus-{idEmpresa}-{idBus}`.
- Без bbox в контракте: точки вне границ подложки отбрасывает интерфейс.
- pmtiles закоммичен обычным git отдельным коммитом (90fefc9); перевести на LFS решает владелец.
- Подписи подложки рисуются системным шрифтом, глифы PBF не поставляются.

## 2026-10-29 — Mapa: возраст данных по часам телефона
### What was done
- bf98c53: `latestBoards` хранит `ReceivedBoard` (табло + момент получения по `MvdApiService.clock`). Признак «живой», удаление через 5 мин, пропуск запроса в пределах 30 с и шторка остановки считают время от получения, а не от `fetchedAt`.
- 79738e7, по итогам ревью:
  - отсечка устаревших оценок считается по часам источника (`MapBuses.overdue`);
  - если часы телефона перевели назад, сохранённое табло с отметкой «после текущего момента» уступает новому;
  - на каждое место, где считается возраст, есть тест; каждый тест падает, если его место откатить.
- Всего 623 теста Flutter, analyze без замечаний.
### Current state
- «Mis paradas» после сбоя по-прежнему считает 5 мин от `fetchedAt` (stops_page.dart ≈1018), а оценки сравнивает с часами телефона. Это записано в документации; сам код не трогали.
### Next steps
- Владелец решает, переводить ли «Mis paradas» на тот же расчёт.

## 2026-10-29 — «Mis paradas»: возраст данных по часам телефона и после сбоя
### What was done
- d54b86a: в ветке сбоя «Mis paradas» теперь считает 5 мин от `_BoardView.receivedAt`. Устаревшие оценки в обеих ветках отсекаются по часам источника через общий `ReceivedBoardClock.sourceNow`, его же использует `MapBuses.overdue`. Подпись «Datos de las» по-прежнему показывает `fetchedAt`.
- Два ревьюера блокеров не нашли. По их замечаниям тест «часы спешат на 6 мин» усилен: теперь он ловит три отката. Документация уточнена. Всего 625 тестов.
### Current state
- По словам ревьюера, та же путаница часов осталась в других местах (не трогали):
  - домашний виджет: home_widget_feed.dart:69 и MVDTransporteWidgetProvider.kt:67;
  - напоминание «Estoy esperando»: bus_wait_service.dart:226;
  - раннее завершение ожидания: bus_wait_service.dart:184, bus_wait.dart:132.
### Next steps
- Владелец решает, чинить ли виджет и «Estoy esperando» тем же способом.

## 2026-10-29 — Виджет и «Estoy esperando» по правильным часам
### What was done
- 54387e8:
  - виджет хранит `route_expected_at_ms` по часам телефона: `expectedAt + (now − fetchedAt)`; логика Kotlin не менялась;
  - `BusWait` хранит `clockOffset` (телефон − источник, сохраняется как `clockOffsetMs`);
  - проверка «прошёл», restore и напоминание на iOS сравнивают время через `expectedOnPhone`;
  - фоновый сервис на Android берёт `getBoard`, чтобы получить `fetchedAt`.
- ee98f7c: без прокси `DirectSource.arrivals` берёт `fetchedAt` из заголовка `Date` transporteRest.
  - Проверено одним живым запросом 2026-10-29: `Date` совпадает с `time − minutos` с точностью до минуты, часы IM отличаются от NTP на ~3 с.
  - Без этого смещение в режиме без прокси было ≈0.
- a4c69c6: `Date`, расходящийся с часами телефона больше чем на сутки, игнорируется (двузначный год, 1970).
- 284ea1f: `_publish` отбрасывает более старое табло, только если сохранённое пришло меньше минуты назад. Иначе смесь часов замораживала бы табло.
- Каждое место покрыто тестом, который падает при откате (проверено ревьюерами). 637 тестов Flutter, 325 тестов прокси, analyze без замечаний.
### Current state
- Не сделано, с низкой вероятностью проблемы:
  - сверка `Date` с телом ответа (`time − minutos`): поймала бы `Date`, сдвинутый меньше чем на сутки;
  - `MapBuses.from` сравнивает `fetchedAt` между остановками и при смеси часов может взять позицию не с того табло.
- Один необъяснённый сбой в одном из полных прогонов у агента; следующие 4 прогона зелёные.
### Next steps
- Владелец: открыть PR (куда), проверить на телефоне, убрать влитые рабочие копии.

## 2026-10-29 — Виджеты остановок для Android (ветка `feat/widgets-paradas` от `feat/mapa`)
### What was done
- Макеты в дизайн-системе Timbre MVD: холст claude.ai «Timbre MVD - widgets» (Chico 2×2, Mediano 4×2, Grande 4×4, состояния). По решению владельца янтарь есть во всех размерах: номер линии (контур `ambarTenue`, цифры `ambar`), знак `stop`, кнопка ⟳ и LED-фон. Время — `papel` с «~» и часами, никогда не янтарь и не обратный отсчёт.
- Android: `TimbreProximoWidget`, `TimbreParadaWidget`, `TimbreMisParadasWidget` (`TimbreStopWidget.kt`), правила без Android в `StopWidgetData.kt`, layouts `widget_stop_*` и превью для пикера (Android 12+), новые векторные иконки, глиф `refresh` в `PixelGlyphs`.
- Данные: `StopWidgetsFeed` (`lib/services/stop_widgets_feed.dart`) пишет `stops_saved` и `stop_board_{id}` (до 6 ómnibus, `dueMs` в часах телефона); виджеты пишут `stops_shown` и `stop_widgets_placed`. Кнопка ⟳ запускает Dart в фоне (`home_widget` interactivity, `timbre://refresh`), без открытия app. Тап по имени остановки — следующая сохранённая. Ómnibus исчезает через минуту после своего времени по неточному будильнику, без сети.
- `BackgroundWorker`: фоновая задача тянет остановки виджетов в любое время и не отключается, пока виджет на экране. Проверка виджетов в `sync()` не ждётся: на пути разблокировки платформенный вызов в тестах не завершается (сломал `app_lock_test`, исправлено, со счётчиком поколений против гонки).
- Тесты: Flutter 646/646, analyze чисто; JVM 16/16 (`StopWidgetDataTest` + `StopWidgetRenderTest` на Robolectric: реальные RemoteViews, картинки в `build/widget-previews/`); `flutter build apk --debug` собирается.
- Доки: 10-superficies (новый раздел), 02-color (исключение 3), 04-iconos (35 глифов), 12-decisiones, 13-en-el-codigo, README, CHANGELOG.
### Current state
- What works: всё выше в контейнере; рендер трёх виджетов проверен Robolectric-ом (эмулятора нет, KVM нет).
- What's broken/pending:
  - на телефоне не проверено: пикер, кнопка ⟳ (фоновый движок home_widget), будильник, ресайз;
  - виджет маршрута (`MVDTransporteWidgetProvider`, 3×2) удалён по решению владельца (см. ниже);
  - при включённом биометрическом замке виджет всё равно показывает остановки на домашнем экране;
  - Maven Central через прокси контейнера отвечает 429: Gradle шёл через зеркало Google (init-скрипт в `~/.gradle/init.d/`, вне репо).
### Next steps
- Владелец: поставить APK, проверить три виджета на телефоне, решить судьбу виджета маршрута и поведение при замке.
### Key decisions made
- Остановка на виджете переключается тапом по имени, без экрана настройки: работает на всех launcher-ах и Android-версиях.
- Шрифт виджетов — системный `sans-serif-condensed`, как у виджета маршрута; «SIN PARADAS» — картинка Doto.

## 2026-10-29 — Удалён виджет маршрута
### What was done
- По решению владельца удалены `MVDTransporteWidgetProvider.kt`, его layout, info, `widget_badge_bg`, `widget_ic_route`, `widget_ic_clock`, строка `widget_description`, `WidgetFeed` (`lib/services/home_widget_feed.dart`) и все вызовы. Фоновая задача больше не тянет origin первой ruta ради виджета; avisos de ruta не тронуты.
- Тесты часов виджета маршрута (телефон спешит на 6 мин, `Date` без прокси, офлайн) перенесены на виджеты остановок: `background_worker_test`, `stops_board_test`. Flutter 641/641, JVM 16/16, analyze чисто.
- Доки: 10-superficies, 12-decisiones (решение «El widget muestra el destino del ómnibus» снято), 11-accesibilidad, pantalla-a-datos, 13-en-el-codigo, 04-iconos, 02-color, README, CHANGELOG («Eliminado»).
### Current state
- Уже поставленный виджет маршрута на телефоне после обновления перестанет грузиться: его нужно убрать с экрана вручную.
- Ключи `route_*` остаются в `HomeWidgetPreferences` у тех, у кого был старый виджет: безвредно, не читаются.

## 2026-10-29 — Bienvenida и собственный код приложения (ветка feat/onboarding)
### What was done
- Владелец поставил задачу 2026-10-28: приветствие при первом запуске в стиле Timbre. В нём обязательно сказать, что нет аккаунтов и записи данных, и дать поставить пароль и отпечаток.
- Решения владельца (через вопросы):
  - свой код из 4 цифр, на телефоне хранится только хеш;
  - отпечаток или Face ID для быстрого входа, код запасной;
  - если код забыт — блокировка телефона, затем новый код;
  - ветка от feat/mapa;
  - `CFBundleLocalizations: es` в iOS.
- Первый workflow-исследование (6 агентов) упёрся в лимит сессии и не дал отчётов. Повтор: один агент по `local_auth`, остальное прочитал сам.
- Ядро (сделано сам, тесты зелёные):
  - `AppPasscode`: PBKDF2-HMAC-SHA256, 20 000 итераций, соль 16 байт, через `compute()`; после 5 неверных кодов пауза 30 с;
  - `DeviceAuth`: biometricOnly, испанские AuthMessages, `useErrorDialogs: false`;
  - ключи в `CacheService`, зависимости `crypto` / `local_auth_android` / `local_auth_darwin`;
  - логика `AppLock`: код, быстрый вход, «¿Olvidaste el código?», старый замок до конца приветствия, исправлен fail-open на iOS.
- Спецификация для агентов: внешний `.claude-docs/onboarding/SPEC.md`.
- Дальше 3 workflow:
  - B (виджеты) и C (документация на испанском);
  - D (экран блокировки) и E (приветствие и Info), затем интеграция F;
  - ревью по 4 направлениям с перепроверкой.
- Ревью подтвердило 11 находок из 16, все исправлены, на каждую уязвимость есть тест с проверкой мутацией:
  - SEC-1 (высокая): окно, открытое из незаблокированного приложения (включение отпечатка, «¿Olvidaste el código?» в Info), при stickyAuth переживало уход в фон, и приложение возвращалось открытым. Теперь такие окна не sticky, а возврат, пока окно ещё открыто, блокирует приложение, если окно закрылось не «да»;
  - LIFE-2: каждая блокировка начинается с пустой клавиатуры;
  - UI-1: клавиатура уменьшается на экранах уже 332 dp (тест на 320×568);
  - UI-2: пустые точки кода и шагов в цвете `tenue` (5.31:1);
  - UI-3: иконки строк приветствия в `etiquetaCartel`, как в Info;
  - PRIV-1: политика больше не обещает «solo en tu dispositivo», упомянута резервная копия Google/iCloud;
  - DOC-1..3 и UI-4: мелкие неточности.
- Проверка на эмуляторе Android (emulator-5556, AVD MVD_mapa_spike, без PIN):
  - приветствие целиком и политика из него;
  - код, повтор, «Listo», блокировка после сворачивания;
  - 5 неверных кодов и пауза; «¿Olvidaste el código?» без блокировки экрана — пояснение;
  - смена и выключение кода в Info; холодный перезапуск без приветствия;
  - после ревью: пустые точки видны, недопечатанный код сбрасывается.
- iOS: симулятор «MVD onboarding» (773A1537…), приложение собирается и показывает приветствие. Пройти дальше не удалось: доступ инструмента к симулятору не выдан.
- Коммиты (ничего не запушено):
  - 40def11: код и хеш;
  - d93ed64: блокировка, быстрый вход, Info;
  - 2ca574a: приветствие;
  - a6a2915: документация.
  Каждый коммит отдельно проверен: analyze чистый, тестов 646 / 717 / 739, все зелёные.
### Current state
- What works: 739 тестов, analyze чистый. Ветка feat/onboarding от bf98c53, 4 коммита + этот журнал.
- What's broken/pending:
  - отпечаток на Android и Face ID на iOS не проверены на устройстве (у эмулятора нет PIN и отпечатков, у инструмента нет доступа к симулятору);
  - feat/mapa ушёл вперёд на 8 коммитов (исправления часов), пересекаются только документы (CHANGELOG, SESSION, 08, 09, 10, 12, 13);
  - Android Auto Backup включён; политика теперь говорит об этом честно, а саму настройку решает владелец.
### Next steps
- Решения владельца:
  - проверить отпечаток на его Galaxy Z Flip5 или поставить PIN и отпечаток на эмуляторе;
  - перебазировать на текущий feat/mapa;
  - выключать ли Auto Backup для Hive.
### Key decisions made
- Настройки блокировки пишутся без await (Hive применяет их в памяти синхронно). Это делает виджет-тесты независимыми от порядка.
- Открывает только `true` от системного окна; ошибка сама по себе не доказывает, что у телефона нет блокировки.
- На Android всегда «huella»: система не различает отпечаток и лицо.
### Trajectory
- H1: «в стиль энного» = стиль Timbre — подтверждено владельцем.
- H2: «пароль» = собственный код приложения, а не PIN телефона — подтверждено.
### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| P1 | Владелец выберет рекомендованные варианты | Выбрал все рекомендованные | exact | Рекомендации с понятной ценой выбирают сразу |

## 2026-10-31 / 11-01 — часы в виджетах и навигация в Mapa (ветка feat/reloj-rutas)

### What was done
- Незакоммиченная работа Codex (виджеты ancho и Flip5, частота обновления, страница «О проекте») закоммичена как есть: cbe6e32 на `codex/timbre-widgets-map-rebuild`. Ветка `feat/reloj-rutas` идёт от неё, worktree `.claude/worktrees/reloj-rutas/MVD_Transporte`.
- Próximo 2×2 и Próximo ancho 4×2 стали часами (afbb9e0): `TextClock` сверху, под ним остановка, следующий автобус и ещё два.
  - Сначала сделал свой семисегментный шрифт. В Robolectric он рисовался, а в настоящем лаунчере нет: `RemoteViews` собираются в restricted-контексте, и `TextView` там не грузит шрифты (TextView.java, `TextAppearance_fontFamily`).
  - Итог по выбору владельца: LED-точки. Это системный шрифт с маской из круглых отверстий (`android:foreground` у `FrameLayout`) поверх тусклых «88:88».
  - Проверено на эмуляторе в лаунчере Pixel: оба виджета, без остановок и с остановкой 574.
- Места в Mapa (a762bae):
  - долгое нажатие на карту даёт Casa, Trabajo или избранное с именем;
  - сверху панель чипов, на карте метки с глифами home, work, star;
  - места хранятся JSON в settings;
  - карта открывается и без остановок.
- Планировщик маршрутов:
  - Transitous отпал: в нём нет городских линий STM (`mvd-routing-sources` в памяти);
  - владелец выбрал расчёт на телефоне по открытым данным IM `uptu_pasada_variante`;
  - движок (builder, `horarios.bin`, RAPTOR) пишет агент по `.claude-docs/rutas/SPEC.md` во внешней папке;
  - моя часть: `TripService` (isolate), `trip_ui.dart` (лист вариантов, линия на карте, карточка, шаги с живым ETA первой посадки), политика приватности, лицензия открытых данных в странице лицензий, документация на испанском.

### Current state
- What works: Kotlin-тесты виджетов, тесты карты и мест, 4 теста UI маршрута на подставном планировщике.
- What's broken/pending: UI маршрутов не закоммичен, ждёт коммитов движка. Реальные маршруты на эмуляторе пока не проверены. Ничего не запушено.

### Next steps
- Принять движок, прогнать весь набор тестов, закоммитить UI и документацию, проверить на эмуляторе маршрут Pocitos → Ciudad Vieja.
- Решения владельца: PR (куда), тест на его телефоне, поиск адреса текстом (сейчас места ставятся только на карте).

### Key decisions made
- Часы: `TextClock`, без перерисовки каждую минуту из приложения, потому что иначе время отстаёт и садится батарея.
- Маршруты на телефоне: ничего не уходит с телефона. Праздники считаются как день недели, данные обновляются с выпуском приложения.

### Trajectory
- H1: «widgets that I'm using… and a bit wider ones» = Próximo 2×2 и Próximo ancho. Подтверждено владельцем.
- H2: «digits separated by sections» = семисегментные цифры. В виджете невозможно, владелец выбрал LED-точки.
- H3: «navigation maps experience» = планировщик A→B с местами, без ведения по GPS. Подтверждено.

### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| P1 | Владелец выберет рекомендованные варианты | Выбрал все рекомендованные (4/4, потом 2/2) | exact | — |
| P2 | Transitous покрывает Монтевидео (по одному запросу) | Нет городских линий | miss (gap:literal) | Покрытие проверять несколькими городскими маршрутами |

## 2026-11-01 — маршруты готовы (ветка feat/reloj-rutas)

### What was done
- Движок от агента (f8784c8..fca8e78):
  - сборщик `tool/rutas/build_horarios.py`;
  - `assets/rutas/horarios.bin`: 227 КБ, 4921 остановка, 138 линий, 37 859 рейсов, данные от 31.10;
  - RAPTOR в `lib/services/rutas/`, 18 тестов;
  - время на Mac: decode 36 мс, plan 140–170 мс, в isolate около 170 мс.
- Мои правки движка (0c7e881):
  - фильтр Парето теперь учитывает время выезда, поэтому следующий автобус той же линии больше не пропадает;
  - `TripService` ищет сначала с одной пересадкой, с двумя только если без этого ничего не нашлось.
- UI маршрутов (2b542c7):
  - лист «Cómo llegar a…», линия на карте, карточка, «Pasos» с живым ETA первой посадки;
  - политика приватности (дата 1 ноября), лицензия данных IM в странице лицензий;
  - документация на испанском: 04/07/08/09/12/13, CHANGELOG.
- 693687b: отдельное сообщение для точки без остановок STM рядом. Эмулятор стоит в Маунтин-Вью, и раньше выходило «нет поездки, иди дольше».
- Эмулятор (emulator-5556, лаунчер Pixel):
  - пройдено: Casa в Ciudad Vieja, Trabajo в Centro, варианты 113/100, линия на карте, «Pasos», живое «Con GPS: el 113 llega en 24 min»;
  - код приложения на эмуляторе теперь 1234, выставлен через «¿Olvidaste el código?» и PIN 1111;
  - Google просил «Location Accuracy», ответил «No thanks».

### Current state
- What works: analyze чистый, 802 теста Flutter и тесты Kotlin зелёные. Часы и маршруты проверены в лаунчере эмулятора.
- What's broken/pending:
  - ничего не запушено, PR нет;
  - на телефоне владельца не проверено;
  - время эмулятора PST, поэтому расписание и живые минуты на нём расходятся; на телефоне в UY это не так.

### Next steps
- Владелец: push и PR (база: codex/timbre-widgets-map-rebuild или main?), проверка на его Galaxy Z Flip5.
- Возможные доработки:
  - поиск адреса текстом;
  - убрать почти одинаковые варианты одной линии (100 в 8:27 и в 8:28);
  - линии ехать по форме маршрута, а не прямыми между остановками;
  - обновление `horarios.bin` с выпусками.

### Key decisions made
- Вариант A лучше B, только если A выезжает не раньше B, приезжает не позже и не хуже по пересадкам и ходьбе.

## 2026-11-01 — PR #7 и установка на телефон владельца

### What was done
- Ветка `feat/reloj-rutas` запушена, открыт PR #7 в `main`: https://github.com/undermindOS/MVD_Transporte/pull/7
  - базу владелец не назвал; выбрана `main`, как у #6;
  - в описании стек #5 → #6 → #7 и 22 своих коммита (онбординг, виджеты Codex, часы, места, маршруты);
  - CI-проверок в репозитории нет.
- Release arm64 с `--build-number 2011` (versionCode 2011 > 2010 от Codex) поставлен на Galaxy Z Flip5 владельца по беспроводному adb: `install -r`, подпись совпала, данные сохранены.
- На телефоне стоят виджеты TimbreProximoWidget (id 68) и TimbreFlipWidget (id 70).
- `am broadcast APPWIDGET_UPDATE` с adb на телефоне запрещён (SecurityException), поэтому виджеты перерисуются сами или при открытии приложения.

### Next steps
- Владелец смотрит на телефоне: часы Próximo, места и маршрут в Mapa.

## 2026-11-01 (после теста на телефоне) — поиск адресов, Ajustes, разделение виджетов

### What was done
- Владелец (скриншот с Flip5) попросил:
  - добавлять адрес текстом;
  - настройки любимых мест;
  - «i» заменить шестерёнкой, раз это полноценные настройки;
  - часы крупнее, по центру, с пометкой «сейчас»;
  - разделить виджеты: время на первом месте или автобусы.
- Ответы на вопросы: подпись «AHORA · дата»; Próximo вернуть как было; адреса брать из гибрида IM + OSM с поиском «как в Google Maps», маршрут только по общественному транспорту.
- d87cc19 `PlaceSearch`:
  - IM `ubicacionesRest` (адреса, перекрёстки, места; UTM 21S переводится в WGS84);
  - Photon (OSM, подсказки при наборе);
  - Nominatim только по Enter, не чаще раза в секунду;
  - номер дома проверяется сразу, сокращения улиц понимаются (bv/gral).
- 77e602a:
  - строка поиска над картой, метка `pin` с карточкой «Cómo llegar / Casa / Trabajo / Favorito»; долгое нажатие ставит метку;
  - неотмеченные Casa и Trabajo открывают поиск;
  - Info стал Ajustes с шестерёнкой, «Mis lugares» с поиском, переносом, переименованием, удалением и «Caminar hasta»;
  - места грузятся один раз при старте. Раньше было setState во время build, когда Ajustes открывался поверх Mapa.
- f0ce70f: политика приватности (текст поиска уходит в IM, Photon и Nominatim, не через прокси, без позиции), документация 04/09/12/13, CHANGELOG.
- Виджеты делает агент:
  - 27bc4b0 вернул Próximo и Próximo ancho к прежнему виду;
  - «Reloj» и «Reloj ancho» ещё в работе.
- Эмулятор: поиск «18 de julio 1453» (IM и OSM), метка и карточка, Ajustes «Mis lugares» — всё работает.

### Next steps
- Принять виджеты Reloj, весь набор тестов, release 2012 на телефон владельца, push в PR #7, обновить описание PR.
- Виджеты Reloj (5c40c40, агент): «AHORA · дата», LED-время 53 sp (2×2) и 88 sp (ancho), строка автобуса. Проверены в лаунчере эмулятора рядом с вернувшимися Próximo и ancho.
- 21cbd3a: CHANGELOG, карта кода, тест частоты обновления (список провайдеров).
- Весь набор: 816 Flutter-тестов и Kotlin-тесты зелёные. Запушено, описание и заголовок PR #7 обновлены.
- Release 2012 собран (build/share/TimbreMVD-2012.apk). На телефон не поставлен: телефон пропал из беспроводного adb. APK отправлен владельцу файлом.
