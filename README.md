# MVD_Transporte

Неофициальное Flutter-приложение для общественного транспорта Монтевидео: нативная вкладка
«Mis paradas» — сохранённые остановки и маршруты с временем прибытия автобусов,
уведомления и Android-виджет, — и быстрый доступ к официальным сайтам (Mi STM, пополнение
карты, Cómo Ir, Avisos), которые открываются в системном браузере (Custom Tabs /
SFSafariViewController), а не во встроенном WebView.

Не аффилировано с Intendencia de Montevideo.

## Данные

Время прибытия, расписания и названия остановок — открытые сервисы Intendencia de Montevideo,
которые использует веб-версия Cómo Ir (`api.montevideo.gub.uy/transporteRest`).
Кондиционер и «cero emisiones» у прибывающих автобусов — официальный API IM
(`api.montevideo.gub.uy/api/transportepublico`, OAuth2, 14 запросов в минуту на ключ). Его ключ
живёт только в прокси на Cloudflare Workers ([proxy/](proxy/README.md)); если приложение собрано с
адресом прокси, все эти запросы идут через него (маршруты `/v1`), иначе — напрямую в `transporteRest`
и без данных о комфорте.
Поиск остановок рядом («Paradas cercanas») — открытый WFS GeoServer IM
(`geoserver.montevideo.gub.uy/geoserver/ows`, слой `imm:v_uptu_paradas`, без авторизации).
Поиск остановки по названиям улиц («Buscar por calles») — каталог остановок официального API
(`/v1/catalog/stops` прокси, хранится на устройстве сутки); есть только в сборке с прокси.
Кнопка «Ver en Cómo Ir» открывает остановку по deep link `m.montevideo.gub.uy/comoir/parada?numero={id}`.
Карта API, условия использования и правовые ограничения — в [docs/REVIEW.md](docs/REVIEW.md).

## Запуск

```bash
flutter pub get
flutter test
flutter run
```

Через прокси (адрес Worker после деплоя или `http://127.0.0.1:8787` при `npm run dev` в `proxy/`):

```bash
flutter run --dart-define=MVD_PROXY_URL=https://mvd-transporte-proxy.<subdomain>.workers.dev
```

Сборки для сторов — с тем же `--dart-define`.

## Структура

- `lib/services/mvd_api_service.dart` — клиент API (ETA, остановки, расписания; прокси или напрямую;
  каталог остановок и поиск по улицам — только через прокси)
- `proxy/` — Cloudflare Worker: маршруты `/v1`, Durable Object `ImGateway` с ключом официального API
- `lib/services/nearby_stops_service.dart` — остановки рядом (геолокация + WFS)
- `lib/services/background_worker.dart` — фоновая проверка алертов (WorkManager, ≥15 мин)
- `lib/models/bus_wait.dart`, `lib/services/bus_wait_service.dart`, `lib/services/bus_wait_task.dart` —
  «Estoy esperando»: Android — служба переднего плана (опрос раз в 30 с), iOS — напоминание на
  прогнозное время
- `lib/ui/stops_page.dart` — остановки и маршруты
- `lib/ui/home_page.dart` — вкладки, биометрический замок
- `lib/ui/services_page.dart`, `lib/services/official_sites.dart` — официальные сайты в системном браузере
- `android/.../MVDTransporteWidgetProvider.kt` — виджет домашнего экрана

История изменений — [CHANGELOG.md](CHANGELOG.md).
