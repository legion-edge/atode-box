import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../scheduling/schedule_engine.dart';
import 'inbox_item.dart';
import 'lifestyle_settings.dart';

/// Returned only after settings are durably saved. Notification scheduling in
/// later issues can use [scheduleChanged] to decide whether to recalculate.
class SettingsChange {
  const SettingsChange(this.previous, this.current);

  final LifestyleSettings previous;
  final LifestyleSettings current;

  bool get scheduleChanged => !previous.hasSameScheduleAs(current);
}

abstract interface class DocumentStore {
  Future<String?> read();
  Future<void> write(String contents);
}

/// Resolves an app-private directory on iOS and Android.
class AppStorageDirectory {
  static const _channel = MethodChannel('dev.legionedge.atode_box/storage');

  static Future<Directory> resolve() async {
    final path = await _channel.invokeMethod<String>('applicationSupportPath');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Application support path unavailable');
    }
    return Directory(path);
  }
}

/// Keeps the previous complete document until its replacement is installed.
class FileDocumentStore implements DocumentStore {
  FileDocumentStore(this.directory);

  final Directory directory;

  File get _current =>
      File('${directory.path}${Platform.pathSeparator}atode_box.json');
  File get _backup => File('${_current.path}.bak');
  File get _pending => File('${_current.path}.tmp');

  @override
  Future<String?> read() async {
    if (await _current.exists()) return _current.readAsString();
    if (await _backup.exists()) return _backup.readAsString();
    return null;
  }

  @override
  Future<void> write(String contents) async {
    await directory.create(recursive: true);
    await _pending.writeAsString(contents, flush: true);
    var movedCurrent = false;
    try {
      if (await _current.exists()) {
        if (await _backup.exists()) await _backup.delete();
        await _current.rename(_backup.path);
        movedCurrent = true;
      }
      await _pending.rename(_current.path);
      if (await _backup.exists()) await _backup.delete();
    } catch (_) {
      if (movedCurrent && !await _current.exists()) {
        await _backup.rename(_current.path);
      }
      rethrow;
    }
  }
}

/// Mutations only publish a new in-memory state after durable write succeeds.
class LocalRepository {
  LocalRepository(this.store);

  static Future<LocalRepository> openOnDevice() async =>
      LocalRepository(FileDocumentStore(await AppStorageDirectory.resolve()));

  final DocumentStore store;
  Map<String, InboxItem>? _items;
  LifestyleSettings? _settings;
  String? _scheduleZone;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _load() async {
    if (_items != null) return;
    final source = await store.read();
    if (source == null) {
      _items = {};
      _settings = const LifestyleSettings();
      return;
    }
    final root = jsonDecode(source) as Map<String, dynamic>;
    final version = root['schema_version'] as int? ?? 0;
    if (version < 0 || version > 1) {
      throw const FormatException('Unsupported storage schema');
    }
    // Version 0 is the initial unversioned shape; absent new fields receive
    // defaults, and the next successful write emits version 1.
    final records = root['items'] as List<dynamic>? ?? [];
    final items = <String, InboxItem>{};
    final reservedIds = records
        .map(
          (record) =>
              (record as Map<String, dynamic>)['notification_id'] as int?,
        )
        .whereType<int>()
        .toSet();
    final storedIds = records
        .map(
          (record) =>
              (record as Map<String, dynamic>)['notification_id'] as int?,
        )
        .whereType<int>()
        .toList();
    if (storedIds.length != reservedIds.length ||
        storedIds.any((id) => id < 1 || id > 0x7fffffff)) {
      throw const FormatException('Invalid notification ID');
    }
    var nextId = 1;
    for (final record in records) {
      var item = InboxItem.fromJson(record as Map<String, dynamic>);
      if (items.containsKey(item.id)) {
        throw const FormatException('Duplicate item ID');
      }
      if (item.notificationId == null) {
        while (reservedIds.contains(nextId)) {
          nextId++;
        }
        item = item.copyWith(notificationId: nextId);
        reservedIds.add(nextId++);
      }
      items[item.id] = item;
    }
    final settings = LifestyleSettings.fromJson(
      root['settings'] as Map<String, dynamic>? ?? {},
    );
    final scheduleZone = root['schedule_zone'] as String?;
    // Invalid settings must not publish a partially loaded item cache.
    _items = items;
    _settings = settings;
    _scheduleZone = scheduleZone;
  }

