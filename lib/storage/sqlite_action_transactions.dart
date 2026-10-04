import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../notifications/background_action.dart';
import '../scheduling/schedule_engine.dart';
import 'inbox_item.dart';
import 'lifestyle_settings.dart';

enum PrototypeActionReception { accepted, duplicate, ignored }

enum PrototypeActionDrain { empty, applied, ignored, blocked }

/// Experimental durable adapter. There is deliberately no device factory,
/// JSON migration, installation identity generator, or production caller.
/// The supplied epoch/incarnation remain the caller's unproven restore contract.
class SqliteActionTransactions implements NotificationActionTransactions {
  SqliteActionTransactions._(this.database);

  final Database database;

  static Future<SqliteActionTransactions> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        // FFI connections share an isolate. A synchronous native busy wait
        // would prevent the competing connection from completing its commit.
        onConfigure: (db) => db.execute('PRAGMA busy_timeout = 0'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE action_document (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              revision INTEGER NOT NULL CHECK (revision >= 0),
              contents TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE action_outbox (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              revision INTEGER NOT NULL CHECK (revision >= 0)
            )
          ''');
          await _createActionJournal(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion != 1 || newVersion != 2) {
            throw StateError('Unsupported action database version');
          }
          // Only our experimental v1 DB; not a production JSON migration.
          await _createActionJournal(db);
        },
        onDowngrade: (db, oldVersion, newVersion) =>
            throw StateError('Unsupported action database version'),
      ),
    );
    return SqliteActionTransactions._(database);
  }

  /// Explicit anonymous seed only; an existing canonical row always wins.
  /// No file is read and no legacy JSON fallback/import is performed.
  Future<bool> seedPrototype({
    required List<NotificationActionRecord> records,
    LifestyleSettings settings = const LifestyleSettings(),
  }) async {
    final document = _Document(0, {
      for (final record in records) record.item.id: record,
    }, settings);
    if (document.records.length != records.length) {
      throw ArgumentError('Duplicate item identity');
    }
    final notificationIds = <int>{};
    for (final record in records) {
      if (record.item.notificationId == null ||
          !notificationIds.add(record.item.notificationId!)) {
        throw ArgumentError('Missing or duplicate notification identity');
      }
      _validateRecord(record);
    }
    return _transaction((txn) async {
      if ((await txn.query('action_document')).isNotEmpty) return false;
      await txn.insert('action_document', {
        'id': 1,
        'revision': 0,
        'contents': document.encode(),
      });
      return true;
    });
  }

  @override
  Future<NotificationActionSnapshot> read(String itemId) async {
    final document = await _retryRead(() => _read(database));
    return NotificationActionSnapshot(
      revision: document.revision,
      record: document.records[itemId],
      settings: document.settings,
    );
  }

  @override
  Future<bool> compareAndSwap({
    required int expectedRevision,
    required NotificationActionRecord previous,
    required NotificationActionRecord next,
  }) => _transaction((txn) async {
    final current = await _read(txn);
    final stored = current.records[previous.item.id];
    if (current.revision != expectedRevision ||
        stored == null ||
        jsonEncode(_recordJson(stored)) != jsonEncode(_recordJson(previous))) {
      return false;
    }
    _validateRecord(next);
    if (next.item.id != previous.item.id ||
        next.item.originalText != previous.item.originalText ||
        next.item.savedAt != previous.item.savedAt ||
        next.item.notificationId != previous.item.notificationId ||
        next.incarnation != previous.incarnation ||
        next.epoch != previous.epoch ||
        next.generation != previous.generation + 1) {
      throw ArgumentError('Action changed immutable identity or generation');
    }
    current.records[next.item.id] = next;
    await _commit(txn, current);
    return true;
  });

  /// Prototype foreground intent, applied to the latest committed item.
  /// Actual LocalRepository writers are NOT connected to this adapter yet.
  Future<void> editTitleForPrototype(String itemId, String? title) =>
      _transaction((txn) async {
        final current = await _read(txn);
        final record = current.records[itemId];
        if (record == null) throw StateError('Unknown item');
        current.records[itemId] = NotificationActionRecord(
          item: record.item.copyWith(title: title),
          generation: record.generation,
          incarnation: record.incarnation,
          epoch: record.epoch,
        );
        await _commit(txn, current);
      });

  /// Latest settings can be tested with CAS retries. Production schedule
  /// recalculation and all remaining foreground intents are not implemented.
  Future<void> saveSettingsForPrototype(LifestyleSettings settings) =>
      _transaction((txn) async {
        final current = await _read(txn);
        await _commit(
          txn,
          _Document(current.revision, current.records, settings),
        );
      });

  /// Dirty revision is durable, even if OS work never starts or is interrupted.
  /// No OS delivery policy is chosen here, including for past-due requests.
  Future<int?> pendingEffectsRevision() async {
    final rows = await _retryRead(() => database.query('action_outbox'));
    return rows.isEmpty ? null : rows.single['revision'] as int;
  }

  /// Only acknowledges the observed revision. This is NOT a native OS gate:
  /// an old worker's late OS effect must still be fenced by the future gate.
  Future<bool> acknowledgeEffects(int revision) => _transaction(
    (txn) async =>
        await txn.delete(
          'action_outbox',
          where: 'id = 1 AND revision = ?',
          whereArgs: [revision],
        ) ==
        1,
  );

  /// Retry ONLY a known SQLITE_BUSY before the transaction callback starts.
  /// A callback/commit/rollback exception is never replayed, even if BUSY.
  /// Forty attempts yield between native calls; no unbounded lock wait.
  Future<T> _transaction<T>(Future<T> Function(Transaction) body) async {
    for (var attempt = 0; ; attempt++) {
      var started = false;
      try {
        return await database.transaction((txn) {
          started = true;
          return body(txn);
        }, exclusive: false); // BEGIN IMMEDIATE, not a deferred read upgrade.
      } on DatabaseException catch (error) {
        if (started || !_busy(error) || attempt == 39) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  static Future<T> _retryRead<T>(Future<T> Function() read) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await read();
      } on DatabaseException catch (error) {
        if (!_busy(error) || attempt == 39) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  static bool _busy(DatabaseException error) =>
      ((error.getResultCode() ?? -1) & 0xff) == 5;

  Future<void> close() => database.close();

  /// Durable receipt contract for a FUTURE native action entry point.
  /// Native code must perform this equivalent transaction before acknowledging
  /// its callback or cancelling the displayed notice. No callback is wired now.
  Future<PrototypeActionReception> receiveActionForPrototype({
    required String actionId,
    required String? payload,
  }) async {
    final token = NotificationActionToken.parse(payload);
    if (token == null || (actionId != 'complete' && actionId != 'snooze')) {
      return PrototypeActionReception.ignored;
    }
    final normalized = _payloadFor(token);
    return _transaction((txn) async {
      final current = await _read(txn);
      final existing = await txn.query(
        'action_journal',
        where: 'token = ? AND action = ?',
        whereArgs: [normalized, actionId],
        limit: 1,
      );
      if (existing.isNotEmpty) return PrototypeActionReception.duplicate;
      if (current.records[token.itemId]?.matches(token) != true) {
        return PrototypeActionReception.ignored;
      }
      await txn.insert('action_journal', {
        'token': normalized,
        'action': actionId,
        'state': 'pending',
      });
      return PrototypeActionReception.accepted;
    });
  }

  /// Anonymous worker prototype. Fresh settings/record, domain state, consume,
  /// receipt completion and outbox commit in ONE transaction, with no OS work.
  /// This uses Dart's existing reducer, not a duplicated native schedule policy.
  Future<PrototypeActionDrain> drainActionForPrototype({
    required DateTime now,
    ScheduleEngine scheduler = const ScheduleEngine(),
  }) => _transaction((txn) async {
    final receipts = await txn.query(
      'action_journal',
      where: 'state = ?',
      whereArgs: ['pending'],
      orderBy: 'sequence ASC',
      limit: 1,
    );
    if (receipts.isEmpty) return PrototypeActionDrain.empty;
    final receipt = receipts.single;
    final current = await _read(txn);
    final rawToken = receipt['token'];
    final token = rawToken is String
        ? NotificationActionToken.parse(rawToken)
        : null;
    final action = switch (receipt['action']) {
      'complete' => BackgroundAction.complete,
      'snooze' => BackgroundAction.snooze,
      _ => null,
    };
    if (token == null || action == null) {
      // Preserve the receipt for foreground diagnosis. Quarantine it without
      // domain/outbox writes so other independently valid receipts can proceed.
      await txn.update(
        'action_journal',
        {'state': 'blocked'},
        where: 'sequence = ?',
        whereArgs: [receipt['sequence']],
      );
      return PrototypeActionDrain.blocked;
    }
    final next = reduceBackgroundAction(
      snapshot: NotificationActionSnapshot(
        revision: current.revision,
        record: current.records[token.itemId],
        settings: current.settings,
      ),
      token: token,
      action: action,
      scheduler: scheduler,
      now: now,
    );
    if (next != null) {
      _validateRecord(next);
      current.records[next.item.id] = next;
      await _commit(txn, current);
    }
    await txn.update(
      'action_journal',
      {'state': next == null ? 'ignored' : 'applied'},
      where: 'sequence = ?',
      whereArgs: [receipt['sequence']],
    );
    return next == null
        ? PrototypeActionDrain.ignored
        : PrototypeActionDrain.applied;
  });

  static Future<void> _createActionJournal(DatabaseExecutor db) =>
      db.execute('''
    CREATE TABLE action_journal (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      token TEXT NOT NULL,
      action TEXT NOT NULL CHECK (action IN ('complete', 'snooze')),
      state TEXT NOT NULL CHECK (state IN ('pending', 'applied', 'ignored', 'blocked')),
      UNIQUE (token, action)
    )
  ''');

  static String _payloadFor(NotificationActionToken token) => jsonEncode({
    'v': 2,
    'id': token.itemId,
    'nid': token.notificationId,
    'at': token.at.toIso8601String(),
    'generation': token.generation,
    'incarnation': token.incarnation,
    'epoch': token.epoch,
  });

  static Future<_Document> _read(DatabaseExecutor executor) async {
    final rows = await executor.query('action_document');
    if (rows.length != 1) throw StateError('No canonical action document');
    final row = rows.single;
    final json = jsonDecode(row['contents'] as String) as Map<String, dynamic>;
    if (json['schema_version'] != 1) {
      throw StateError('Unsupported action document schema');
    }
    final records = <String, NotificationActionRecord>{};
    final notificationIds = <int>{};
    for (final value in json['records'] as List<dynamic>) {
      final map = value as Map<String, dynamic>;
      final record = NotificationActionRecord(
        item: InboxItem.fromJson(map['item'] as Map<String, dynamic>),
        generation: map['generation'] as int,
        incarnation: map['incarnation'] as String,
        epoch: map['epoch'] as String,
      );
      _validateRecord(record);
      if (records.containsKey(record.item.id)) {
        throw StateError('Duplicate action record');
      }
      if (!notificationIds.add(record.item.notificationId!)) {
        throw StateError('Duplicate notification identity');
      }
      records[record.item.id] = record;
    }
    return _Document(
      row['revision'] as int,
      records,
      LifestyleSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  static Future<void> _commit(Transaction txn, _Document current) async {
    if (current.revision >= 9007199254740990) {
      throw StateError('Action revision exhausted');
    }
    final revision = current.revision + 1;
    await txn.update('action_document', {
      'revision': revision,
      'contents': current.encode(),
    }, where: 'id = 1');
    await txn.insert('action_outbox', {
      'id': 1,
      'revision': revision,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static void _validateRecord(NotificationActionRecord record) {
    final item = record.item;
    if (item.id.isEmpty ||
        item.id.length > 256 ||
        record.incarnation.isEmpty ||
        record.incarnation.length > 256 ||
        record.epoch.isEmpty ||
        record.epoch.length > 256 ||
        record.generation < 0 ||
        // The terminal generation is storable but cannot appear in a payload.
        record.generation > 9007199254740991 ||
        item.notificationId == null ||
        item.notificationId! <= 0 ||
        item.notificationId! > 0x7fffffff) {
      throw ArgumentError('Invalid action identity');
    }
  }

  static Map<String, Object?> _recordJson(NotificationActionRecord record) => {
    'item': record.item.toJson(),
    'generation': record.generation,
    'incarnation': record.incarnation,
    'epoch': record.epoch,
  };
}

class _Document {
  _Document(this.revision, this.records, this.settings);
  final int revision;
  final Map<String, NotificationActionRecord> records;
  final LifestyleSettings settings;

  String encode() => jsonEncode({
    'schema_version': 1,
    'records': records.values
        .map(SqliteActionTransactions._recordJson)
        .toList(),
    'settings': settings.toJson(),
  });
}
