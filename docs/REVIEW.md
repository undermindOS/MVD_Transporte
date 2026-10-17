# MVD Transporte — ревью, API и правовые рамки

**Дата:** 2026-10-17 · **Ветка:** `main` · **Flutter** 3.41.1 / Dart 3.11.0

Все утверждения про API проверены живыми запросами 17.10.2026; про правила сторов
и лицензию — по первоисточникам, ссылки в конце. Часть пунктов перепроверена
параллельной сессией ревью; совпавшие находки отмечены ✔︎.

---

## 1. Что это за приложение

Flutter-приложение (Android основной таргет, iOS сконфигурирован частично):

| Вкладка | Тип | Источник |
|---|---|---|
| Inicio | WebView | `stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml` (Mi STM, вход через SAML SSO `ih.montevideo.gub.uy`) |
| Recarga | WebView | `stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml` |
| Mis paradas | нативная | остановки и маршруты A→B с ETA, алерты (WorkManager, раз в 15 мин) |
| Cómo Ir | WebView | `m.montevideo.gub.uy/comoir/` (Ionic 3 SPA) |
| Avisos | WebView | `stm.gub.uy/.../notificaciones.xhtml` |

Плюс: биометрический замок, Android-виджет (баланс карты из скрейпинга + ближайший автобус),
хранение в Hive.

**Главная находка:** нативная часть (ETA, имена остановок, алерты, виджет) **не работала** —
оба используемых эндпоинта мертвы (см. §2).

---

## 2. API Intendencia de Montevideo

### 2.1 Что использовало приложение — мертво

| Запрос | Ответ 17.10.2026 |
|---|---|
| `POST m.montevideo.gub.uy/stmonlineRest/nextETA` `{"parada": N}` | `400 {"error": "Argumentos invalidos!!!"}` (с `linea` — пустой FeatureCollection ✔︎) |
| `GET m.montevideo.gub.uy/transporteRest/variantes/{id}` | `500 No existe la ubicación de parada…` для любого id |

### 2.2 Открытые эндпоинты Cómo Ir (без авторизации)

Найдены в конфиге `m.montevideo.gub.uy/comoir/build/main.js`. Теперь приложение использует первые два.

| Эндпоинт | Назначение |
|---|---|
| `GET api.montevideo.gub.uy/transporteRest/siguientesParada/{parada}` | ближайшие автобусы (POST с `[codigoLinea…]` — фильтр по линиям) |
| `GET …/transporteRest/lineas/{parada}` | `{"descripcion":"<угол улиц>","lineas":[{"descripcion":"G8","codigo":437}]}` |
| `GET …/transporteRest/siguientesParada/{parada}/{HABIL\|SABADO\|DOMINGO}/{H:MM}` | расписание по типу дня |
| `POST …/transporteRest/siguientesRuteo/…`, `…/partesCirculares/` | ETA по маршруту, кольцевые |
| `api.montevideo.gub.uy/comoirRest/rest/comoir/{caminando,bus,cortarRecorrido,duracionRuteo}` | построение маршрута |
| `api.montevideo.gub.uy/ubicacionesRest/…` | геокодирование: углы, адреса, POI |
| `GET api.montevideo.gub.uy/notificacion/mensajes?idApp=1&fromIdMessage=N` | официальные новости транспорта (объезды, изменения) |
| `GET pci.montevideo.gub.uy/buses/control` | % GPS-покрытия по операторам `[{"empresa":"CUTCSA","valor":100}…]` |
| `geoserver.montevideo.gub.uy/geoserver/ows` WFS `imm:v_uptu_paradas` | 42 672 записи «остановка × вариант», EPSG:32721 (`srsName=EPSG:4326` для lat/lon) ✔︎ |
| `https://m.montevideo.gub.uy/comoir/parada?numero={id}` | deep link: открыть остановку в Cómo Ir (сервер отдаёт SPA, код обрабатывает `numero`) |

