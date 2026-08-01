import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const backendChannel = MethodChannel('com.zarz.spotiflac/backend');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
  });

  test('duplicate session grant completions share one native call', () async {
    final nativeResult = Completer<bool>();
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (call.method != 'completeExtensionSessionGrant') return null;
          callCount++;
          return nativeResult.future;
        });

    final events = <ExtensionSessionGrantEvent>[];
    final subscription = PlatformBridge.extensionSessionGrantEvents().listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    final first = PlatformBridge.completeExtensionSessionGrant(
      ' qobuz-web ',
      'grant-value',
    );
    final second = PlatformBridge.completeExtensionSessionGrant(
      'QOBUZ-WEB',
      'grant-value',
    );

    expect(identical(first, second), isTrue);
    expect(callCount, 1);

    nativeResult.complete(true);
    expect(await Future.wait([first, second]), [isTrue, isTrue]);
    await Future<void>.delayed(Duration.zero);

    expect(callCount, 1);
    expect(events, hasLength(1));
    expect(events.single.extensionId, 'qobuz-web');
    expect(events.single.success, isTrue);
  });
}
