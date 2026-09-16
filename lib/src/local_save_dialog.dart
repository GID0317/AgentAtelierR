import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_localization.dart';
import 'glass_ui.dart';

Future<void> showLocalSaveDialog(
  BuildContext context,
  AppController controller,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black45,
    builder: (dialogContext) => _LocalSaveDialog(controller: controller),
  );
}

class _LocalSaveDialog extends StatefulWidget {
  const _LocalSaveDialog({required this.controller});

  final AppController controller;

  @override
  State<_LocalSaveDialog> createState() => _LocalSaveDialogState();
}

class _LocalSaveDialogState extends State<_LocalSaveDialog> {
  bool _busy = false;

  String _text(String zh, String en, String ja) =>
      widget.controller.interfaceLanguage.text(zh, en, ja);

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<bool> _confirm({required String title, required String body}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_text('取消', 'Cancel', 'キャンセル')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_text('确认', 'Confirm', '確認')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save(int index, bool occupied) async {
    if (_busy) return;
    if (occupied) {
      final confirmed = await _confirm(
        title: _text('覆盖存档？', 'Overwrite save?', 'セーブを上書きしますか？'),
        body: _text(
          '槽位 ${index + 1} 的旧存档将被替换。',
          'The existing save in slot ${index + 1} will be replaced.',
          'スロット ${index + 1} の既存セーブは置き換えられます。',
        ),
      );
      if (!mounted || !confirmed) return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.saveToLocalSlot(index);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('存档完成', 'Game saved', 'セーブしました'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_text('存档失败', 'Save failed', 'セーブ失敗')}: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(int index) async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: _text('读取存档？', 'Load save?', 'セーブを読み込みますか？'),
      body: _text(
        '当前尚未保存的进度会被槽位 ${index + 1} 替换。',
        'Unsaved progress will be replaced by slot ${index + 1}.',
        '未保存の進行状況はスロット ${index + 1} の内容に置き換えられます。',
      ),
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.loadFromLocalSlot(index);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_text('读取完成', 'Save loaded', 'ロードしました'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_text('读取失败', 'Load failed', 'ロード失敗')}: $error'),
        ),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _delete(int index) async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: _text('删除存档？', 'Delete save?', 'セーブを削除しますか？'),
      body: _text(
        '槽位 ${index + 1} 删除后无法恢复。',
        'Slot ${index + 1} cannot be recovered after deletion.',
        'スロット ${index + 1} は削除後に復元できません。',
      ),
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deleteLocalSlot(index);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_text('删除失败', 'Delete failed', '削除失敗')}: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.controller.localSaveSlots;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: GlassSurface(
          liquidGlass: widget.controller.liquidGlassChatUi,
          tone: GlassTone.dark,
          fallbackColor: const Color(0xE0201D1B),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.save_outlined, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _text('本地存档', 'Local saves', 'ローカルセーブ'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      tooltip: _text('关闭', 'Close', '閉じる'),
                      color: Colors.white,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: slots.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final slot = slots[index];
                    return Material(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        leading: CircleAvatar(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          slot == null
                              ? _text('空存档位', 'Empty slot', '空きスロット')
                              : '${slot.location} · ${_formatTime(slot.savedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          slot == null
                              ? _text(
                                  '点击保存当前进度',
                                  'Save current progress',
                                  '現在の進行状況を保存',
                                )
                              : '${slot.messageCount} ${_text('条消息', 'messages', '件のメッセージ')}\n${slot.preview}',
                          maxLines: slot == null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        isThreeLine: slot != null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (slot != null)
                              IconButton(
                                onPressed: _busy ? null : () => _load(index),
                                tooltip: _text('读取', 'Load', 'ロード'),
                                color: Colors.white,
                                icon: const Icon(Icons.download_rounded),
                              ),
                            IconButton(
                              onPressed: _busy
                                  ? null
                                  : () => _save(index, slot != null),
                              tooltip: _text('保存', 'Save', 'セーブ'),
                              color: Colors.white,
                              icon: const Icon(Icons.save_rounded),
                            ),
                            if (slot != null)
                              IconButton(
                                onPressed: _busy ? null : () => _delete(index),
                                tooltip: _text('删除', 'Delete', '削除'),
                                color: Colors.white70,
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
