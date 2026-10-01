import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'theme.dart';

void main() {
  runApp(const GlukWaveApp());
}

class GlukWaveApp extends StatefulWidget {
  const GlukWaveApp({super.key});

  @override
  State<GlukWaveApp> createState() => _GlukWaveAppState();
}

class _GlukWaveAppState extends State<GlukWaveApp> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _appState,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Gluk Wave',
        theme: buildGlukWaveTheme(),
        home: const _RootScreen(),
      ),
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  int _currentTab = 0;

  static const _pages = [HomeScreen(), LibraryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (value) => setState(() => _currentTab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.waves_rounded), label: 'Волна'),
          NavigationDestination(icon: Icon(Icons.library_music_rounded), label: 'Библиотека'),
        ],
      ),
    );
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required super.notifier, required super.child});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }
}