Формат `siguientesParada` (реальный ответ, остановка 3140):

```json
{"linea":"145","destino":"PLAZA ESPAÑA","minutos":5,"real":true,
 "coordinates":[-56.142532,-34.88331],"idEmpresa":50,"idBus":247,
 "horaDesc":"7:39","accesibilidad":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y LUCIANO ROMERO"}
```

`real:false` — расписание без GPS (`coordinates:null`, `minutos` может быть 945).
`idEmpresa`: 10 COETC, 20 COME, 50 CUTCSA, 70 UCOT. Несуществующая остановка → `500 "No existe…"`.

### 2.3 Официальный документированный API

`https://api.montevideo.gub.uy/api/transportepublico` (Swagger: `/swagger/spec/publictransport.json`) ✔︎

- OAuth2 **client_credentials**, token: `https://mvdapi-auth.montevideo.gub.uy/token`; без токена → `403`.
- `GET /buses` (позиции всего парка, фильтры `company`, `lines`, `busstopId`), `/buses/geo?center&radius`
- `GET /buses/busstops`, `/buses/busstops/{id}/lines`, `/buses/busstops/{id}/upcomingbuses?lines=` (обязателен `lines`)
- `GET /buses/linevariants`, `/buses/gtfs/static/latest/google_transit.zip` (+ `version.txt`) — **GTFS**
- `ETAItem` содержит `eta` (с), `distance` (м), `access`, `thermalConfort`, `emissions`.

### 2.4 Открытые наборы данных (catalogodatos.gub.uy, Licencia de Datos Abiertos – Uruguay)

- «Horarios de ómnibus urbanos por parada STM» — `datos-abiertos.montevideo.gub.uy/uptu_pasada_variante.zip`
- «Transporte colectivo: paradas, puntos de control y recorridos de ómnibus» — shapefile’ы
- «Viajes realizados en los ómnibus del STM» — обновлён 2026-09-19

---

## 3. Правовые рамки

**Официальный API.** Условия на портале: сервис «se ofrece de forma gratuita para el público
en general», нужна бесплатная регистрация, «un número razonable de consultas por segundo»,
вопросы — `pci@imm.gub.uy`. Это единственный канал с явным разрешением.

**`transporteRest` (используется сейчас).** Открыт технически, но это внутренний бэкенд Cómo Ir
без опубликованных условий. Технический доступ ≠ разрешение; эндпоинт может исчезнуть так же,
как `stmonlineRest`. Это не хуже исходного состояния (приложение и раньше ходило в недокументированные
эндпоинты), но долгосрочно — риск.

**Licencia de Datos Abiertos – Uruguay v0.1** (Directrices técnicas AGESIC, утверждены Decreto 54/017):
разрешает коммерческое и некоммерческое использование, переработку и встраивание в приложения.
«Nota de Origen» обязательна и должна содержать: поставщика, ссылку на лицензию, **ссылку на
конкретный набор данных**, и **упоминание изменений** ✔︎. Сейчас приложение открытые наборы не
использует, поэтому в Info указан источник без ссылки на лицензию. При подключении GTFS/наборов —
добавить полную Nota de Origen.

**Политики сторов (главный риск публикации)** ✔︎
- Google Play, Spam: запрещено приложение, которое является «a webview of a website without
  permission from the website owner or administrator». 4 из 5 вкладок — WebView сайтов IM.
- Google Play, Government/Misleading Claims: нужен явный дисклеймер о неаффилированности
  и ссылка на источник в описании стора. Дисклеймер в Info есть; **иконка — щит с солнцем и
  полосами — похожа на госсимволику Уругвая** → риск отклонения.
- Apple 4.2 (Minimum Functionality, «repackaged website») и 5.2.2 (нужно разрешение
  на использование стороннего сервиса).

