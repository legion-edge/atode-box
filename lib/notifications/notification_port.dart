import '../storage/inbox_item.dart';

class PendingNotice {
  const PendingNotice(this.id, this.payload);
  final int id;
  final String? payload;
}

class NoticeResponse {
  const NoticeResponse(this.action, this.payload);
  final String action;
  final String? payload;
}

class LocalNotice {
  const LocalNotice({
    required this.id,
    required this.at,
    required this.payload,
    required this.title,
    required this.body,
  });
  final int id;
  final DateTime at;
  final String payload;
  final String title;
  final String body;
}

abstract interface class NotificationPort {
  Future<void> initialize(void Function(NoticeResponse) onResponse);
  Future<NoticeResponse?> launchResponse();
  Future<bool> permissionGranted();
  Future<bool> requestPermission();
  Future<List<PendingNotice>> pending();
  Future<void> schedule(LocalNotice notice);
  Future<void> cancel(int id);
}

/// Short, category-specific copy. The saved text is kept private in OS previews.
LocalNotice noticeFor(InboxItem item) {
  final (title, body) = switch (item.category) {
    ItemCategory.read => ('読む', '保存したものを読んでみませんか'),
    ItemCategory.watch => ('見る', '保存したものを見てみませんか'),
    ItemCategory.go => ('行く', '行きたい場所を確認しませんか'),
    ItemCategory.buy => ('買う', '買いたいものを確認しませんか'),
    ItemCategory.doTask => ('やる', 'やりたいことを進めませんか'),
    ItemCategory.idea => ('アイデア', '保存したアイデアを見返しませんか'),
    ItemCategory.memo => ('メモ', '保存したメモを見返しませんか'),
  };
  final at = item.nextNotifyAt!;
  return LocalNotice(
    id: item.notificationId!,
    at: at,
    payload: '${item.id}|${at.toUtc().toIso8601String()}',
    title: title,
    body: body,
  );
}
