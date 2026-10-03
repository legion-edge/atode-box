import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../classification/category_presentation.dart';
import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/local_repository.dart';

// Null means legacy input: derive a URL. Empty means explicitly removed.
Uri? itemUrl(InboxItem item) {
  final text =
      item.url ??
      RegExp(
        r'https?://[^\s<>]+',
        caseSensitive: false,
      ).firstMatch(item.originalText)?.group(0);
  return validUrl(text ?? '');
}

Uri? validUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null &&
          ['http', 'https'].contains(uri.scheme.toLowerCase()) &&
          uri.host.isNotEmpty
      ? uri
      : null;
}

String detailDate(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String contextLabel(String? key) => switch (key) {
  'commute' => '帰宅開始・帰宅中',
  'after_home' => '帰宅後',
  'evening' => '夜',
  'next_day_evening' => '翌日夜',
  'holiday_eve' => '休日の前日夜',
  'holiday_day' => '休日昼',
  'holiday_evening' => '休日夜',
  'next_week' => '1週間後',
  _ => '未設定',
};

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.item,
    required this.repository,
    this.zone = const DeviceZone(),
    this.now = DateTime.now,
    this.syncNotifications,
    this.openUrl,
  });

  final InboxItem item;
  final LocalRepository repository;
  final ScheduleZone zone;
  final DateTime Function() now;
  final Future<void> Function()? syncNotifications;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen>
    with WidgetsBindingObserver {
  late InboxItem _item = widget.item;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    try {
      final item = await widget.repository.getItem(_item.id);
      if (!mounted) return;
      if (item == null || item.status == ItemStatus.deleted) {
        Navigator.pop(context);
      } else {
        setState(() => _item = item);
      }
    } catch (_) {
      if (mounted) _message('内容を読み込めませんでした');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _sync() async {
    try {
      await widget.syncNotifications?.call();
    } catch (_) {
      if (mounted) _message('変更は保存しました。通知の更新は次回起動時に再試行します');
    }
  }

  Future<void> _open() async {
    final uri = itemUrl(_item);
    if (uri == null || _busy) return;
    setState(() => _busy = true);
    try {
      final opened =
          await (widget.openUrl?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened && mounted) _message('URLを開けませんでした');
    } catch (_) {
      if (mounted) _message('URLを開けませんでした');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditItemScreen(
          item: _item,
          repository: widget.repository,
          now: widget.now,
          zone: widget.zone,
        ),
      ),
    );
    if (saved == true) {
      await _reload();
      await _sync();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この項目を削除しますか？'),
        content: const Text('一覧から削除し、次回通知を取り消します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteItem(_item.id);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _message('削除できませんでした。もう一度お試しください');
      }
      return;
    }
    await _sync();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final url = itemUrl(_item);
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存した内容'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '編集',
          ),
          IconButton(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: '削除',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CategoryBadge(_item.category),
            const SizedBox(height: 16),
            if (_item.title?.trim().isNotEmpty == true) ...[
              Text('タイトル', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(_item.title!),
              const SizedBox(height: 16),
            ],
            Text('保存日時 ${detailDate(widget.zone.toLocal(_item.savedAt))}'),
            if (_item.status == ItemStatus.completed)
              const Text('完了済み・次回通知なし')
            else if (_item.nextNotifyAt == null)
              const Text('次回未設定')
            else
              Text(
                '次回通知 ${detailDate(widget.zone.toLocal(_item.nextNotifyAt!))}',
              ),
            Text(
              '通知コンテキスト：${contextLabel(_item.status == ItemStatus.active ? _item.context : null)}',
            ),
            if (url != null) ...[
              const SizedBox(height: 16),
              SelectableText(url.toString()),
              FilledButton.icon(
                onPressed: _busy ? null : _open,
                icon: const Icon(Icons.open_in_new),
                label: const Text('開く'),
              ),
            ],
            const SizedBox(height: 24),
            Text('原文', style: Theme.of(context).textTheme.labelLarge),
            SelectableText(_item.originalText),
          ],
        ),
      ),
    );
  }
}

class _EditItemScreen extends StatefulWidget {
  const _EditItemScreen({
    required this.item,
    required this.repository,
    required this.now,
    required this.zone,
  });
  final InboxItem item;
  final LocalRepository repository;
  final DateTime Function() now;
  final ScheduleZone zone;
  @override
  State<_EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<_EditItemScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item.title);
  late final _url = TextEditingController(
    text: itemUrl(widget.item)?.toString() ?? widget.item.url ?? '',
  );
  late ItemCategory _category = widget.item.category;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.editItem(
        widget.item.id,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        url: _url.text.trim(),
        category: _category,
        scheduler: ScheduleEngine(zone: widget.zone),
        now: widget.now(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存できませんでした。もう一度お試しください';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('編集')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _title,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'タイトル（任意）'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL（任意）'),
                validator: (value) =>
                    value!.trim().isEmpty || validUrl(value) != null
                    ? null
                    : 'http または https のURLを入力してください',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ItemCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'カテゴリ'),
                items: [
                  for (final category in ItemCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: CategoryBadge(category),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 24),
              const Text('原文はそのまま保持します。カテゴリを変更すると通知予定を再計算します。'),
              SelectableText(widget.item.originalText),
              if (_error != null) Text(_error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
