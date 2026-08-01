import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/screens/settings/donate_page.dart';
import 'package:spotiflac_android/services/app_remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'refreshes remote config despite a legacy recent-fetch timestamp',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_remote_config_cached_json': jsonEncode(
          _configPayload(
            announcementId: 'cached-announcement',
            donateTitle: 'Cached donation',
          ),
        ),
        'app_remote_config_last_fetch_at': DateTime.now().toIso8601String(),
      });

      var requestCount = 0;
      final service = AppRemoteConfigService(
        endpoint: 'https://example.test/config',
        client: MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode(
              _configPayload(
                announcementId: 'fresh-announcement',
                donateTitle: 'Fresh donation',
              ),
            ),
            200,
          );
        }),
      );

      final snapshot = await service.fetchConfigSnapshot(locale: 'en-US');

      expect(requestCount, 1);
      expect(snapshot?.changed, isTrue);
      expect(snapshot?.config.announcement?.id, 'fresh-announcement');
      expect(snapshot?.config.donate.title, 'Fresh donation');
    },
  );

  test('checks the endpoint again for each remote config request', () async {
    var requestCount = 0;
    final service = AppRemoteConfigService(
      endpoint: 'https://example.test/config',
      client: MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(
            _configPayload(
              announcementId: 'announcement-$requestCount',
              donateTitle: 'Donation $requestCount',
            ),
          ),
          200,
        );
      }),
    );

    final first = await service.fetchConfigSnapshot(locale: 'en-US');
    final second = await service.fetchConfigSnapshot(locale: 'en-US');

    expect(requestCount, 2);
    expect(first?.config.announcement?.id, 'announcement-1');
    expect(second?.config.announcement?.id, 'announcement-2');
  });

  testWidgets('donate page applies a refreshed config without reopening', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_remote_config_cached_json': jsonEncode(
        _configPayload(
          announcementId: 'cached-announcement',
          donateTitle: 'Cached donation',
        ),
      ),
    });

    final response = Completer<http.Response>();
    final service = AppRemoteConfigService(
      endpoint: 'https://example.test/config',
      client: MockClient((request) => response.future),
    );

    await tester.pumpWidget(
      MaterialApp(home: DonatePage(remoteConfigService: service)),
    );
    await tester.pump();

    expect(find.text('Cached donation'), findsOneWidget);

    response.complete(
      http.Response(
        jsonEncode(
          _configPayload(
            announcementId: 'fresh-announcement',
            donateTitle: 'Fresh donation',
          ),
        ),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cached donation'), findsNothing);
    expect(find.text('Fresh donation'), findsOneWidget);
  });
}

Map<String, Object?> _configPayload({
  required String announcementId,
  required String donateTitle,
}) {
  return {
    'announcement': {
      'id': announcementId,
      'enabled': true,
      'title': 'Announcement',
      'message': 'Announcement message',
    },
    'donate': {
      'enabled': true,
      'title': donateTitle,
      'message': 'Donation message',
      'methods': [
        {
          'id': 'support',
          'title': 'Support',
          'subtitle': 'Support this project',
          'url': 'https://example.test/support',
        },
      ],
      'supporters': <String>[],
      'notices': ['Donation notice'],
    },
  };
}