  Future<void> _persist(
    Map<String, InboxItem> items,
    LifestyleSettings settings,
  ) => store.write(
    jsonEncode({
      'schema_version': 1,
      'items': items.values.map((item) => item.toJson()).toList(),
      'settings': settings.toJson(),
      'schedule_zone': _scheduleZone,
    }),
  );

  Future<void> _commit(
    Map<String, InboxItem> items,
    LifestyleSettings settings,
  ) async {
    try {
      await _persist(items, settings);
      _items = items;
      _settings = settings;
    } catch (_) {
      // A filesystem error after rename may still have installed the new file.
      // Reload on the next operation instead of keeping a stale snapshot.
      _items = null;
      _settings = null;
      _scheduleZone = null;
      rethrow;
    }
  }

  Future<List<InboxItem>> allItems() => _serial(() async {
    await _load();
    return List.unmodifiable(_items!.values);
  });

  Future<InboxItem?> getItem(String id) => _serial(() async {
    await _load();
    return _items![id];
  });

  Future<void> saveItem(
    InboxItem item, {
    ScheduleEngine? scheduler,
    DateTime? now,
  }) => _serial(() async {
    await _load();
    if (item.id.isEmpty || item.originalText.isEmpty) {
      throw ArgumentError('Item ID and original text are required');
    }
    if (_items!.containsKey(item.id)) {
      throw StateError('Item ID already exists');
    }
    if (scheduler != null && now == null) {
      throw ArgumentError('An injected time is required for scheduling');
    }
    var nextId = 1;
    final used = _items!.values.map((value) => value.notificationId).toSet();
    while (used.contains(nextId)) {
      nextId++;
    }
    final withId = item.copyWith(notificationId: nextId);
    final scheduled = scheduler == null
        ? withId
        : _withSchedule(withId, scheduler.initial(withId, _settings!, now!));
    if (scheduler != null) _scheduleZone = _zone(now!);
    final next = {..._items!, item.id: scheduled};
    await _commit(next, _settings!);
  });

  static String _zone(DateTime now) =>
      '${now.toLocal().timeZoneName}/${now.toLocal().timeZoneOffset.inMinutes}';

  /// Recalculate only when the device's local zone identity/offset changes.
  Future<bool> adjustForTimeZone(ScheduleEngine scheduler, DateTime now) =>
      _serial(() async {
        await _load();
        final current = _zone(now);
        if (_scheduleZone == current) return false;
        if (_scheduleZone == null) {
          _scheduleZone = current;
          return false;
        }
        final updated = <String, InboxItem>{};
        for (final item in _items!.values) {
          updated[item.id] = item.status == ItemStatus.active
              ? _withSchedule(
                  item,
                  scheduler.recalculate(item, _settings!, now),
                )
              : item;
        }
        _scheduleZone = current;
        await _commit(updated, _settings!);
        return true;
      });

  InboxItem _withSchedule(InboxItem item, Schedule schedule) => item.copyWith(
    nextNotifyAt: schedule.at,
    context: schedule.context.storageKey,
    scheduleReason: schedule.reason,
  );

  /// One durable operation updates the count and next UTC instant together.
  Future<InboxItem> snoozeItem(
    String id,
    ScheduleEngine scheduler,
    DateTime now,
  ) => _serial(() async {
    await _load();
    final item = _items![id];
    if (item == null) throw StateError('Item does not exist');
    final schedule = scheduler.snooze(item, _settings!, now);
    final updated = item.snoozed(
      schedule.at,
      notificationContext: schedule.context.storageKey,
      reason: schedule.reason,
    );
    _scheduleZone = _zone(now);
    await _commit({..._items!, id: updated}, _settings!);
    return updated;
  });

