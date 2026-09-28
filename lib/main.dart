import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'classification/basic_classifier.dart';
import 'classification/category_presentation.dart';
import 'lifestyle_settings_screen.dart';
import 'scheduling/schedule_engine.dart';
import 'storage/inbox_item.dart';
import 'storage/lifestyle_settings.dart';
import 'storage/local_repository.dart';

void main() => runApp(const AtodeBoxApp());

class AtodeBoxApp extends StatelessWidget {
  const AtodeBoxApp({super.key, this.repository});

  final LocalRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'あとでボックス',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF86A9A1)),
        useMaterial3: true,
      ),
      home: HomeInputScreen(repository: repository),
    );
  }
}

class HomeInputScreen extends StatefulWidget {
  const HomeInputScreen({super.key, this.repository});

  final LocalRepository? repository;

  @override
  State<HomeInputScreen> createState() => _HomeInputScreenState();
}

class _HomeInputScreenState extends State<HomeInputScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _random = Random.secure();
  Future<LocalRepository>? _repository;
  LifestyleSettings? _settings;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<LocalRepository> _getRepository() async =>
      widget.repository ??
      await (_repository ??= LocalRepository.openOnDevice());

  Future<void> _loadSettings() async {
    try {
      final settings = await (await _getRepository()).getSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _loadError = null;
        });
      }
    } catch (_) {
      _repository = null;
      if (mounted) setState(() => _loadError = '設定を読み込めませんでした');
    }
  }

  Future<void> _completeInitialSetup() async {
    if (_saving || _settings == null) return;
    setState(() {
      _saving = true;
      _loadError = null;
    });
    try {
      await (await _getRepository()).saveSettings(
        _settings!.copyWith(initialSetupComplete: true),
      );
      if (mounted) {
        setState(
          () => _settings = _settings!.copyWith(initialSetupComplete: true),
        );
      }
    } catch (_) {
      _repository = null;
      if (mounted) setState(() => _loadError = '保存できませんでした。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettings() async {
    if (_settings == null) return;
    try {
      final repository = await _getRepository();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LifestyleSettingsScreen(
            repository: repository,
            initial: _settings!,
          ),
        ),
      );
      if (saved == true) await _loadSettings();
    } catch (_) {
      _repository = null;
      if (!mounted) return;
      if (_settings!.initialSetupComplete) {
        _message('設定を開けませんでした。もう一度お試しください');
      } else {
        setState(() => _loadError = '設定を開けませんでした。もう一度お試しください');
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String _newId() => List.generate(
    4,
    (_) => _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
  ).join();

  void _message(String message, {ItemCategory? category}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        content: category == null
            ? Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              )
            : Row(
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    ' · ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  CategoryBadge(category),
                ],
              ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 112),
      ),
    );
  }

  Future<void> _save(String text, {required bool fromInput}) async {
    if (_saving || text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final category = const BasicClassifier().classify(text).category;
      final repository = await _getRepository();
      final now = DateTime.now();
      await repository.saveItem(
        InboxItem(
          id: _newId(),
          originalText: text,
          savedAt: now,
          category: category,
        ),
        scheduler: const ScheduleEngine(),
        now: now,
      );
      if (!mounted) return;
      if (fromInput && _input.text == text) _input.clear();
      _message('登録しました', category: category);
      if (fromInput) _inputFocus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      _repository = null;
      _message('保存できませんでした。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pasteAndSave() async {
    if (_saving) return;
    try {
      final text = (await Clipboard.getData('text/plain'))?.text;
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        _message('クリップボードは空です');
        return;
      }
      await _save(text, fromInput: false);
    } catch (_) {
      if (mounted) _message('貼り付けできませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('あとでボックス')),
        body: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    TextButton(
                      onPressed: _loadSettings,
                      child: const Text('再試行'),
                    ),
                  ],
                ),
        ),
      );
    }
    if (!_settings!.initialSetupComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('はじめに')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('生活時間に合わせて思い出します', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 24),
                Text('帰宅開始  ${formatMinute(_settings!.commuteStartMinute)}'),
                Text('帰宅後  ${formatMinute(_settings!.afterHomeMinute)}'),
                Text(
                  '休日  ${_settings!.weekendsAreHolidays ? '土日' : '土日なし'}・${_settings!.japaneseHolidays ? '日本の祝日' : '祝日なし'}',
                ),
                const Spacer(),
                if (_loadError != null)
                  Text(
                    _loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _completeInitialSetup,
                  child: const Text('このまま使う'),
                ),
                OutlinedButton(
                  onPressed: _saving ? null : _openSettings,
                  child: const Text('設定を変更する'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('あとでボックス'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: '通知一覧',
            onPressed: () => _message('通知一覧は準備中です'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '今じゃない。でも忘れたくない。',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('気になることを、そのまま入れておこう。'),
              const SizedBox(height: 20),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'あとで見たいこと',
                    hintText: 'URL、行きたい場所、買い物、メモなど',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _save(_input.text, fromInput: true),
                icon: const Icon(Icons.add),
                label: const Text('登録'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pasteAndSave,
                icon: const Icon(Icons.content_paste),
                label: const Text('貼り付けて追加'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
