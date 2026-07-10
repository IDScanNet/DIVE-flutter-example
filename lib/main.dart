import 'package:flutter/material.dart';
import 'screens/dive_sdk_screen.dart';
import 'screens/dive_online_sdk_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DIVE SDK Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('DIVE SDK Demo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'DIVE SDK'),
              Tab(text: 'DIVE Online SDK'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [DiveSdkScreen(), DiveOnlineSdkScreen()],
        ),
      ),
    );
  }
}