**Приватность (Ley 18.331).** Нужна политика конфиденциальности (обязательна для сторов):
геолокация (Cómo Ir), локальное хранение баланса, вход в Mi STM. Вход идёт через SAML SSO
`ih.montevideo.gub.uy` **внутри WebView приложения**, а приложение внедряет JS в страницы — даже
при честном коде пользователь не может это проверить. Лучшая практика (RFC 8252) —
Custom Tabs / SFSafariViewController для входа. Виджет показывает баланс даже при включённом
биометрическом замке.

---

## 4. Исправлено в этом изменении

| # | Серьёзность | Где | Проблема → исправление |
|---|---|---|---|
| 1 | P0 | `mvd_api_service.dart` | ETA: мёртвый `nextETA` → `siguientesParada`; ошибка сети теперь `null`, а не «нет автобусов» |
| 2 | P0 | `mvd_api_service.dart` | имя остановки: мёртвый `variantes` → `lineas`; `StopNotFoundException` |
| 3 | P0 | `background_worker.dart`, `stops_page.dart` | фоновая задача не регистрировалась при включении алертов и для маршрутов → `BackgroundWorker.sync()` после каждого изменения |
| 4 | P0 | `stops_page.dart` | `Dismissible` удалял элемент после `await` → синхронное удаление |
| 5 | P0 | `webview_page.dart` | биометрия fail-open при любом исключении (в т.ч. `LockedOut`) → fail-closed, открывать только если на устройстве нет блокировки |
| 6 | P0 | `test/` | оба теста падали → fake WebView-платформа, Hive во temp, 18 тестов на реальных фикстурах |
| 7 | P1 | `background_worker.dart` | алерт «llegando» по расписанию → только `isRealTime` |
| 8 | P1 | `background_worker.dart` | исключение виджета (iOS без App Group) глушило уведомления → отдельный try ✔︎ |
| 9 | P1 | `webview_page.dart` | Android WebView по умолчанию запрещает геолокацию (`// default don't allow` в плагине) → callback с запросом разрешения, только домены IM |
| 10 | P1 | `webview_page.dart` | цикл блокировки: системный PIN-экран вызывает pause/resume → защита `_isAuthenticating` + 2 с grace |
| 11 | P1 | `info_page.dart` | `StatelessWidget` — переключатель не менялся → stateful, callback возвращает итоговое состояние |
| 12 | P1 | `MVDTransporteWidgetProvider.kt`, `webview_page.dart` | кнопки виджета: `putExtra("tab")` никто не читал → `HomeWidgetLaunchIntent` + URI `mvdtransporte://tab?index=N` ✔︎ |
| 13 | P1 | `comoir_scraper.dart` | `[class*="to"]` ловил `toolbar`/`button`/`bottom`, `[data-id]` — что угодно; запуск на любом URL с «comoir» → узкие селекторы, проверка хоста |
| 14 | P1 | `balance_scraper.dart` | запуск на любом URL с `principal.xhtml`; в виджет мог попасть текст контейнера → проверка хоста, извлечение суммы |
| 15 | P1 | `AndroidManifest.xml` | `SCHEDULE_EXACT_ALARM` не используется (ограничен Google Play), `usesCleartextTraffic="true"` → удалено/`false` ✔︎ |
| 16 | P2 | `route_alert.dart` | линии сравнивались с учётом регистра ✔︎ |
| 17 | P2 | виджет | «5 min» устаревает до 15 мин → время прибытия `~08:14`; строка маршрута очищается без данных |
| 18 | P2 | `webview_page.dart` | SPA-навигация не обновляла «назад» → `onUrlChange`; `setState` после `dispose` → проверки `mounted` |
| 19 | P2 | `cache_service.dart` | двойная регистрация адаптеров Hive (hot restart) → guard |
| 20 | P2 | `webview_page.dart` | геолокация при каждом старте, уведомления без алертов → запрос в контексте |
| 21 | P2 | `info_page.dart` | ссылка на несуществующий репозиторий `mi_Transporte_MVD`; нет источника данных |
| 22 | P0 | `ios/Podfile`, `project.pbxproj` | iOS не собирался: `workmanager_apple` требует 14.0, Xcode 27 — ≥ 15.0 (у части подов 9.0/11.0) → target 15.0 + `post_install` |
| 23 | P1 | `webview_page.dart` | гибель WebContent (`WKErrorWebContentProcessTerminated`, код 2) → `onPageFinished` не приходит, «Cargando...» навсегда → 1 автоперезапуск, затем экран ошибки с «Reintentar»; найдено на симуляторе, тест воспроизводит |

