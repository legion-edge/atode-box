enum ItemCategory { read, watch, go, buy, doTask, idea, memo }

enum ItemStatus { active, completed, deleted }

/// Explicit user/classifier metadata. Unknown content uses the short rule.
enum ContentLength { unspecified, short, long }

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
    this.contentLength = ContentLength.unspecified,
    this.status = ItemStatus.active,
    this.nextNotifyAt,
    this.context,
    this.scheduleReason,
    this.snoozeCount = 0,
    this.needsProcessing = true,
    this.notificationId,
  }) : assert(snoozeCount >= 0);

  final String id;
  final String originalText;
  final String? title;
  final String? url;
  final DateTime savedAt;
  final ItemCategory category;
  final ContentLength contentLength;
  final ItemStatus status;
  final DateTime? nextNotifyAt;
  final String? context;
  final String? scheduleReason;
  final int snoozeCount;
  final bool needsProcessing;

  /// Stable OS request ID; assigned by the repository on first save.
  final int? notificationId;

  InboxItem copyWith({
    Object? title = _unchanged,
    Object? url = _unchanged,
    ItemCategory? category,
    ContentLength? contentLength,
    ItemStatus? status,
    Object? nextNotifyAt = _unchanged,
    Object? context = _unchanged,
    Object? scheduleReason = _unchanged,
    int? snoozeCount,
    bool? needsProcessing,
    int? notificationId,
  }) => InboxItem(
    id: id,
    originalText: originalText,
    savedAt: savedAt,
    title: identical(title, _unchanged) ? this.title : title as String?,
    url: identical(url, _unchanged) ? this.url : url as String?,
    category: category ?? this.category,
    contentLength: contentLength ?? this.contentLength,
    status: status ?? this.status,
    nextNotifyAt: identical(nextNotifyAt, _unchanged)
        ? this.nextNotifyAt
        : nextNotifyAt as DateTime?,
    context: identical(context, _unchanged) ? this.context : context as String?,
    scheduleReason: identical(scheduleReason, _unchanged)
        ? this.scheduleReason
        : scheduleReason as String?,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    needsProcessing: needsProcessing ?? this.needsProcessing,
    notificationId: notificationId ?? this.notificationId,
  );

  InboxItem completed() => copyWith(status: ItemStatus.completed);
  InboxItem deleted() => copyWith(status: ItemStatus.deleted);

  InboxItem snoozed(
    DateTime next, {
    String? notificationContext,
    String? reason,
  }) {
    if (status != ItemStatus.active) {
      throw StateError('Only active items can be snoozed');
    }
    return copyWith(
      nextNotifyAt: next,
      context: notificationContext,
      scheduleReason: reason,
      snoozeCount: snoozeCount + 1,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'original_text': originalText,
    'title': title,
    'url': url,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'category': category == ItemCategory.doTask ? 'do' : category.name,
    'content_length': contentLength.name,
    'status': status.name,
    'next_notify_at': nextNotifyAt?.toUtc().toIso8601String(),
    'context': context,
    'schedule_reason': scheduleReason,
    'snooze_count': snoozeCount,
    'needs_processing': needsProcessing,
    'notification_id': notificationId,
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
      contentLength: ContentLength.values.byName(
        json['content_length'] as String? ?? 'unspecified',
      ),
      status: ItemStatus.values.byName(json['status'] as String? ?? 'active'),
      nextNotifyAt: json['next_notify_at'] == null
          ? null
          : DateTime.parse(json['next_notify_at'] as String),
      context: json['context'] as String?,
      scheduleReason: json['schedule_reason'] as String?,
      snoozeCount: json['snooze_count'] as int? ?? 0,
      needsProcessing: json['needs_processing'] as bool? ?? true,
      notificationId: json['notification_id'] as int?,
    );
  }
}
