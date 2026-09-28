import 'package:flutter/material.dart';

import 'storage/lifestyle_settings.dart';
import 'storage/local_repository.dart';

String formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class LifestyleSettingsScreen extends StatefulWidget {
  const LifestyleSettingsScreen({
    super.key,
    required this.repository,
    required this.initial,
  });

  final LocalRepository repository;
  final LifestyleSettings initial;

  @override
  State<LifestyleSettingsScreen> createState() =>
      _LifestyleSettingsScreenState();
}

class _LifestyleSettingsScreenState extends State<LifestyleSettingsScreen> {
  late LifestyleSettings _draft = widget.initial;
  bool _saving = false;
  String? _error;

  Future<void> _pickTime(bool commute) async {
    final minute = commute ? _draft.commuteStartMinute : _draft.afterHomeMinute;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: commute ? '帰宅開始時刻' : '帰宅後の時刻',
      cancelText: 'キャンセル',
      confirmText: '決定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _draft = commute
          ? _draft.copyWith(
              commuteStartMinute: selected.hour * 60 + selected.minute,
            )
          : _draft.copyWith(
              afterHomeMinute: selected.hour * 60 + selected.minute,
            );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveSettings(
        _draft.copyWith(initialSetupComplete: true),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = '保存できませんでした。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('生活時間の設定')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('思い出す時間の目安を設定します。', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('帰宅開始'),
            subtitle: Text(formatMinute(_draft.commuteStartMinute)),
            trailing: const Icon(Icons.schedule),
            onTap: _saving ? null : () => _pickTime(true),
          ),
          ListTile(
            title: const Text('帰宅後'),
            subtitle: Text(formatMinute(_draft.afterHomeMinute)),
            trailing: const Icon(Icons.schedule),
            onTap: _saving ? null : () => _pickTime(false),
          ),
          SwitchListTile(
            title: const Text('土日を休日にする'),
            value: _draft.weekendsAreHolidays,
            onChanged: _saving
                ? null
                : (value) => setState(
                    () => _draft = _draft.copyWith(weekendsAreHolidays: value),
                  ),
          ),
          SwitchListTile(
            title: const Text('日本の祝日を休日にする'),
            value: _draft.japaneseHolidays,
            onChanged: _saving
                ? null
                : (value) => setState(
                    () => _draft = _draft.copyWith(japaneseHolidays: value),
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存する'),
          ),
        ],
      ),
    ),
  );
}
