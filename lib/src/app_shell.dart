import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_localization.dart';
import 'alarm_screen.dart';
import 'chat_screen.dart';
import 'glass_ui.dart';
import 'settings_screen.dart';
import 'soundscape_controller.dart';
import 'world_map_screen.dart';

enum AppDestination { chat, worldMap, alarms, settings, runtimeLogs }

extension AppDestinationData on AppDestination {
  String label(AppLanguage language) => switch (this) {
    AppDestination.chat => language.text('角色聊天', 'Character chat', 'キャラクター会話'),
    AppDestination.worldMap => language.text('世界地图', 'World map', 'ワールドマップ'),
    AppDestination.alarms => language.text('语音闹钟', 'Voice alarms', 'ボイスアラーム'),
    AppDestination.settings => language.text('设置', 'Settings', '設定'),
    AppDestination.runtimeLogs => language.text('运行日志', 'Runtime logs', '実行ログ'),
  };

  IconData get icon => switch (this) {
    AppDestination.chat => Icons.chat_bubble_outline,
    AppDestination.worldMap => Icons.map_outlined,
    AppDestination.alarms => Icons.alarm_outlined,
    AppDestination.settings => Icons.settings_outlined,
    AppDestination.runtimeLogs => Icons.bug_report_outlined,
  };
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _soundscape = SoundscapeController();
  AppDestination _destination = AppDestination.chat;
  bool _menuOpen = false;
  bool _chatUiHidden = false;

  @override
  void dispose() {
    _soundscape.dispose();
    super.dispose();
  }

  void _openMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _toggleChatUiVisibility() {
    setState(() {
      _chatUiHidden = !_chatUiHidden;
      if (_chatUiHidden) _menuOpen = false;
    });
  }

  void _selectDestination(AppDestination value) {
    Navigator.maybePop(context);
    if (value == AppDestination.worldMap && _destination != value) {
      widget.controller.recordMapVisit();
    }
    setState(() {
      _destination = value;
      _menuOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _soundscape.sync(
            widget.controller,
            worldMapVisible: _destination == AppDestination.worldMap,
          );
        });
        // Keep the chat element at the same tree location: replacing its
        // parent on settings navigation disposes playback, replay files and drafts.
        final content = Stack(
          children: [
            IndexedStack(
              index: _destination == AppDestination.settings
                  ? AppDestination.chat.index
                  : _destination.index,
              children: [
                ChatScreen(
                  controller: widget.controller,
                  onMenuPressed: _openMenu,
                  hideUi: _chatUiHidden,
                ),
                WorldMapScreen(
                  controller: widget.controller,
                  onMenuPressed: _openMenu,
                  onClose: () => _selectDestination(AppDestination.chat),
                ),
                AlarmScreen(
                  controller: widget.controller,
                  onMenuPressed: _openMenu,
                ),
                const SizedBox.shrink(),
                RuntimeLogScreen(
                  language: widget.controller.interfaceLanguage,
                  liquidGlass: widget.controller.liquidGlassChatUi,
                  onMenuPressed: _openMenu,
                ),
              ],
            ),
            if (_destination == AppDestination.settings)
              SettingsScreen(
                controller: widget.controller,
                onMenuPressed: _openMenu,
              ),
          ],
        );
        final safeTop = MediaQuery.paddingOf(context).top;
        return Scaffold(
          key: _scaffoldKey,
          body: Stack(
            children: [
              content,
              if (!_chatUiHidden)
                Positioned(
                  left: 16,
                  top: safeTop + 8,
                  child: GlassIconButton(
                    liquidGlass: widget.controller.liquidGlassChatUi,
                    size: 48,
                    icon: _menuOpen ? Icons.close_rounded : Icons.menu_rounded,
                    tooltip: widget.controller.interfaceLanguage.text(
                      _menuOpen ? '关闭菜单' : '打开菜单',
                      _menuOpen ? 'Close menu' : 'Open menu',
                      _menuOpen ? 'メニューを閉じる' : 'メニューを開く',
                    ),
                    onPressed: _openMenu,
                  ),
                ),
              if (_destination == AppDestination.chat)
                Positioned(
                  left: 72,
                  top: safeTop + 8,
                  child: GlassIconButton(
                    liquidGlass: widget.controller.liquidGlassChatUi,
                    size: 48,
                    icon: _chatUiHidden
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    tooltip: widget.controller.interfaceLanguage.text(
                      _chatUiHidden ? '恢复界面' : '隐藏界面',
                      _chatUiHidden ? 'Restore interface' : 'Hide interface',
                      _chatUiHidden ? 'UIを表示' : 'UIを隠す',
                    ),
                    onPressed: _toggleChatUiVisibility,
                  ),
                ),
              if (_menuOpen) _buildFoldMenu(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFoldMenu() {
    final language = widget.controller.interfaceLanguage;
    final liquidGlass = widget.controller.liquidGlassChatUi;
    return Positioned(
      left: 16,
      top: MediaQuery.paddingOf(context).top + 64,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final destination in AppDestination.values)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GlassIconButton(
                  liquidGlass: liquidGlass,
                  size: 48,
                  icon: destination.icon,
                  tooltip: destination.label(language),
                  onPressed: () => _selectDestination(destination),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
