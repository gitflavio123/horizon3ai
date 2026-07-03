import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/pentest_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => PentestProvider()),
      ],
      child: const Horizon3App(),
    ),
  );
}

class Horizon3App extends StatelessWidget {
  const Horizon3App({super.key});

  @override
  Widget build(BuildContext context) {
    // Custom dark cyber-security theme
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0A0C14),
      primaryColor: const Color(0xFF00E5FF),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        secondary: Color(0xFF7C4DFF),
        surface: Color(0xFF141724),
        error: Color(0xFFFF5252),
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        onSurface: Color(0xFFECEFF1),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          color: const Color(0xFFECEFF1),
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 14,
          color: const Color(0xFFB0BEC5),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF141724),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF22263C), width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF181C2E),
        hintStyle: const TextStyle(color: Color(0xFF607D8B)),
        labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E3456), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF5252), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF5252), width: 2),
        ),
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Horizon3.ai Pentest Dashboard',
      theme: darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Image(
                    image: AssetImage('assets/images/tesys_logo.png'),
                    height: 40,
                  ),
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
              ),
              SizedBox(height: 16),
              Text(
                'Caricamento configurazioni...',
                style: TextStyle(color: Color(0xFF00E5FF), letterSpacing: 1),
              ),
            ],
          ),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const DashboardScreen();
    }

    return const LoginScreen();
  }
}
