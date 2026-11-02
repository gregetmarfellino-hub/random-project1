import 'package:flutter/material.dart';

import 'screens/device_hub_screen.dart';

class PyCleanRemoteApp extends StatelessWidget {
  const PyCleanRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PyClean',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF11111B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF89B4FA),
          secondary: Color(0xFFCBA6F7),
          surface: Color(0xFF1E1E2E),
          error: Color(0xFFF38BA8),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF11111B),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        dividerColor: const Color(0x3345475A),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF2A2A3C),
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E2E),
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0x3345475A),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF89B4FA),
            ),
          ),
        ),
      ),
      home: const DeviceHubScreen(),
    );
  }
}
