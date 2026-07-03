import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:horizon3ai/screens/login_screen.dart';
import 'package:horizon3ai/providers/auth_provider.dart';

void main() {
  testWidgets('Horizon3 App Login UI Smoke Test', (WidgetTester tester) async {
    // Build the LoginScreen directly wrapped in providers (without calling initialize() to avoid secure storage platform channel calls)
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Let the widget render
    await tester.pump();

    // Verify that the login screen title and brand text are present.
    expect(find.text('HORIZON3.AI'), findsOneWidget);
    expect(find.text('NodeZero API Integration'), findsOneWidget);
    expect(find.text('Configura Connessione Portal'), findsOneWidget);
    expect(find.text('COLLEGA API'), findsOneWidget);
  });
}
