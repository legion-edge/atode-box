import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'inbox_item.dart';
import 'lifestyle_settings.dart';

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
    for (final record in records) {
      final item = InboxItem.fromJson(record as Map<String, dynamic>);
      if (items.containsKey(item.id)) {
        throw const FormatException('Duplicate item ID');
      }
      items[item.id] = item;
    }
    _items = items;
    _settings = LifestyleSettings.fromJson(
      root['settings'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<void> _persist(
    Map<String, InboxItem> items,
    LifestyleSettings settings,
  ) => store.write(
    jsonEncode({
      'schema_version': 1,
      'items': items.values.map((item) => item.toJson()).toList(),
      'settings': settings.toJson(),
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

  Future<void> saveItem(InboxItem item) => _serial(() async {
    await _load();
    if (item.id.isEmpty || item.originalText.isEmpty) {
      throw ArgumentError('Item ID and original text are required');
    }
    if (_items!.containsKey(item.id)) {
      throw StateError('Item ID already exists');
    }
    final next = {..._items!, item.id: item};
    await _commit(next, _settings!);
  });

  Future<void> updateItem(InboxItem item) => _serial(() async {
    await _load();
    final previous = _items![item.id];
    if (previous == null) throw StateError('Item does not exist');
    if (previous.originalText != item.originalText ||
        previous.savedAt != item.savedAt) {
      throw StateError('Original text and saved time cannot be changed');
    }
    final next = {..._items!, item.id: item};
    await _commit(next, _settings!);
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

  Future<void> saveSettings(LifestyleSettings settings) => _serial(() async {
    await _load();
    await _commit(_items!, settings);
  });
}
