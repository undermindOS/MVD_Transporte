// Servicios, Novedades, Horarios and Info on the Timbre design system:
// what each screen promises the user, independent of pixels. Real fonts
// and a phone-sized screen, so overflow checks mean something.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/models/transport_news.dart';
import 'package:stm_app/services/official_sites.dart';
import 'package:stm_app/ui/info_page.dart';
import 'package:stm_app/ui/news_list.dart';
import 'package:stm_app/ui/schedule_page.dart';
import 'package:stm_app/ui/services_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/empty_state.dart';
import 'package:stm_app/ui/widgets/led_matrix.dart';
import 'package:stm_app/ui/widgets/line_badge.dart';
import 'package:stm_app/ui/widgets/pixel_icon.dart';
import 'package:stm_app/ui/widgets/segmented.dart';
import 'package:stm_app/ui/widgets/timbre_app_bar.dart';
import 'package:stm_app/ui/widgets/timbre_bus.dart';

import 'support/layout.dart';

/// [textScale] 2.0 is the largest Android font size ("Largest", Android 14+).
Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      theme: buildTimbreTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

final _news = [
  TransportNews(
      id: 180,
      title: 'Líneas patrimoniales recorren la Ciudad Vieja',
      summary: 'Este sábado y domingo, de 10 a 18 horas',
      body: '',
      date: DateTime(2026, 10, 2)),
  TransportNews(
      id: 179,
      title: 'Desvíos por Expo Prado',
      summary: '',
      body: '',
      date: DateTime(2026, 9, 11)),
];

const _passes = [
  ScheduledPass(
      line: '145', destination: 'PLAZA ESPAÑA', time: '23:31', hhmm: 2331),
  ScheduledPass(
      line: '143', destination: 'CIUDADELA', time: '23:54', hhmm: 2354),
  ScheduledPass(
      line: '494', destination: 'PASO DE LA ARENA', time: '0:17', hhmm: 17),
];

Widget _services(List<OfficialSite> opened) =>
    Scaffold(body: ServicesPage(onOpen: opened.add));

Widget _newsList({int? readBefore = 179, bool failed = false}) => Scaffold(
      body: NewsList(
        news: _news,
        readBefore: readBefore,
        isLoading: false,
        failed: failed,
        onRefresh: () async {},
      ),
    );

Widget _schedule({List<ScheduledPass> passes = _passes}) => SchedulePage(
      stop: BusStop(id: 3140, name: 'AV RAMON ANADOR y TIBURCIO GOMEZ'),
      now: DateTime(2026, 10, 17, 23, 33),
      fetch: (id, day, h, m) async => passes,
    );

/// [page] pushed over a first screen, as the app opens Info and Horarios.
Widget _pushed(Widget page) => Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('abrir'),
        ),
      ),
    );

Widget _info({Uri? privacy}) => InfoPage(
      biometricLockEnabled: false,
      onToggleBiometricLock: (v) async => v,
      privacyPolicyUrl: privacy,
    );

