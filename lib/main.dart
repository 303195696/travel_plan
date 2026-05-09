import 'package:flutter/material.dart';
import 'package:travel_plan/screens/home_map_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TravelPlanApp());
}

class TravelPlanApp extends StatelessWidget {
  const TravelPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '出行规划',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeMapPage(),
    );
  }
}
