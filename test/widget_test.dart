// This is a basic Flutter widget test for MVD Transporte App.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/main.dart';

void main() {
  testWidgets('MVD Transporte App loads with bottom navigation', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MiTransporteMVDApp());

    // Verify that bottom navigation bar exists with all 5 items.
    expect(find.byType(NavigationBar), findsOneWidget);

    // Verify navigation labels are present.
    expect(find.text('Inicio'), findsWidgets); // AppBar title + nav label
    expect(find.text('Recarga'), findsOneWidget);
    expect(find.text('Mis paradas'), findsOneWidget);
    expect(find.text('Cómo Ir'), findsOneWidget);
    expect(find.text('Avisos'), findsOneWidget);

    // Verify navigation icons are present.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.credit_card_outlined), findsOneWidget);
    expect(find.byIcon(Icons.directions_bus_outlined), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

    // Verify Info button in AppBar.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('Bottom navigation interaction test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MiTransporteMVDApp());

    // Wait for initial load
    await tester.pumpAndSettle();

    // Tap on 'Recarga' tab (index 1)
    await tester.tap(find.text('Recarga'));
    await tester.pump();

    // Verify that the navigation item is still present after tap
    expect(find.text('Recarga'), findsWidgets); // Nav label + possibly AppBar

    // Tap on 'Avisos' tab (index 4)
    await tester.tap(find.text('Avisos'));
    await tester.pump();

    // Verify that the navigation item is still present after tap
    expect(find.text('Avisos'), findsWidgets);
  });
}
