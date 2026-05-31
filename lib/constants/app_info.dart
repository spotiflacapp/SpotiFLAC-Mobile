import 'package:flutter/foundation.dart';

class AppInfo {
  static const String version = '4.5.6';
  static const String buildNumber = '133';
  static const String fullVersion = '$version+$buildNumber';

  static String get displayVersion => kDebugMode ? 'Internal' : version;

  static const String appName = 'SpotiFLAC Mobile';
  static const String copyright = '© 2026 SpotiFLAC';

  static const String mobileAuthor = 'zarzet';
  static const String originalAuthor = 'afkarxyz';

  static const String githubRepo = 'zarzet/SpotiFLAC-Mobile';
  static const String githubUrl = 'https://github.com/$githubRepo';
  static const String originalGithubUrl =
      'https://github.com/afkarxyz/SpotiFLAC';
  static const String remoteConfigApiUrl =
      'https://api.zarz.moe/v1/spotiflac-mobile/config';

  static const String kofiUrl = 'https://ko-fi.com/zarzet';
  static const String githubSponsorsUrl = 'https://github.com/sponsors/zarzet/';
}
