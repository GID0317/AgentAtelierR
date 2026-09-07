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
        final content = _destination == AppDestination.settings
            ? Stack(
                children: [
                  ChatScreen(
                    controller: widget.controller,
                    onMenuPressed: _openMenu,
                    hideUi: _chatUiHidden,
                  ),
                  SettingsScreen(
                    controller: widget.controller,
                    onMenuPressed: _openMenu,
                  ),
                ],
              )
            : IndexedStack(
                index: _destination.index,
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

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.selected,
    required this.stars,
    required this.language,
    required this.liquidGlass,
    required this.onSelected,
  });

  final AppDestination selected;
  final int stars;
  final AppLanguage language;
  final bool liquidGlass;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(280, 360).toDouble(),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
      ),
      child: GlassSurface(
        liquidGlass: liquidGlass,
        tone: GlassTone.light,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
        fallbackColor: const Color(0xF2F4F7F4),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 18),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 25,
                      backgroundImage: AssetImage(
                        'assets/images/chara_icons/ryza.png',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AgentAtelierR',
                            style: TextStyle(
                              color: Color(0xFF24302E),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            language.text('本地原型', 'Local prototype', 'ローカル版'),
                            style: TextStyle(color: Color(0xA624302E)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: Color(0xFFFFD66B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$stars',
                            style: const TextStyle(color: Color(0xFF24302E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x2424302E)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final destination in AppDestination.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          selected: destination == selected,
                          selectedTileColor: Colors.white.withValues(
                            alpha: 0.52,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: destination == selected
                                ? const BorderSide(color: Color(0x2424302E))
                                : BorderSide.none,
                          ),
                          leading: Icon(
                            destination.icon,
                            color: const Color(0xFF334542),
                          ),
                          title: Text(
                            destination.label(language),
                            style: const TextStyle(color: Color(0xFF24302E)),
                          ),
                          onTap: () => onSelected(destination),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Text(
                  language.text(
                    'AI 与语音服务可在设置中配置',
                    'Configure AI and voice services in Settings',
                    'AIと音声サービスは設定から変更できます',
                  ),
                  style: const TextStyle(
                    color: Color(0xA624302E),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
