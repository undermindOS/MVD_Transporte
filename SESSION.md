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