void main() {
  setUpAll(loadBundledFonts);

  group('Servicios', () {
    testWidgets('card services and Cómo Ir in two sections', (tester) async {
      usePhoneScreen(tester);
      final opened = <OfficialSite>[];
      await tester.pumpWidget(_app(_services(opened)));

      final card = tester.getTopLeft(find.text('Tu tarjeta STM')).dy;
      final travel = tester.getTopLeft(find.text('Para moverte')).dy;
      for (final t in ['Mi STM', 'Recarga', 'Avisos']) {
        expect(tester.getTopLeft(find.text(t)).dy, inExclusiveRange(card, travel));
      }
      expect(tester.getTopLeft(find.text('Cómo Ir')).dy, greaterThan(travel));
      expect(find.textContaining('Timbre MVD no es una app oficial'),
          findsOneWidget);

      await tester.tap(find.text('Cómo Ir'));
      expect(opened, [OfficialSite.comoIr]);
    });

    testWidgets('screen readers hear the destination and can open it',
        (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      final opened = <OfficialSite>[];
      await tester.pumpWidget(_app(_services(opened)));

      final miStm =
          RegExp(r'^Mi STM\. .*Abre el sitio oficial en el navegador$');
      expect(tester.getSemantics(find.bySemanticsLabel(miStm)),
          isSemantics(isButton: true, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel(miStm));
      expect(opened, [OfficialSite.miStm]);
      handle.dispose();
    });

    testWidgets('tiles stop growing on tablets', (tester) async {
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_services([])));

      final tile = tester.getSize(find.byType(AspectRatio).first);
      expect(tile.width, lessThanOrEqualTo(168));
    });
  });

  group('Novedades', () {
    testWidgets('only unread news get NUEVA and a filled date',
        (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_newsList()));

      expect(find.text('NUEVA'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('SET'), findsOneWidget); // Uruguay: setiembre
      BoxDecoration tileOf(String day) => tester
          .widget<Container>(find
              .ancestor(of: find.text(day), matching: find.byType(Container))
              .first)
          .decoration! as BoxDecoration;
      // Unread: an inset LED display; read: an empty frame
      expect(tileOf('02').color, TimbreColors.noche);
      expect(tileOf('11').color, isNull);
    });

    testWidgets('never opened: everything is new', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_newsList(readBefore: null)));
      expect(find.text('NUEVA'), findsNWidgets(2));
    });

    testWidgets('each row is one phrase that opens the message',
        (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_newsList()));

      const unread = 'Nueva. 2 de octubre. Líneas patrimoniales recorren la '
          'Ciudad Vieja. Este sábado y domingo, de 10 a 18 horas';
      expect(tester.getSemantics(find.bySemanticsLabel(unread)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(find.bySemanticsLabel('11 de setiembre. Desvíos por Expo Prado'),
          findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel(unread));
      await tester.pumpAndSettle();
      expect(find.text('02/10/2026'), findsOneWidget); // the detail sheet
      handle.dispose();
    });

    testWidgets('offline is a warning, not "Sin novedades"', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_newsList(failed: true)));
      expect(find.text('No se pudo actualizar. Deslizá para reintentar'),
          findsOneWidget);
      expect(find.text('SIN NOVEDADES'), findsNothing);
    });
  });

  group('Horarios', () {
    testWidgets('grouped by hour, midnight in between', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_schedule()));
      await tester.pumpAndSettle();

      expect(find.text('AV RAMON ANADOR y TIBURCIO GOMEZ'), findsOneWidget);
      expect(find.text(' · 3140'), findsOneWidget);
      expect(find.text('Desde 23:30'), findsOneWidget);
      final midnight = tester.getTopLeft(find.text('Después de medianoche')).dy;
      expect(tester.getTopLeft(find.text('23 h')).dy, lessThan(midnight));
      expect(tester.getTopLeft(find.text('0 h')).dy, greaterThan(midnight));
    });

    testWidgets('the hours are labels, never lit', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_schedule()));
      await tester.pumpAndSettle();

      for (final hour in ['23 h', '0 h']) {
        expect(tester.widget<Text>(find.text(hour)).style!.color,
            TimbreColors.etiquetaCartel);
      }
      expect(tester.widget<Text>(find.text('23:31')).style!.color,
          TimbreColors.etiquetaCartel);
    });

    testWidgets('a failed load is a red LED that says what to do',
        (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(SchedulePage(
        stop: BusStop(id: 3140, name: 'AV RAMON ANADOR y TIBURCIO GOMEZ'),
        now: DateTime(2026, 10, 17, 23, 33),
        fetch: (id, day, h, m) async => null,
      )));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo cargar el horario. Revisá la conexión.'),
          findsOneWidget);
      final icon = tester.widget<PixelIcon>(find.byWidgetPredicate(
          (w) => w is PixelIcon && w.glyph == PixelGlyphs.warning));
      expect(icon.color, TimbreColors.rojoLed);
    });

    testWidgets('timetable badges are outlined, never live', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_schedule()));
      await tester.pumpAndSettle();

      final badges = tester.widgetList<LineBadge>(find.byType(LineBadge));
      expect(badges, hasLength(3));
      expect(badges.every((b) => !b.live), isTrue);
    });

    testWidgets('rows read as one sentence', (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_schedule()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('23:31, línea 145 a Plaza España'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              'Horarios de la parada 3140, Av Ramon Anador y Tiburcio Gomez'),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('TimbreSegmented', () {
    testWidgets('selected segment is announced; the others can be picked',
        (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      final picks = <int>[];
      await tester.pumpWidget(_app(Scaffold(
        body: TimbreSegmented<int>(
          values: const [3, 5, 10],
          selected: 3,
          labelOf: (v) => '$v min',
          onChanged: picks.add,
        ),
      )));

      expect(
          tester.getSemantics(find.text('3 min')),
          isSemantics(
              label: '3 min',
              isButton: true,
              isSelected: true,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: false));
      expect(
          tester.getSemantics(find.text('10 min')),
          isSemantics(
              label: '10 min',
              isButton: true,
              isSelected: false,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: true));

      await tester.tap(find.text('3 min'));
      await tester.tap(find.text('10 min'));
      tester.semantics.tap(find.semantics.byLabel('5 min'));
      expect(picks, [10, 5]);
      handle.dispose();
    });
  });

  group('Info', () {
    testWidgets('unofficial notice and links', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_info()));

      expect(find.text('NO OFICIAL'), findsOneWidget);
      expect(find.textContaining('No está afiliada con la Intendencia'),
          findsOneWidget);
      expect(find.text('Código fuente'), findsOneWidget);
      expect(find.text('Contacto'), findsOneWidget);
      // No public privacy policy yet: no dead link
      expect(find.text('Política de privacidad'), findsNothing);
    });

    testWidgets('links say where they open', (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_info()));

      for (final link in [
        'Código fuente, github.com/undermindOS/MVD_Transporte, '
            'se abre en el navegador',
        'Contacto, zhongnanhaii@yahoo.com, se abre en tu app de correo',
      ]) {
        final finder = find.bySemanticsLabel(link);
        await tester.ensureVisible(finder);
        expect(tester.getSemantics(finder),
            isSemantics(isButton: true, hasTapAction: true),
            reason: link);
      }
      handle.dispose();
    });

    testWidgets('privacy policy row once it is published', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(
          _app(_info(privacy: Uri.parse('https://example.com/privacidad'))));
      expect(find.text('Política de privacidad'), findsOneWidget);
    });
  });

  // The brand outside the lists: the identity bar on every screen, the
  // blue surfaces as boards, the bus when a list is empty
  group('Timbre identity', () {
    for (final (name, page, title) in [
      ('Info', _info(), 'INFO'),
      ('Horarios', _schedule(), 'HORARIOS'),
    ]) {
      testWidgets('$name: identity bar with the plate and the back arrow',
          (tester) async {
        usePhoneScreen(tester);
        await tester.pumpWidget(_app(_pushed(page)));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        final bar = find.byType(AppBar);
        for (final part in [
          find.byType(CartelCompacto),
          find.byType(BackButton),
          find.byType(LedMatrix),
          find.text(title),
        ]) {
          expect(find.descendant(of: bar, matching: part), findsOneWidget);
        }
      });
    }

    testWidgets('Servicios tiles and unread dates are small boards',
        (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_services([])));
      expect(find.byType(LedMatrix), findsNWidgets(4));

      await tester.pumpWidget(_app(_newsList()));
      final unread = find
          .ancestor(of: find.text('02'), matching: find.byType(Container))
          .first;
      expect(find.descendant(of: unread, matching: find.byType(LedMatrix)),
          findsOneWidget);
      expect(find.byType(LedMatrix), findsOneWidget); // read ones stay plain
    });

    testWidgets('empty lists: a sign with nothing to announce',
        (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      final bus = find.descendant(
          of: find.byType(TimbreEmptyState), matching: find.byType(TimbreBus));
      await tester.pumpWidget(_app(Scaffold(
        body: NewsList(
          news: const [],
          readBefore: null,
          isLoading: false,
          failed: false,
          onRefresh: () async {},
        ),
      )));
      expect(find.text('SIN NOVEDADES'), findsOneWidget);
      expect(find.bySemanticsLabel('Sin novedades'), findsOneWidget);
      expect(bus, findsOneWidget);

      await tester.pumpWidget(_app(_schedule(passes: const [])));
      await tester.pumpAndSettle();
      expect(find.text('SIN PASADAS'), findsOneWidget);
      expect(find.bySemanticsLabel('Sin pasadas para este horario'),
          findsOneWidget);
      expect(find.textContaining('Probá con otro día'), findsOneWidget);
      expect(bus, findsOneWidget);
      handle.dispose();
    });
  });

  // Older riders use big fonts. Nothing may overflow (an overflow fails
  // the test) and the header must not cut the page title.
  group('Largest system font', () {
    for (final (name, screen) in [
      ('Servicios', _services([])),
      ('Novedades', _newsList()),
      ('Horarios', _schedule()),
      ('Info', _info(privacy: Uri.parse('https://example.com/privacidad'))),
    ]) {
      testWidgets(name, (tester) async {
        usePhoneScreen(tester);
        await tester.pumpWidget(_app(screen, textScale: 2));
        await tester.pumpAndSettle();
      });
    }

    testWidgets('header plate and page title', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => Scaffold(
            appBar: buildTimbreAppBar(
              context,
              title: 'Servicios',
              subtitle: 'Sitios oficiales, en tu navegador',
            ),
          ),
        ),
        textScale: 2,
      ));

      final bar = tester.getRect(find.byType(AppBar));
      expect(tester.getRect(find.text('SERVICIOS')).bottom,
          lessThanOrEqualTo(bar.bottom));
      expect(tester.getRect(find.text('Sitios oficiales, en tu navegador')).bottom,
          lessThanOrEqualTo(bar.bottom));
      // A second line, not "…"
      final subtitle = tester.renderObject<RenderParagraph>(
          find.text('Sitios oficiales, en tu navegador'));
      expect(subtitle.didExceedMaxLines, isFalse);
    });

    // Horarios names the stop in full: a long name wraps, the number
    // follows it, nothing ends in "…"
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Text at ${scale}x: Horarios shows the whole stop name',
          (tester) async {
        usePhoneScreen(tester);
        await tester.pumpWidget(_app(
            _schedule(passes: const [
              ScheduledPass(
                  line: '538',
                  destination: 'GRAL FLORES Y JOSÉ SERRATO',
                  time: '23:40',
                  hhmm: 2340),
            ]),
            textScale: scale));
        await tester.pumpAndSettle();

        final bar = tester.getRect(find.byType(AppBar));
        final name = find.text('AV RAMON ANADOR y TIBURCIO GOMEZ');
        expect(tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
            isFalse);
        expect(tester.getRect(name).bottom, lessThanOrEqualTo(bar.bottom));
        if (scale == 2) {
          // Two lines of 17 px text at 2x
          expect(tester.getSize(name).height, greaterThan(17 * 2 * 1.5));
        }
        final number = tester.getRect(find.text(' · 3140'));
        expect(number.right, lessThanOrEqualTo(390 - 16));
        expect(number.bottom, lessThanOrEqualTo(bar.bottom));
        // The destination of a pass takes two lines before it is cut
        final destination = tester.renderObject<RenderParagraph>(
            find.text('GRAL FLORES Y JOSÉ SERRATO'));
        expect(destination.didExceedMaxLines, isFalse);
      });
    }

    testWidgets('the longest page title shrinks to fit, never cut',
        (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => Scaffold(
            appBar: buildTimbreAppBar(context, title: 'Mis paradas'),
          ),
        ),
        textScale: 2,
      ));

      final title =
          tester.renderObject<RenderParagraph>(find.text('MIS PARADAS'));
      expect(title.didExceedMaxLines, isFalse);
      // Inside the screen, after the side margin
      expect(tester.getRect(find.byType(FittedBox).first).right,
          lessThanOrEqualTo(390 - 16));
    });
  });
}
