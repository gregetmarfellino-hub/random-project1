import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;

// Fungsi ini jalan di BACKGROUND, bahkan pas aplikasinya ditutup (kill)
@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri?.host == 'execute_clean') {
    print("⚡ WIDGET DIPENCET DARI HOME SCREEN!");
    
    // Nanti IP 192.168.X.X ini kita ganti sama IP PC lu
    final pcUrl = Uri.parse('http://192.168.1.100:5000/api/trigger-clean'); 
    
    try {
      await http.post(pcUrl);
      print("Sinyal berhasil ditembak ke PC!");
    } catch (e) {
      print("Gagal nembak PC: \$e");
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Daftarin fungsi background ke sistem Home Widget
  HomeWidget.registerBackgroundCallback(backgroundCallback);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E2E), // Catppuccin Base
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.settings_remote, size: 80, color: Color(0xFF89B4FA)),
              SizedBox(height: 20),
              Text(
                'PYCLEAN MOBILE AGENT',
                style: TextStyle(
                  color: Color(0xFFCDD6F4), 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Aplikasi ini berjalan di latar belakang.\nSilakan pasang Widget di Home Screen Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA6ADC8), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}