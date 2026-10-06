import 'package:flutter/material.dart';

import 'screens/remote_home_screen.dart';

class PyCleanRemoteApp extends StatelessWidget {
  const PyCleanRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PyClean Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF89B4FA),
          surface: Color(0xFF2A2A3C),
        ),
      ),
      home: const RemoteHomeScreen(),
    );
  }
}
