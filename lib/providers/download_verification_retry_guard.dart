class DownloadVerificationRetryGuard {
  final Set<String> _grantedRetryKeys = {};

  bool hasRetriedAfterGrant(String itemId, String service) =>
      _grantedRetryKeys.contains(_key(itemId, service));

  void recordVerificationResult(
    String itemId,
    String service, {
    required bool granted,
  }) {
    if (granted) {
      _grantedRetryKeys.add(_key(itemId, service));
    }
  }

  void clearItem(String itemId) {
    _grantedRetryKeys.removeWhere(
      (retryKey) => retryKey == itemId || retryKey.startsWith('$itemId::'),
    );
  }

  void retainItems(Set<String> itemIds) {
    _grantedRetryKeys.removeWhere((retryKey) {
      final itemId = retryKey.split('::').first;
      return !itemIds.contains(itemId);
    });
  }

  String _key(String itemId, String service) =>
      '$itemId::${service.trim().toLowerCase()}';
}
