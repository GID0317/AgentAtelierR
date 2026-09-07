import 'dart:ui';

import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:spine_flutter/spine_flutter.dart' hide Color;

import 'src/app_controller.dart';
import 'src/app_localization.dart';
import 'src/app_shell.dart';
import 'src/runtime_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    RuntimeLog.instance.error(
      'Flutter',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    RuntimeLog.instance.error('Platform', error, stackTrace);
    return false;
  };
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  AppController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await RuntimeLog.instance.initialize();
      RuntimeLog.instance.info('App', '应用启动，版本 0.7.0+15');
      await initSpineFlutter(enableMemoryDebugging: false);
      await Alarm.init();
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      final controller = await AppController.load();
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _controller = controller);
    } on Object catch (error, stackTrace) {
      RuntimeLog.instance.error('Startup', error, stackTrace);
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) return AgentAtelierRApp(controller: controller);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: _error == null
                ? Image.asset(
                    'assets/branding/agent_atelier_logo.png',
                    width: MediaQuery.sizeOf(context).width * 0.85,
                    fit: BoxFit.contain,
                  )
                : TextButton.icon(
                    onPressed: () {
                      setState(() => _error = null);
                      _initialize();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('加载失败，点击重试'),
                  ),
          ),
        ),
      ),
    );
  }
}

class AgentAtelierRApp extends StatelessWidget {
  const AgentAtelierRApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF262521);
    const paper = Color(0xFFF6F3ED);
    const darkSurface = Color(0xFF171A1A);
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2D796A),
        brightness: Brightness.light,
        surface: paper,
      ),
      scaffoldBackgroundColor: paper,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
      ),
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF78C8B4),
        brightness: Brightness.dark,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkSurface,
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AgentAtelierR',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: switch (controller.themePreference) {
          AppThemePreference.system => ThemeMode.system,
          AppThemePreference.light => ThemeMode.light,
          AppThemePreference.dark => ThemeMode.dark,
        },
        home: AppShell(controller: controller),
      ),
    );
  }
}
