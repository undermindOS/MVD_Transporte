# MVD_Transporte

Неофициальное Flutter-приложение для общественного транспорта Монтевидео: личный кабинет
Mi STM и пополнение карты (WebView официального сайта), Cómo Ir, а также нативная вкладка
«Mis paradas» — сохранённые остановки и маршруты с временем прибытия автобусов,
уведомления и Android-виджет.

Не аффилировано с Intendencia de Montevideo.

## Данные

Время прибытия и названия остановок — открытые сервисы Intendencia de Montevideo,
которые использует веб-версия Cómo Ir (`api.montevideo.gub.uy/transporteRest`).
Поиск остановок рядом («Paradas cercanas») — открытый WFS GeoServer IM
(`geoserver.montevideo.gub.uy/geoserver/ows`, слой `imm:v_uptu_paradas`, без авторизации).
Кнопка «Ver en Cómo Ir» открывает остановку по deep link `m.montevideo.gub.uy/comoir/parada?numero={id}`.
Карта API, условия использования и правовые ограничения — в [docs/REVIEW.md](docs/REVIEW.md).

## Запуск

```bash
flutter pub get
flutter test
flutter run
```

## Структура

- `lib/services/mvd_api_service.dart` — клиент API (ETA, остановки)
- `lib/services/nearby_stops_service.dart` — остановки рядом (геолокация + WFS)
- `lib/services/background_worker.dart` — фоновая проверка алертов (WorkManager, ≥15 мин)
- `lib/ui/stops_page.dart` — остановки и маршруты
- `lib/ui/webview_page.dart` — вкладки, WebView, биометрический замок
- `android/.../MVDTransporteWidgetProvider.kt` — виджет домашнего экрана

История изменений — [CHANGELOG.md](CHANGELOG.md).
