import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/widget_refresh_settings.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/widget_refresh_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final stored = <String, Object?>{};
  final redraws = <String>[];
  var failSave = false;

  setUp(() {
    stored.clear();
    redraws.clear();
    failSave = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'getWidgetData':
          return stored[args['id']];
        case 'saveWidgetData':
          if (failSave) throw PlatformException(code: 'write_failed');
          stored[args['id'] as String] = args['data'];
          return true;
        case 'updateWidget':
          redraws.add(args['android'] as String);
          return true;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'new installs use 15 minutes; invalid values cannot schedule fast polling',
    () async {
      expect(await WidgetRefreshSettings.load(), 15);
      stored[WidgetRefreshSettings.keyMinutes] = 1;
      expect(await WidgetRefreshSettings.load(), 15);
      await expectLater(WidgetRefreshSettings.save(1), throwsArgumentError);
    },
  );

  test(
    'changing frequency persists it and reapplies all placed providers',
    () async {
      for (final minutes in [30, 60, 0, 15]) {
        redraws.clear();
        await WidgetRefreshSettings.save(minutes);
        expect(await WidgetRefreshSettings.load(), minutes);
        expect(redraws, [
          'TimbreProximoWidget',
          'TimbreParadaWidget',
          'TimbreMisParadasWidget',
          'TimbreAnchoWidget',
          'TimbreFlipWidget',
        ]);
      }
    },
  );

  testWidgets(
    'a choice survives reopening and Manual still offers button refresh',
    (tester) async {
      Widget app() => MaterialApp(
        theme: buildTimbreTheme(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: WidgetRefreshOptions(),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      expect(await WidgetRefreshSettings.load(), 30);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.bySemanticsLabel('30 min'))
            .properties
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      expect(await WidgetRefreshSettings.load(), 0);
      expect(
        find.textContaining('para actualizar cuando quieras'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a failed write leaves the last saved selection and offers retry',
    (tester) async {
      failSave = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTimbreTheme(),
          home: const Scaffold(body: WidgetRefreshOptions()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 h'));
      await tester.pumpAndSettle();
      expect(await WidgetRefreshSettings.load(), 15);
      expect(
        find.text('No se pudo guardar. Tocá para reintentar.'),
        findsOneWidget,
      );
      expect(redraws, isEmpty);
    },
  );
}