  Future<void> updateItem(InboxItem item) => _serial(() async {
    await _load();
    final previous = _items![item.id];
    if (previous == null) throw StateError('Item does not exist');
    if (previous.originalText != item.originalText ||
        !previous.savedAt.isAtSameMomentAs(item.savedAt)) {
      throw StateError('Original text and saved time cannot be changed');
    }
    final next = {..._items!, item.id: item};
    await _commit(next, _settings!);
  });

  /// Validate a notification and mutate the latest record in one serial action.
  Future<InboxItem?> completeFromNotification(String id, DateTime expectedAt) =>
      _serial(() async {
        await _load();
        final item = _items![id];
        if (!_currentNotification(item, expectedAt)) return null;
        final updated = item!.completed();
        await _commit({..._items!, id: updated}, _settings!);
        return updated;
      });

  Future<InboxItem?> snoozeFromNotification(
    String id,
    DateTime expectedAt,
    ScheduleEngine scheduler,
    DateTime now,
  ) => _serial(() async {
    await _load();
    final item = _items![id];
    if (!_currentNotification(item, expectedAt)) return null;
    final schedule = scheduler.snooze(item!, _settings!, now);
    final updated = item.snoozed(
      schedule.at,
      notificationContext: schedule.context.storageKey,
      reason: schedule.reason,
    );
    _scheduleZone = _zone(now);
    await _commit({..._items!, id: updated}, _settings!);
    return updated;
  });

  bool _currentNotification(InboxItem? item, DateTime expectedAt) =>
      item != null &&
      item.status == ItemStatus.active &&
      item.nextNotifyAt?.isAtSameMomentAs(expectedAt) == true;

  /// Edit metadata against the latest record; preserve original and action state.
  Future<InboxItem> editItem(
    String id, {
    required String? title,
    required String url,
    required ItemCategory category,
    required ScheduleEngine scheduler,
    required DateTime now,
  }) => _serial(() async {
    await _load();
    final previous = _items![id];
    if (previous == null || previous.status == ItemStatus.deleted) {
      throw StateError('Item is unavailable');
    }
    var updated = previous.copyWith(title: title, url: url, category: category);
    if (updated.status == ItemStatus.active &&
        (previous.category != category || previous.nextNotifyAt == null)) {
      updated = _withSchedule(
        updated,
        scheduler.recalculate(updated, _settings!, now),
      );
    } else if (updated.status != ItemStatus.active) {
      updated = updated.copyWith(
        nextNotifyAt: null,
        context: null,
        scheduleReason: null,
      );
    }
    await _commit({..._items!, id: updated}, _settings!);
    return updated;
  });

  Future<void> deleteItem(String id) => _serial(() async {
    await _load();
    final item = _items![id];
    if (item == null) throw StateError('Item does not exist');
    final updated = item.deleted().copyWith(
      nextNotifyAt: null,
      context: null,
      scheduleReason: null,
    );
    await _commit({..._items!, id: updated}, _settings!);
  });

  /// Physical removal is separate from the domain's soft-deleted status.
  Future<void> removeItem(String id) => _serial(() async {
    await _load();
    if (!_items!.containsKey(id)) return;
    final next = {..._items!}..remove(id);
    await _commit(next, _settings!);
  });

  Future<LifestyleSettings> getSettings() => _serial(() async {
    await _load();
    return _settings!;
  });

  Future<SettingsChange> saveSettings(LifestyleSettings settings) =>
      _serial(() async {
        await _load();
        final previous = _settings!;
        await _commit(_items!, settings);
        return SettingsChange(previous, settings);
      });

  /// Saves settings and recalculates every active item in the same document.
  /// A setup-complete-only edit leaves all item schedules untouched.
  Future<SettingsChange> saveSettingsWithSchedules(
    LifestyleSettings settings,
    ScheduleEngine scheduler,
    DateTime now,
  ) => _serial(() async {
    await _load();
    final change = SettingsChange(_settings!, settings);
    if (!change.scheduleChanged) {
      await _commit(_items!, settings);
      return change;
    }
    _scheduleZone = _zone(now);
    final updated = <String, InboxItem>{};
    for (final item in _items!.values) {
      updated[item.id] = item.status == ItemStatus.active
          ? _withSchedule(item, scheduler.recalculate(item, settings, now))
          : item;
    }
    await _commit(updated, settings);
    return change;
  });
}
