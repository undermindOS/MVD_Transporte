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
