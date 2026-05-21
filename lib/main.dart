// lib/main.dart
//
// Captain's Sidestick — entry point.
// Bootstraps services, locks portrait orientation, applies dark navy theme,
// and renders the main cockpit screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';           // add provider to pubspec below
import 'settings_model.dart';
import 'websocket_service.dart';
import 'sensor_service.dart';
import 'cockpit_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colours — match the PC app exactly
// ─────────────────────────────────────────────────────────────────────────────
const Color kNavy   = Color(0xFF0D1B2A);
const Color kNavy2  = Color(0xFF152233);   // slightly lighter panels
const Color kAmber  = Color(0xFFE0A020);
const Color kAmberD = Color(0xFFB07010);   // pressed state
const Color kRed    = Color(0xFFD03030);
const Color kGreen  = Color(0xFF30C050);
const Color kText   = Color(0xFFDDE8F0);
const Color kDim    = Color(0xFF4A6070);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — pilot holds phone upright
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Immersive full-screen — hide status & nav bars
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Load settings before first frame
  final settings = SettingsModel();
  await settings.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<WebSocketService>(
          create: (_) => WebSocketService(settings),
        ),
        ChangeNotifierProvider<SensorService>(
          create: (_) => SensorService(settings),
        ),
      ],
      child: const CaptainsSidestickApp(),
    ),
  );
}

class CaptainsSidestickApp extends StatelessWidget {
  const CaptainsSidestickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Captain's Sidestick",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kNavy,
        colorScheme: const ColorScheme.dark(
          primary:   kAmber,
          secondary: kAmber,
          surface:   kNavy2,
          error:     kRed,
        ),
        // Sliders
        sliderTheme: SliderThemeData(
          activeTrackColor:   kAmber,
          inactiveTrackColor: kDim,
          thumbColor:         kAmber,
          overlayColor:       kAmber.withOpacity(0.2),
          trackHeight:        6,
        ),
        // Buttons
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAmber,
            foregroundColor: kNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        // Input fields
        inputDecorationTheme: InputDecorationTheme(
          filled:           true,
          fillColor:        kNavy2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kDim),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kDim),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kAmber, width: 2),
          ),
          labelStyle:    const TextStyle(color: kDim),
          hintStyle:     const TextStyle(color: kDim),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: kText, fontSize: 14),
          bodySmall:  TextStyle(color: kDim,  fontSize: 11),
          labelLarge: TextStyle(color: kNavy, fontWeight: FontWeight.bold),
        ),
        fontFamily: 'monospace',
      ),
      home: const CockpitScreen(),
    );
  }
}
