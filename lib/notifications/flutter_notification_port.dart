import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_port.dart';

class FlutterNotificationPort implements NotificationPort {
  FlutterNotificationPort() : _plugin = FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  static const open = 'open';
  static const complete = 'complete';
  static const snooze = 'snooze';
  static const _category = 'atode_actions';

  @override
  Future<void> initialize(void Function(NoticeResponse) onResponse) async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(
                  open,
                  '開く',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  complete,
                  '完了',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  snooze,
                  'あとで',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onResponse(
        NoticeResponse(response.actionId ?? open, response.payload),
      ),
    );
  }

  @override
  Future<NoticeResponse?> launchResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details!.notificationResponse;
    if (response == null) return null;
    return NoticeResponse(response.actionId ?? open, response.payload);
  }

  @override
  Future<bool> permissionGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<List<PendingNotice>> pending() async =>
      (await _plugin.pendingNotificationRequests())
          .map(
            (request) => PendingNotice(
              request.id,
              request.payload,
              title: request.title,
              body: request.body,
            ),
          )
          .toList();

  @override
  Future<void> schedule(LocalNotice notice) => _plugin.zonedSchedule(
    id: notice.id,
    title: notice.title,
    body: notice.body,
    scheduledDate: tz.TZDateTime.from(notice.at.toUtc(), tz.UTC),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        '思い出す通知',
        channelDescription: '保存した項目を予定時刻に通知します',
        importance: Importance.high,
        actions: [
          AndroidNotificationAction(open, '開く', showsUserInterface: true),
          AndroidNotificationAction(complete, '完了', showsUserInterface: true),
          AndroidNotificationAction(snooze, 'あとで', showsUserInterface: true),
        ],
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: _category),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    payload: notice.payload,
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