---

## 5. Не исправлено — нужно решение владельца

| Тема | Почему не трогал | Рекомендация |
|---|---|---|
| `applicationId`/`namespace` = `com.example.stm_app`; release подписан debug-ключом ✔︎ | Google Play не примет `com.example`; смена ID = новое приложение для установленных копий | выбрать ID (на iOS уже `com.liberontech.stmapp`), завести keystore |
| WebView-обёртка сайтов IM (политики сторов) | продуктовое решение | письмо в `pci@imm.gub.uy` за разрешением; либо Custom Tabs вместо WebView для Mi STM/Recarga |
| Иконка с госсимволикой | дизайн | заменить щит/солнце на нейтральный символ |
| Вход в Mi STM внутри WebView + `BalanceScraper` | убирает фичу баланса | Custom Tabs/SFSafariViewController, отказ от скрейпинга баланса |
| `ComoIrScraper` фактически не работает ✔︎ | удаление фичи | Ionic SPA: `onPageFinished` срабатывает один раз на пустой странице; заменить нативным выбором остановки (§6) |
| Hive открыт одновременно в UI- и WorkManager-изоляте ✔︎ | миграция хранилища | Hive 2.x не многоизолятный → `hive_ce` с `IsolatedHive` или `shared_preferences` для фоновых данных |
| iOS: фон и виджет не настроены ✔︎ | нужен Xcode, App Group, BGTask | `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`, регистрация в AppDelegate, App Group для home_widget |
| WorkManager ≥ 15 мин | ограничение Android | порог алерта 5 мин часто проскакивает — см. «режим ожидания» в §6 |
| Один `WebViewController` на 4 вкладки ✔︎ | рефакторинг навигации | история вкладок смешивается, перезагрузка при каждом переключении; `_nativePageCache` кэширует Widget, а не State — `IndexedStack` |
| Устаревшие зависимости | апгрейд ломает API | `local_auth` 3.x удалил `AuthenticationOptions` ✔︎, `workmanager` 0.10, `hive_flutter` заброшен; `geolocator`, `shared_preferences` не используются |
| UA «Android 10 / Chrome 120» и на iOS ✔︎ | влияет на сайт STM | убрать подмену или задавать по платформе — проверить вручную |
| «colectivo» → «ómnibus» ✔︎ | тексты | в Уругвае говорят «ómnibus» |
| `NSLocationAlwaysAndWhenInUseUsageDescription` ✔︎ | не нужен | удалить из Info.plist |

---

## 6. Предложения (с опорой на API и лицензии)

1. **Официальный API через свой прокси.** Зарегистрироваться на `api.montevideo.gub.uy`,
   держать `client_secret` на небольшом бэкенде (Cloudflare Worker и т.п.) с кэшем токена
   и ответов. Это легальный канал с явными условиями и защита от поломок, как с `stmonlineRest`.
2. **Поиск остановок без номера.** WFS `imm:v_uptu_paradas` (`srsName=EPSG:4326`) или
   `/buses/busstops` → «остановки рядом» по геолокации и поиск по улице.
3. **«Ver en Cómo Ir»** на карточке остановки — deep link `/comoir/parada?numero={id}`:
   официальная интеграция без скрейпинга.
4. **Новости транспорта.** `notificacion/mensajes` — объезды и изменения линий, которые
   публикует сама IM, нативным списком.
