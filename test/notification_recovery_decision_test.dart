import 'package:atode_box/notifications/notification_recovery_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);
  final future = now.add(const Duration(minutes: 1));
  final past = now.subtract(const Duration(minutes: 1));

  test(
    'late inexact pending remains untouched, including legacy and equality',
    () {
      for (final payload in PayloadGeneration.values) {
        for (final at in [past, now]) {
          final result = decideNotificationRecovery(
            desiredAt: at,
            now: now,
            evidence: NoticeEvidence.matchingPending,
            payload: payload,
          );
          expect(result.step, RecoveryStep.preserveExisting);
          expect(result.reason, RecoveryReason.latePending);
        }
      }
    },
  );

  test(
    'absent past notification is not automatically recreated or discarded',
    () {
      for (final at in [past, now]) {
        final result = decideNotificationRecovery(
          desiredAt: at,
          now: now,
          evidence: NoticeEvidence.absent,
        );
        expect(result.step, RecoveryStep.hold);
        expect(result.reason, RecoveryReason.nonDeliveryUnproven);
      }
    },
  );

  test(
    'unknown or unrelated observations never authorize cancel or schedule',
    () {
      for (final at in [past, now, future]) {
        for (final evidence in [
          NoticeEvidence.unavailable,
          NoticeEvidence.unrelatedOrUnverifiable,
        ]) {
          expect(
            decideNotificationRecovery(
              desiredAt: at,
              now: now,
              evidence: evidence,
            ).step,
            RecoveryStep.hold,
          );
        }
      }
    },
  );

  test('displayed notification stays displayed without duplicate delivery', () {
    for (final at in [past, now, future]) {
      for (final payload in PayloadGeneration.values) {
        final result = decideNotificationRecovery(
          desiredAt: at,
          now: now,
          evidence: NoticeEvidence.matchingDisplayed,
          payload: payload,
        );
        expect(result.step, RecoveryStep.preserveExisting);
        expect(result.reason, RecoveryReason.displayed);
      }
    }
  });

  test('only matching future legacy pending is a replacement candidate', () {
    final result = decideNotificationRecovery(
      desiredAt: future,
      now: now,
      evidence: NoticeEvidence.matchingPending,
      payload: PayloadGeneration.matchingLegacy,
    );
    expect(result.step, RecoveryStep.replaceFutureLegacy);
    expect(result.reason, RecoveryReason.futureLegacy);
    expect(
      decideNotificationRecovery(
        desiredAt: future,
        now: now,
        evidence: NoticeEvidence.matchingPending,
      ).step,
      RecoveryStep.preserveExisting,
    );
    expect(
      decideNotificationRecovery(
        desiredAt: future,
        now: now,
        evidence: NoticeEvidence.absent,
      ).step,
      RecoveryStep.scheduleFuture,
    );
  });

  InstallationRecoveryDecision binding({
    bool canonical = true,
    bool legacy = false,
    bool readable = true,
    bool documentReadable = true,
    String? marker = 'fixture-epoch',
    String? document = 'fixture-epoch',
    bool proven = false,
  }) => decideInstallationRecovery(
    hasCanonicalDocument: canonical,
    hasLegacyDocument: legacy,
    markerReadable: readable,
    markerPresent: marker != null,
    documentReadable: documentReadable,
    markerEpoch: marker,
    documentEpoch: canonical ? document : null,
    restoreBoundaryProven: proven,
  );

  test('matching DB and marker alone do not prove restoration safety', () {
    final result = binding();
    expect(result.step, InstallationRecoveryStep.holdForPlatformProof);
    expect(result.reason, InstallationRecoveryReason.restoreBoundaryUnproven);
    expect(
      binding(proven: true).step,
      InstallationRecoveryStep.continueVerified,
    );
  });

  test(
    'restored DB with missing/different marker holds without epoch rotation',
    () {
      for (final marker in <String?>[null, '', 'different']) {
        expect(
          binding(marker: marker, proven: true).step,
          InstallationRecoveryStep.holdForRecovery,
        );
      }
      expect(
        binding(marker: 'different').reason,
        InstallationRecoveryReason.epochMismatch,
      );
    },
  );

  test(
    'unreadable lockscreen storage never authorizes empty initialization',
    () {
      for (final canonical in [false, true]) {
        expect(
          binding(canonical: canonical, readable: false).reason,
          InstallationRecoveryReason.markerUnreadable,
        );
      }
    },
  );

  test('existing legacy JSON does not become a fresh empty installation', () {
    expect(
      binding(canonical: false, legacy: true, marker: null).step,
      InstallationRecoveryStep.holdForRecovery,
    );
    expect(
      binding(canonical: false, legacy: true).reason,
      InstallationRecoveryReason.legacyMigrationRequired,
    );
    expect(
      binding(canonical: false, marker: null).step,
      InstallationRecoveryStep.initializeFresh,
    );
  });

  test('malformed document epoch holds despite a claimed platform proof', () {
    expect(
      binding(document: null, proven: true).step,
      InstallationRecoveryStep.holdForRecovery,
    );
    expect(
      binding(document: 'x' * 257, proven: true).reason,
      InstallationRecoveryReason.markerMissingOrMalformed,
    );
  });

  test(
    'existing marker with lost DB is recovery, not an empty installation',
    () {
      expect(
        binding(canonical: false).reason,
        InstallationRecoveryReason.canonicalDocumentMissing,
      );
      expect(
        binding(canonical: false, marker: '').step,
        InstallationRecoveryStep.holdForRecovery,
      );
    },
  );

  test('document read failure is not absence even without a marker', () {
    final result = binding(
      canonical: false,
      marker: null,
      documentReadable: false,
    );
    expect(result.step, InstallationRecoveryStep.holdForRecovery);
    expect(result.reason, InstallationRecoveryReason.documentUnreadable);
  });

  test(
    'contradictory empty-install evidence cannot authorize initialization',
    () {
      final result = decideInstallationRecovery(
        hasCanonicalDocument: false,
        hasLegacyDocument: false,
        markerReadable: true,
        documentReadable: true,
        markerPresent: false,
        markerEpoch: null,
        documentEpoch: 'unexpected',
      );
      expect(result.step, InstallationRecoveryStep.holdForRecovery);
      expect(result.reason, InstallationRecoveryReason.inconsistentEvidence);
    },
  );

  test('present but malformed marker is not collapsed into file absence', () {
    final result = decideInstallationRecovery(
      hasCanonicalDocument: false,
      hasLegacyDocument: false,
      markerReadable: true,
      documentReadable: true,
      markerPresent: true,
      markerEpoch: null,
      documentEpoch: null,
    );
    expect(result.step, InstallationRecoveryStep.holdForRecovery);
    expect(result.reason, InstallationRecoveryReason.canonicalDocumentMissing);
  });
}
