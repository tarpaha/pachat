import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() {
  runApp(const PaChatApp());
}

class PaChatApp extends StatelessWidget {
  const PaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
