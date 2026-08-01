// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'download_queue_provider.dart';

extension _DownloadQueueVerificationGate on DownloadQueueNotifier {
  /// Completes when the app is in the foreground. Verification challenges
  /// can only be handled there: launching a browser from the background is
  /// blocked by the OS and the challenge would expire unseen.
  Future<void> _waitForForeground() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    final completer = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await completer.future;
    } finally {
      listener.dispose();
    }
  }

  Future<bool> _openVerificationAndWait(String extensionId) {
    final key = extensionId.trim().toLowerCase();
    final activeFlow = _verificationFlowsByExtension[key];
    if (activeFlow != null) {
      _log.i(
        'Joining active verification flow for $extensionId instead of opening another challenge',
      );
      return activeFlow;
    }

    final flow = _runVerificationFlow(extensionId, key);
    _verificationFlowsByExtension[key] = flow;
    return flow;
  }

  Future<bool> _runVerificationFlow(String extensionId, String key) async {
    try {
      return await openVerificationAndAwaitGrant(
        extensionId,
        browserMode: ref
            .read(settingsProvider)
            .extensionVerificationBrowserMode,
        awaitForeground: (normalizedExtensionId) async {
          if (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed) {
            _log.i(
              'Verification required for $normalizedExtensionId while app is in '
              'background; deferring challenge until the app is foregrounded',
            );
            await _waitForForeground();
          }
        },
      );
    } finally {
      _verificationFlowsByExtension.remove(key);
    }
  }

  Future<bool> _handleVerificationRequiredDownload(
    DownloadItem item,
    String errorMsg,
    String? verificationService,
  ) async {
    final targetService = (verificationService ?? '').trim().isNotEmpty
        ? verificationService!.trim()
        : item.service;
    if (_verificationRetryGuard.hasRetriedAfterGrant(item.id, targetService)) {
      _log.e(
        'Verification was already completed once for ${item.track.name} on $targetService; not opening another challenge',
      );
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: errorMsg,
        errorType: DownloadErrorType.verificationRequired,
      );
      _failedInSession++;
      return true;
    }
    _log.i(
      'Download for ${item.track.name} requires verification; waiting for $targetService grant',
    );
    updateItemStatus(
      item.id,
      DownloadStatus.downloading,
      error: 'Waiting for verification',
      errorType: DownloadErrorType.verificationRequired,
    );

    try {
      await _notificationService.showVerificationRequired();
    } catch (error) {
      _log.w('Failed to show the verification-required notification: $error');
    }

    late final bool verified;
    try {
      verified = await _openVerificationAndWait(targetService);
    } finally {
      try {
        await _notificationService.cancelVerificationRequired();
      } catch (error) {
        _log.w(
          'Failed to clear the verification-required notification: $error',
        );
      }
    }
    final current = _findItemById(item.id);
    if (current == null || _isLocallyCancelled(item.id, item: current)) {
      _log.i('Verification completed after item was removed or cancelled');
      return true;
    }

    // Only a completed grant consumes the automatic retry. If bootstrap or
    // browser launch failed before a challenge opened, a later attempt must
    // still be allowed after the network changes.
    _verificationRetryGuard.recordVerificationResult(
      item.id,
      targetService,
      granted: verified,
    );
    if (verified) {
      _log.i(
        'Verification complete for $targetService; retrying ${item.track.name}',
      );
      updateItemStatus(
        item.id,
        DownloadStatus.queued,
        progress: 0,
        speedMBps: 0,
        error: 'Retrying after verification',
        errorType: DownloadErrorType.verificationRequired,
      );
      _saveQueueToStorage();
      return true;
    }

    _log.e('Verification did not complete for $targetService');
    updateItemStatus(
      item.id,
      DownloadStatus.failed,
      error: errorMsg,
      errorType: DownloadErrorType.verificationRequired,
    );
    _failedInSession++;
    return true;
  }

  Duration _rateLimitBackoffDelay(String errorMsg) {
    final lower = errorMsg.toLowerCase();
    final retryAfterMatch = RegExp(
      r'retry[- ]?after(?: seconds)?[:= ]+(\d+)',
      caseSensitive: false,
    ).firstMatch(lower);
    final parsedSeconds = retryAfterMatch == null
        ? null
        : int.tryParse(retryAfterMatch.group(1) ?? '');
    final seconds = (parsedSeconds ?? 30).clamp(5, 300).toInt();
    return Duration(seconds: seconds);
  }

  Future<bool> _handleRateLimitedDownload(
    DownloadItem item,
    String errorMsg,
  ) async {
    if (_rateLimitRetriedItemIds.contains(item.id)) {
      return false;
    }
    _rateLimitRetriedItemIds.add(item.id);

    final delay = _rateLimitBackoffDelay(errorMsg);
    _log.i(
      'Rate limited while downloading ${item.track.name}; retrying after ${delay.inSeconds}s',
    );
    updateItemStatus(
      item.id,
      DownloadStatus.downloading,
      error: 'Rate limited, retrying after ${delay.inSeconds}s',
      errorType: DownloadErrorType.rateLimit,
    );

    await Future<void>.delayed(delay);
    final current = _findItemById(item.id);
    if (current == null || _isLocallyCancelled(item.id, item: current)) {
      return true;
    }
    updateItemStatus(
      item.id,
      DownloadStatus.queued,
      progress: 0,
      speedMBps: 0,
      error: 'Retrying after rate limit',
      errorType: DownloadErrorType.rateLimit,
    );
    _saveQueueToStorage();
    return true;
  }
}
