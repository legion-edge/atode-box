/// Proposed recovery decisions only. No production caller or OS operation.
/// Evidence must concern the exact desired item/time/token, not just its OS ID.
enum NoticeEvidence {
  matchingPending,
  matchingDisplayed,
  absent,
  unavailable,
  unrelatedOrUnverifiable,
}

enum PayloadGeneration { currentV2, matchingLegacy }

enum RecoveryStep {
  preserveExisting,
  scheduleFuture,
  replaceFutureLegacy,
  hold,
}

enum RecoveryReason {
  currentPending,
  latePending,
  displayed,
  futureMissing,
  futureLegacy,
  nonDeliveryUnproven,
  observationUnresolved,
}

class NotificationRecoveryDecision {
  const NotificationRecoveryDecision(this.step, this.reason);
  final RecoveryStep step;
  final RecoveryReason reason;
}

/// A plan is not authorization to execute. Future changes still require the
/// native gate, verified installation binding and final migration agreement.
/// OS absence is never evidence that a past request was not already delivered
/// and dismissed, or that a previous schedule call was never accepted.
NotificationRecoveryDecision decideNotificationRecovery({
  required DateTime desiredAt,
  required DateTime now,
  required NoticeEvidence evidence,
  PayloadGeneration payload = PayloadGeneration.currentV2,
}) {
  final future = desiredAt.isAfter(now);
  switch (evidence) {
    case NoticeEvidence.unavailable:
    case NoticeEvidence.unrelatedOrUnverifiable:
      return const NotificationRecoveryDecision(
        RecoveryStep.hold,
        RecoveryReason.observationUnresolved,
      );
    case NoticeEvidence.matchingDisplayed:
      return const NotificationRecoveryDecision(
        RecoveryStep.preserveExisting,
        RecoveryReason.displayed,
      );
    case NoticeEvidence.matchingPending:
      if (!future) {
        return const NotificationRecoveryDecision(
          RecoveryStep.preserveExisting,
          RecoveryReason.latePending,
        );
      }
      if (payload == PayloadGeneration.matchingLegacy) {
        return const NotificationRecoveryDecision(
          RecoveryStep.replaceFutureLegacy,
          RecoveryReason.futureLegacy,
        );
      }
      return const NotificationRecoveryDecision(
        RecoveryStep.preserveExisting,
        RecoveryReason.currentPending,
      );
    case NoticeEvidence.absent:
      return future
          ? const NotificationRecoveryDecision(
              RecoveryStep.scheduleFuture,
              RecoveryReason.futureMissing,
            )
          : const NotificationRecoveryDecision(
              RecoveryStep.hold,
              RecoveryReason.nonDeliveryUnproven,
            );
  }
}

enum InstallationRecoveryStep {
  initializeFresh,
  continueVerified,
  holdForRecovery,
  holdForPlatformProof,
}

enum InstallationRecoveryReason {
  emptyInstallation,
  legacyMigrationRequired,
  markerUnreadable,
  documentUnreadable,
  canonicalDocumentMissing,
  inconsistentEvidence,
  markerMissingOrMalformed,
  epochMismatch,
  restoreBoundaryUnproven,
  verifiedBinding,
}

class InstallationRecoveryDecision {
  const InstallationRecoveryDecision(this.step, this.reason);
  final InstallationRecoveryStep step;
  final InstallationRecoveryReason reason;
}

/// Pure fail-closed contract. It does not create/rotate an epoch, import JSON,
/// cancel notifications, discard outbox work, or declare platform proof.
/// A matching string alone cannot detect same-install snapshot rollback.
InstallationRecoveryDecision decideInstallationRecovery({
  required bool hasCanonicalDocument,
  required bool hasLegacyDocument,
  required bool markerReadable,
  required bool markerPresent,
  required bool documentReadable,
  required String? markerEpoch,
  required String? documentEpoch,
  bool restoreBoundaryProven = false,
}) {
  if (!documentReadable) {
    return const InstallationRecoveryDecision(
      InstallationRecoveryStep.holdForRecovery,
      InstallationRecoveryReason.documentUnreadable,
    );
  }
  if (!markerReadable) {
    return const InstallationRecoveryDecision(
      InstallationRecoveryStep.holdForRecovery,
      InstallationRecoveryReason.markerUnreadable,
    );
  }
  if ((!hasCanonicalDocument && documentEpoch != null) ||
      (!markerPresent && markerEpoch != null)) {
    return const InstallationRecoveryDecision(
      InstallationRecoveryStep.holdForRecovery,
      InstallationRecoveryReason.inconsistentEvidence,
    );
  }
  if (!hasCanonicalDocument) {
    if (!hasLegacyDocument && markerPresent) {
      return const InstallationRecoveryDecision(
        InstallationRecoveryStep.holdForRecovery,
        InstallationRecoveryReason.canonicalDocumentMissing,
      );
    }
    return hasLegacyDocument
        ? const InstallationRecoveryDecision(
            InstallationRecoveryStep.holdForRecovery,
            InstallationRecoveryReason.legacyMigrationRequired,
          )
        : const InstallationRecoveryDecision(
            InstallationRecoveryStep.initializeFresh,
            InstallationRecoveryReason.emptyInstallation,
          );
  }
  bool valid(String? epoch) =>
      epoch != null && epoch.isNotEmpty && epoch.length <= 256;
  if (!markerPresent || !valid(markerEpoch) || !valid(documentEpoch)) {
    return const InstallationRecoveryDecision(
      InstallationRecoveryStep.holdForRecovery,
      InstallationRecoveryReason.markerMissingOrMalformed,
    );
  }
  if (markerEpoch != documentEpoch) {
    return const InstallationRecoveryDecision(
      InstallationRecoveryStep.holdForRecovery,
      InstallationRecoveryReason.epochMismatch,
    );
  }
  return restoreBoundaryProven
      ? const InstallationRecoveryDecision(
          InstallationRecoveryStep.continueVerified,
          InstallationRecoveryReason.verifiedBinding,
        )
      : const InstallationRecoveryDecision(
          InstallationRecoveryStep.holdForPlatformProof,
          InstallationRecoveryReason.restoreBoundaryUnproven,
        );
}