5. **Индикатор качества данных.** `pci.../buses/control` — «данные GPS CUTCSA сейчас 40%»,
   чтобы пользователь понимал, почему ETA неточны.
6. **Доступность.** Поля `accesibilidad`/`tipoAccesibilidad` (и `access` в официальном API) —
   значок низкопольного автобуса.
7. **Офлайн-расписание.** GTFS (`google_transit.zip`) или набор «Horarios por parada» —
   работает без сети. Требует Nota de Origen (§3).
8. **Режим ожидания.** Пока пользователь ждёт автобус — опрос раз в 20–30 с с постоянным
   уведомлением (foreground service, тип `shortService`/`dataSync` по правилам Play)
   вместо 15-минутного WorkManager.
9. **Карта автобуса.** У `real:true` есть `coordinates` — показать, где сейчас автобус.

---

## 7. Как проверялось

- `flutter analyze` — без замечаний; `flutter test` — 20/20 (тест на гибель WebContent
  падает без исправления №23 и проходит с ним).
- Новый `MvdApiService` вызван против живого API: остановка 3140 → «AV RAMON ANADOR y
  TIBURCIO GOMEZ», 3 рейса (1 GPS, 2 по расписанию), id 999999 → `StopNotFoundException`.
- `flutter build apk --debug` — собирается (Kotlin-виджет и манифест компилируются).
- **iOS-симулятор** (iPhone 17 Pro Max, iOS 26.2, Xcode 27.1), проверено вживую:
  добавление остановки 3140 — реальное название, рейс по GPS выделен, рейсы по расписанию
  с часами; несуществующая 31409 — «No existe la parada»; колокольчик — системный запрос
  уведомлений в момент включения, `BackgroundWorker.sync()` без ошибок; Info — новый текст
  и ссылка; включение замка — системный запрос кода (не вводился); данные переживают
  перезапуск; `HomeWidget` без App Group на iOS — ошибка перехвачена, приложение работает.
- Наблюдение: вход Mi STM — цепочка `stm.gub.uy` → `ih.montevideo.gub.uy/samlsso` →
  `auth.iduruguay.gub.uy` → `mi.iduruguay.gub.uy/login`, то есть **ID Uruguay** во встроенном WebView.
- **Не удалось проверить:** страницы WebView — в этом симуляторе процесс WebKit падает
  у всех, включая Safari (проблема среды, не приложения); Android-эмулятор не стартует
  (неполный образ `android-36.1`). Вручную на устройстве: геолокация в Cómo Ir, кнопки
  виджета, биометрия, фоновые алерты.
- Тулчейн: Flutter 3.41.1 + Xcode 27 — `flutter build ios --simulator` падает
  (`lipo -verify_arch` в Xcode 27 принимает одну архитектуру, Flutter передаёт две);
  `flutter run -d <симулятор>` работает. Обновить Flutter.

## Источники

- [Montevideo API — каталог](https://api.montevideo.gub.uy/docs), [документация transporte público](https://api.montevideo.gub.uy/apidocs/publictransport), [manual de conexión](https://api.montevideo.gub.uy/docs/manualdeconexion.pdf)
- [Cómo Ir (web)](https://m.montevideo.gub.uy/comoir/)
- [Catálogo Nacional de Datos Abiertos](https://catalogodatos.gub.uy/), [términos](https://catalogodatos.gub.uy/terminos-catalogodatos.pdf)
- [Decreto 54/017 (IMPO)](https://impo.com.uy/bases/decretos/54-2017), [Normativa de Datos Abiertos, AGESIC](https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/2020-09/Normativa%20de%20Datos%20Abiertos.pdf) — §4.4, текст лицензии v0.1
- [Google Play — Spam and Minimum Functionality](https://support.google.com/googleplay/android-developer/answer/9899034), [Misleading Claims](https://support.google.com/googleplay/android-developer/answer/9888077)
- [App Store Review Guidelines 4.2, 5.2](https://developer.apple.com/app-store/review/guidelines/)
