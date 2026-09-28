enum ItemCategory { read, watch, go, buy, doTask, idea, memo }

enum ItemStatus { active, completed, deleted }

/// A saved input. [originalText] is never derived from title or URL.
class InboxItem {
  static const _unchanged = Object();

  const InboxItem({
    required this.id,
    required this.originalText,
    required this.savedAt,
    this.title,
    this.url,
    this.category = ItemCategory.memo,
    this.status = ItemStatus.active,
    this.nextNotifyAt,
    this.context,
    this.snoozeCount = 0,
    this.needsProcessing = true,
  }) : assert(snoozeCount >= 0);

  final String id;
  final String originalText;
  final String? title;
  final String? url;
  final DateTime savedAt;
  final ItemCategory category;
  final ItemStatus status;
  final DateTime? nextNotifyAt;
  final String? context;
  final int snoozeCount;
  final bool needsProcessing;

  InboxItem copyWith({
    Object? title = _unchanged,
    Object? url = _unchanged,
    ItemCategory? category,
    ItemStatus? status,
    Object? nextNotifyAt = _unchanged,
    Object? context = _unchanged,
    int? snoozeCount,
    bool? needsProcessing,
  }) => InboxItem(
    id: id,
    originalText: originalText,
    savedAt: savedAt,
    title: identical(title, _unchanged) ? this.title : title as String?,
    url: identical(url, _unchanged) ? this.url : url as String?,
    category: category ?? this.category,
    status: status ?? this.status,
    nextNotifyAt: identical(nextNotifyAt, _unchanged)
        ? this.nextNotifyAt
        : nextNotifyAt as DateTime?,
    context: identical(context, _unchanged) ? this.context : context as String?,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    needsProcessing: needsProcessing ?? this.needsProcessing,
  );

  InboxItem completed() => copyWith(status: ItemStatus.completed);
  InboxItem deleted() => copyWith(status: ItemStatus.deleted);

  InboxItem snoozed(DateTime next, {String? notificationContext}) {
    if (status != ItemStatus.active) {
      throw StateError('Only active items can be snoozed');
    }
    return copyWith(
      nextNotifyAt: next,
      context: notificationContext,
      snoozeCount: snoozeCount + 1,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'original_text': originalText,
    'title': title,
    'url': url,
    'saved_at': savedAt.toIso8601String(),
    'category': category == ItemCategory.doTask ? 'do' : category.name,
    'status': status.name,
    'next_notify_at': nextNotifyAt?.toIso8601String(),
    'context': context,
    'snooze_count': snoozeCount,
    'needs_processing': needsProcessing,
  };

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category'] == 'do' ? 'doTask' : json['category'];
    return InboxItem(
      id: json['id'] as String,
      originalText: json['original_text'] as String,
      title: json['title'] as String?,
      url: json['url'] as String?,
      savedAt: DateTime.parse(json['saved_at'] as String),
      category: ItemCategory.values.byName(categoryName as String? ?? 'memo'),
      status: ItemStatus.values.byName(json['status'] as String? ?? 'active'),
      nextNotifyAt: json['next_notify_at'] == null
          ? null
          : DateTime.parse(json['next_notify_at'] as String),
      context: json['context'] as String?,
      snoozeCount: json['snooze_count'] as int? ?? 0,
      needsProcessing: json['needs_processing'] as bool? ?? true,
    );
  }
}
