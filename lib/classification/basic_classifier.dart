import '../storage/inbox_item.dart';

enum ClassificationReason { urlHost, phrase, ambiguous, noSignal }

/// [evidence] is the input's host or phrase that matched a local rule.
class ClassificationResult {
  const ClassificationResult(this.category, this.reason, {this.evidence});

  final ItemCategory category;
  final ClassificationReason reason;
  final String? evidence;
}

/// A deliberately small, offline rule set. Multiple category signals are
/// treated as ambiguous instead of choosing by rule order.
class BasicClassifier {
  const BasicClassifier();

  static const _hosts = <ItemCategory, List<String>>{
    ItemCategory.watch: ['youtube.com', 'youtu.be', 'netflix.com'],
  };

  static const _phrases = <ItemCategory, List<String>>{
    ItemCategory.read: ['あとで読む', '読みたい', '読書', '記事', 'ニュース'],
    ItemCategory.watch: ['あとで見る', '見たい動画', '動画', '映画を見る', 'ドラマを見る'],
    ItemCategory.go: ['行きたい', '行ってみたい', '訪問したい'],
    ItemCategory.buy: ['買いたい', '買う', '購入したい', '注文したい'],
    ItemCategory.doTask: ['やること', 'やらないと', '片付ける', '提出する'],
    ItemCategory.idea: ['アイデア', '思いついた', '企画案'],
  };

  ClassificationResult classify(String input) {
    final matches = <ItemCategory, ClassificationResult>{};
    final urls = RegExp(r'https?://[^\s<>]+', caseSensitive: false);
    for (final match in urls.allMatches(input)) {
      final url = Uri.tryParse(match.group(0)!);
      final host = url?.host.toLowerCase();
      if (host == null) continue;
      for (final entry in _hosts.entries) {
        for (final knownHost in entry.value) {
          if (host == knownHost || host.endsWith('.$knownHost')) {
            matches[entry.key] = ClassificationResult(
              entry.key,
              ClassificationReason.urlHost,
              evidence: host,
            );
          }
        }
      }
    }

    final prose = input.replaceAll(urls, '');
    for (final entry in _phrases.entries) {
      for (final phrase in entry.value) {
        if (prose.contains(phrase)) {
          matches.putIfAbsent(
            entry.key,
            () => ClassificationResult(
              entry.key,
              ClassificationReason.phrase,
              evidence: phrase,
            ),
          );
          break;
        }
      }
    }
    if (matches.length > 1) {
      return const ClassificationResult(
        ItemCategory.memo,
        ClassificationReason.ambiguous,
      );
    }
    if (matches.isEmpty) {
      return const ClassificationResult(
        ItemCategory.memo,
        ClassificationReason.noSignal,
      );
    }
    return matches.values.single;
  }
}
