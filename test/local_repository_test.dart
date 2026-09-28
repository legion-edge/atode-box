import 'dart:convert';
import 'dart:io';

import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingStore implements DocumentStore {
  FailingStore(this.contents);
  String? contents;
  bool fail = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String next) async {
    if (fail) throw const FileSystemException('write failed');
    contents = next;
  }
}

void main() {
  final savedAt = DateTime.utc(2026, 9, 28);
  InboxItem item(String id) => InboxItem(
    id: id,
    originalText: 'あとで読む原文 https://example.com',
    savedAt: savedAt,
  );

  test(
    'file store survives repository recreation with text, state and settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'atode_storage_test_',
      );
      try {
        final repo = LocalRepository(FileDocumentStore(directory));
        await repo.saveItem(item('1'));
        await repo.updateItem(item('1').completed());
        await repo.saveSettings(
          const LifestyleSettings(
            commuteStartMinute: 17 * 60,
            initialSetupComplete: true,
          ),
        );

        final reopened = LocalRepository(FileDocumentStore(directory));
        final saved = await reopened.getItem('1');
        expect(saved!.originalText, item('1').originalText);
        expect(saved.status, ItemStatus.completed);
        expect((await reopened.getSettings()).commuteStartMinute, 17 * 60);
        expect((await reopened.getSettings()).initialSetupComplete, isTrue);
        await reopened.updateItem(saved.deleted());
        expect(
          (await LocalRepository(FileDocumentStore(directory)).getItem('1'))!
              .status,
          ItemStatus.deleted,
        );
        await reopened.removeItem('1');
        expect(
          await LocalRepository(FileDocumentStore(directory)).getItem('1'),
          isNull,
        );
        expect(
          await File(
            '${directory.path}${Platform.pathSeparator}atode_box.json.bak',
          ).exists(),
          isFalse,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('snooze stays active and increments count', () {
    final next = DateTime.utc(2026, 9, 29);
    final snoozed = item('1').snoozed(next, notificationContext: 'after_home');
    expect(snoozed.status, ItemStatus.active);
    expect(snoozed.snoozeCount, 1);
    expect(snoozed.nextNotifyAt, next);
    expect(() => snoozed.completed().snoozed(next), throwsStateError);
    expect(snoozed.copyWith(nextNotifyAt: null).nextNotifyAt, isNull);
  });

  test('dates are stored as UTC instants', () {
    final local = DateTime(2026, 9, 28, 18);
    final value = InboxItem(
      id: 'time',
      originalText: '原文',
      savedAt: local,
      nextNotifyAt: local.add(const Duration(days: 1)),
    );
    final json = value.toJson();
    expect(json['saved_at'], local.toUtc().toIso8601String());
    expect(
      json['next_notify_at'],
      local.add(const Duration(days: 1)).toUtc().toIso8601String(),
    );
    expect(InboxItem.fromJson(json).savedAt.isAtSameMomentAs(local), isTrue);
  });

  test('backup is readable after interrupted replacement', () async {
    final directory = await Directory.systemTemp.createTemp(
      'atode_backup_test_',
    );
    try {
      final store = FileDocumentStore(directory);
      await store.write('previous');
      final current = File(
        '${directory.path}${Platform.pathSeparator}atode_box.json',
      );
      await current.rename('${current.path}.bak');
      expect(await store.read(), 'previous');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('write failure leaves previous state and propagates failure', () async {
    final store = FailingStore(null);
    final repo = LocalRepository(store);
    store.fail = true;
    await expectLater(
      repo.saveItem(item('1')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await repo.getItem('1'), isNull);
    store.fail = false;
    await repo.saveItem(item('1'));
    store.fail = true;
    await expectLater(
      repo.updateItem(item('1').completed()),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repo.getItem('1'))!.status, ItemStatus.active);
    await expectLater(
      repo.saveSettings(const LifestyleSettings(commuteStartMinute: 16 * 60)),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repo.getSettings()).commuteStartMinute, 18 * 60);
  });

  test('unversioned document gains defaults and migrates on write', () async {
    final store = FailingStore(
      jsonEncode({
        'items': [
          {
            'id': 'old',
            'original_text': '昔の原文',
            'saved_at': savedAt.toIso8601String(),
          },
        ],
      }),
    );
    final repo = LocalRepository(store);
    final old = await repo.getItem('old');
    expect(old!.status, ItemStatus.active);
    expect(old.category, ItemCategory.memo);
    expect(old.needsProcessing, isTrue);
    await repo.updateItem(old.completed());
    expect(jsonDecode(store.contents!)['schema_version'], 1);
    expect((await LocalRepository(store).getItem('old'))!.originalText, '昔の原文');
  });

  test('unknown future schema fails without overwriting data', () async {
    final source = jsonEncode({'schema_version': 2, 'items': []});
    final store = FailingStore(source);
    final repo = LocalRepository(store);
    await expectLater(repo.saveItem(item('1')), throwsFormatException);
    expect(store.contents, source);
  });
}
