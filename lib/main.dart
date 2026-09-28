import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'storage/inbox_item.dart';
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
  bool _saving = false;

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

  void _message(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
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
      final repository =
          widget.repository ??
          await (_repository ??= LocalRepository.openOnDevice());
      await repository.saveItem(
        InboxItem(id: _newId(), originalText: text, savedAt: DateTime.now()),
      );
      if (!mounted) return;
      if (fromInput && _input.text == text) _input.clear();
      _message('登録しました');
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
            onPressed: () => _message('設定は準備中です'),
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
