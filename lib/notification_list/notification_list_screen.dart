import 'dart:async';

import 'package:flutter/material.dart';

import '../classification/category_presentation.dart';
import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/lifestyle_settings.dart';
import '../storage/local_repository.dart';
import 'notification_list_filter.dart';

class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({
    super.key,
    required this.repository,
    required this.settings,
    this.now = DateTime.now,
    this.zone = const DeviceZone(),
  });

  final LocalRepository repository;
  final LifestyleSettings settings;
  final DateTime Function() now;
  final ScheduleZone zone;

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen>
    with WidgetsBindingObserver {
  NotificationListFilter _filter = NotificationListFilter.today;
  List<InboxItem>? _items;
  String? _error;
  Timer? _dateRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleDateRefresh();
  }

  @override
  void didUpdateWidget(NotificationListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now || oldWidget.zone != widget.zone) {
      _scheduleDateRefresh();
    }
  }

  void _scheduleDateRefresh() {
    _dateRefresh?.cancel();
    final now = widget.now();
    final local = widget.zone.toLocal(now);
    final tomorrow = DateTime.utc(local.year, local.month, local.day + 1);
    final boundary = widget.zone.fromLocal(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      0,
      0,
    );
    final delay = boundary.difference(now);
    _dateRefresh = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleDateRefresh();
      },
    );
  }

  @override
  void dispose() {
    _dateRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _scheduleDateRefresh();
    }
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.allItems();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '一覧を読み込めませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = NotificationListQuery(zone: widget.zone);
    var visible = <InboxItem>[];
    String? calendarError;
    if (_items != null) {
      try {
        visible = query.select(_items!, _filter, widget.settings, widget.now());
      } on RangeError {
        calendarError = 'この年の日本の祝日データは未収録です';
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('通知一覧')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final filter in NotificationListFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            ),
            Expanded(
              child: calendarError != null
                  ? Center(child: Text(calendarError))
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: _load,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    )
                  : _items == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: visible.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height: 240,
                                  child: Center(
                                    child: Text(
                                      _filter ==
                                              NotificationListFilter.completed
                                          ? '完了済みの項目はありません'
                                          : '${_filter.label}の予定はありません',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => Navigator.of(context)
                                        .push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                SavedItemPreviewScreen(
                                                  item: item,
                                                  zone: widget.zone,
                                                ),
                                          ),
                                        )
                                        .then((_) => _load()),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.title
                                                              ?.trim()
                                                              .isNotEmpty ==
                                                          true
                                                      ? item.title!
                                                      : item.originalText,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  spacing: 12,
                                                  runSpacing: 4,
                                                  children: [
                                                    CategoryBadge(
                                                      item.category,
                                                    ),
                                                    Text(
                                                      item.status ==
                                                              ItemStatus
                                                                  .completed
                                                          ? '保存 ${formatListDate(widget.zone.toLocal(item.savedAt))}'
                                                          : item.nextNotifyAt ==
                                                                null
                                                          ? '次回未設定'
                                                          : '次回 ${formatListDate(widget.zone.toLocal(item.nextNotifyAt!))}',
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatListDate(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// A read-only destination until the full item detail screen in Issue #9.
class SavedItemPreviewScreen extends StatelessWidget {
  const SavedItemPreviewScreen({
    super.key,
    required this.item,
    this.zone = const DeviceZone(),
  });

  final InboxItem item;
  final ScheduleZone zone;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('保存した内容')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          CategoryBadge(item.category),
          const SizedBox(height: 16),
          if (item.status == ItemStatus.active && item.nextNotifyAt != null)
            Text('次回通知 ${formatListDate(zone.toLocal(item.nextNotifyAt!))}'),
          if (item.status == ItemStatus.active && item.nextNotifyAt == null)
            const Text('次回未設定'),
          if (item.status == ItemStatus.completed) const Text('完了済み'),
          const SizedBox(height: 24),
          SelectableText(item.originalText),
        ],
      ),
    ),
  );
}
