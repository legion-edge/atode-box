import 'package:atode_box/classification/basic_classifier.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifier = BasicClassifier();

  test('明確な日本語を7カテゴリへ分類し、根拠を返す', () {
    const examples = <String, ItemCategory>{
      'この記事をあとで読む': ItemCategory.read,
      '旅行の動画': ItemCategory.watch,
      '京都に行きたい': ItemCategory.go,
      '新しい靴を買いたい': ItemCategory.buy,
      '書類を提出する': ItemCategory.doTask,
      'アプリのアイデア': ItemCategory.idea,
    };
    for (final entry in examples.entries) {
      final result = classifier.classify(entry.key);
      expect(result.category, entry.value, reason: entry.key);
      expect(result.reason, ClassificationReason.phrase);
      expect(entry.key, contains(result.evidence));
    }
    final memo = classifier.classify('なんとなく気になる');
    expect(memo.category, ItemCategory.memo);
    expect(memo.reason, ClassificationReason.noSignal);
    expect(memo.evidence, isNull);
  });

  test('既知のURLホストだけを分類し、似たドメインやURL本文は推測しない', () {
    final video = classifier.classify('https://m.youtube.com/watch?v=abc');
    expect(video.category, ItemCategory.watch);
    expect(video.reason, ClassificationReason.urlHost);
    expect(video.evidence, 'youtube.com');
    expect(
      classifier.classify('https://youtu.be/abc').category,
      ItemCategory.watch,
    );
    for (final text in [
      'https://youtube.com.evil.test/watch',
      'https://example.com/動画',
      'https://example.com/article',
    ]) {
      expect(
        classifier.classify(text).category,
        ItemCategory.memo,
        reason: text,
      );
    }
  });

  test('複数カテゴリの手掛かりや曖昧な入力はメモ', () {
    for (final text in [
      '動画を見て靴を買いたい',
      'https://youtube.com/watch?v=abc の記事を読む',
      'あとで確認',
      '買い物か散歩',
      '  ',
    ]) {
      expect(
        classifier.classify(text).category,
        ItemCategory.memo,
        reason: text,
      );
    }
    expect(
      classifier.classify('動画を見て靴を買いたい').reason,
      ClassificationReason.ambiguous,
    );
  });
}
