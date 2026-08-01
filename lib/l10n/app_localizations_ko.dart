// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => '홈';

  @override
  String get navLibrary => '라이브러리';

  @override
  String get navSettings => '설정';

  @override
  String get navStore => '레포';

  @override
  String get homeTitle => '홈';

  @override
  String get homeSubtitle => '지원되는 URL을 붙여넣거나, 이름으로 검색하세요';

  @override
  String get homeEmptyTitle => '아직 검색 제공자가 없음';

  @override
  String get homeEmptySubtitle => '계속하려면 확장 프로그램을 설치하세요';

  @override
  String get homeSupports => '지원 항목: 트랙, 앨범, 재생목록, 아티스트 URL';

  @override
  String get homeRecent => '최근 기록';

  @override
  String get historyFilterAll => '모두';

  @override
  String get historyFilterAlbums => '앨범';

  @override
  String get historyFilterSingles => '싱글';

  @override
  String get historySearchHint => '기록 검색...';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsDownload => '다운로드';

  @override
  String get settingsAppearance => '디자인';

  @override
  String get settingsExtensions => '확장 프로그램';

  @override
  String get settingsAbout => '정보';

  @override
  String get downloadTitle => '다운로드';

  @override
  String get downloadAskQualitySubtitle => '다운로드를 할 때마다 음질을 선택하도록 합니다';

  @override
  String get downloadFilenameFormat => '파일 이름 형식';

  @override
  String get downloadSingleFilenameFormat => '싱글 파일 이름 형식';

  @override
  String get downloadSingleFilenameFormatDescription =>
      '싱글 및 EP용 파일 이름 패턴입니다. 앨범 형식과 동일한 태그를 사용합니다';

  @override
  String get downloadFolderOrganization => '폴더 분류 형식';

  @override
  String get appearanceTitle => '디자인';

  @override
  String get appearanceThemeSystem => '시스템';

  @override
  String get appearanceThemeLight => '밝은';

  @override
  String get appearanceThemeDark => '어두운';

  @override
  String get appearanceDynamicColor => '동적 색상';

  @override
  String get appearanceDynamicColorSubtitle => '배경 화면을 참고하여 강조 색상이 지정됩니다';

  @override
  String get appearanceHistoryView => '기록 정렬 방식';

  @override
  String get appearanceHistoryViewList => '리스트';

  @override
  String get appearanceHistoryViewGrid => '그리드';

  @override
  String get optionsPrimaryProvider => '기본 제공자';

  @override
  String get optionsPrimaryProviderSubtitle => '트랙 또는 앨범 이름으로 검색하는 데 사용되는 서비스';

  @override
  String optionsUsingExtension(String extensionName) {
    return '확장 프로그램 사용: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => '기본 검색 탭';

  @override
  String get optionsDefaultSearchTabSubtitle => '새 검색 결과를 표시할 탭을 먼저 선택하세요';

  @override
  String get optionsAutoFallback => '자동 대체';

  @override
  String get optionsAutoFallbackSubtitle => '다운로드가 실패한 경우에 다른 서비스를 사용합니다';

  @override
  String get optionsEmbedLyrics => '가사 삽입';

  @override
  String get optionsEmbedLyricsSubtitle => '다운로드된 트랙과 함께 동기화된 가사를 저장합니다';

  @override
  String get optionsMaxQualityCover => '고품질 표지 이미지';

  @override
  String get optionsMaxQualityCoverSubtitle => '최고 해상도의 표지 이미지를 다운로드';

  @override
  String get optionsReplayGain => '리플레이게인';

  @override
  String get optionsReplayGainSubtitleOn => '음량 스캔 및 리플레이게인 태그 삽입 (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff => '비활성화됨: 음량 정규화 태그 없음';

  @override
  String get trackReplayGain => '리플레이게인 다시 스캔';

  @override
  String get trackReplayGainScanning => '음량을 분석하는 중...';

  @override
  String get trackReplayGainSuccess => '리플레이게인 태그가 추가됨';

  @override
  String get trackReplayGainFailed => '리플레이게인 태그 추가 실패';

  @override
  String selectionReplayGainCount(int count) {
    return '리플레이게인 ($count)';
  }

  @override
  String get replayGainBatchConfirmTitle => '리플레이게인 추가';

  @override
  String replayGainBatchConfirmMessage(int count) {
    return '음량을 분석하고 $count 개의 트랙에 리플레이게인 태그를 추가하시겠습니까?';
  }

  @override
  String get replayGainBatchAnalyzing => '리플레이게인을 분석하는 중...';

  @override
  String replayGainBatchSuccess(int success, int total) {
    return '$total 개의 트랙 중 $success 개에 리플레이게인이 추가됨';
  }

  @override
  String get optionsArtistTagMode => '아티스트 태그 모드';

  @override
  String get optionsArtistTagModeDescription =>
      '여러 아티스트를 내장 태그에 작성하는 방법을 선택하세요';

  @override
  String get optionsArtistTagModeJoined => '단일 결합 값';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      '플레이어 호환성을 최대화하려면 \'아티스트 A, 아티스트 B\'와 같이 하나의 아티스트 값을 입력하세요';

  @override
  String get optionsArtistTagModeSplitVorbis => 'FLAC/Opus용 태그 분할';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'FLAC 및 Opus의 경우 아티스트당 하나의 아티스트 태그를 작성하세요. MP3 및 M4A는 병합된 상태로 유지됩니다';

  @override
  String get optionsExtensionStore => '확장 프로그램 레포';

  @override
  String get optionsExtensionStoreSubtitle => '하단바에서 레포 탭 표시';

  @override
  String get optionsCheckUpdates => '업데이트 확인';

  @override
  String get optionsCheckUpdatesSubtitle => '새 버전이 출시되면 알림';

  @override
  String get optionsUpdateChannel => '업데이트 채널';

  @override
  String get optionsUpdateChannelStable => '안정 버전만 받기';

  @override
  String get optionsUpdateChannelPreview => '베타 버전을 받기';

  @override
  String get optionsUpdateChannelWarning => '베타 버전은 불안정할 수 있습니다';

  @override
  String get optionsClearHistory => '다운로드 기록 지우기';

  @override
  String get optionsClearHistorySubtitle => '기록에서 모든 다운로드된 트랙을 제거합니다';

  @override
  String get optionsDetailedLogging => '상세 로깅';

  @override
  String get optionsDetailedLoggingOn => '상세한 로그가 기록되고 있습니다';

  @override
  String get optionsDetailedLoggingOff => '버그 보고서 활성화';

  @override
  String get extensionsTitle => '확장 프로그램';

  @override
  String get extensionsDisabled => '비활성화됨';

  @override
  String extensionsVersion(String version) {
    return '버전 $version';
  }

  @override
  String get extensionsUninstall => '제거';

  @override
  String get storeTitle => '확장 프로그램 레포';

  @override
  String get storeSearch => '확장 프로그램 검색...';

  @override
  String get storeInstall => '설치';

  @override
  String get storeInstalled => '설치됨';

  @override
  String get storeUpdate => '업데이트';

  @override
  String get aboutTitle => '정보';

  @override
  String get aboutContributors => '개발에 힘써주신 분들';

  @override
  String get aboutMobileDeveloper => '모바일 버전 개발자';

  @override
  String get aboutOriginalCreator => 'SpotiFLAC 오리지널 개발자';

  @override
  String get aboutLogoArtist => '아름다운 로고를 만들어주신 재능 있는 아티스트!';

  @override
  String get aboutTranslators => '번역에 도움주신 분들';

  @override
  String get aboutSpecialThanks => '특별히 감사드리는 분들';

  @override
  String get aboutLinks => '링크';

  @override
  String get aboutMobileSource => '모바일 소스 코드';

  @override
  String get aboutPCSource => 'PC 소스 코드';

  @override
  String get aboutKeepAndroidOpen => 'Keep Android Open';

  @override
  String get aboutReportIssue => '문제 신고';

  @override
  String get aboutReportIssueSubtitle => '발생하는 모든 문제를 신고해 주세요';

  @override
  String get aboutFeatureRequest => '기능 요청';

  @override
  String get aboutFeatureRequestSubtitle => '앱의 새 기능을 제안해 주세요';

  @override
  String get aboutTelegramChannel => '텔레그램 채널';

  @override
  String get aboutTelegramChannelSubtitle => '공지 및 업데이트 안내';

  @override
  String get aboutTelegramChat => '텔레그램 커뮤니티';

  @override
  String get aboutTelegramChatSubtitle => '다른 이용자와 소통';

  @override
  String get aboutSocial => '소셜 네트워크';

  @override
  String get aboutApp => '앱 정보';

  @override
  String get aboutVersion => '버전';

  @override
  String get aboutBinimumDesc =>
      'QQDL 및 HiFi API 개발자입니다. 이 프로젝트는 무손실 다운로드 지원을 형성하는 데 도움을 주셨습니다';

  @override
  String get aboutSachinsenalDesc =>
      'HiFi 프로젝트의 원작자이자, 무손실 음원 소스 연동 기능의 토대를 구축한 개발자입니다';

  @override
  String get aboutSjdonadoDesc =>
      'I Don\'t Have Spotify(IDHS) 개발자입니다. 위급 상황 발생 시 해결해 주는 대체 링크 해결 도구를 만들었습니다!';

  @override
  String get aboutAppDescription =>
      '음악 메타데이터를 검색하고\\n확장 프로그램을 관리하고\\n라이브러리를 정리하세요';

  @override
  String get artistAlbums => '앨범';

  @override
  String get artistSingles => '싱글 및 EP';

  @override
  String get artistCompilations => '컴필레이션';

  @override
  String get artistPopular => '인기';

  @override
  String artistMonthlyListeners(String count) {
    return '월별 청취자 $count';
  }

  @override
  String get trackMetadataService => '제공자';

  @override
  String get trackMetadataPlay => '재생';

  @override
  String get trackMetadataShare => '공유';

  @override
  String get trackMetadataDelete => '삭제';

  @override
  String get setupGrantPermission => '권한을 부여해 주세요';

  @override
  String get setupSkip => '다음에 할래요';

  @override
  String get setupStorageAccessRequired => '저장소 접근 권한 필요';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Android 11 이상 버전에서는 선택한 다운로드 폴더에 파일을 저장하려면 \'모든 파일 접근\' 권한이 필요합니다';

  @override
  String get setupOpenSettings => '설정 열기';

  @override
  String get setupPermissionDeniedMessage =>
      '권한이 거부되었습니다. 계속하려면 모든 권한을 허용해 주세요';

  @override
  String setupPermissionRequired(String permissionType) {
    return '\'\'$permissionType\'\' 권한 필요';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return '최상의 사용 경험을 위해 \'\'$permissionType\'\' 권한이 필요합니다. 설정에서 나중에 변경할 수 있습니다';
  }

  @override
  String get setupUseDefaultFolder => '기본 폴더를 사용하시겠습니까?';

  @override
  String get setupNoFolderSelected => '선택된 폴더가 없습니다. 기본 음악 폴더를 사용하시겠습니까?';

  @override
  String get setupUseDefault => '기본값 사용';

  @override
  String get setupDownloadLocationTitle => '다운로드 경로';

  @override
  String get setupDownloadLocationIosMessage =>
      'iOS에서는 다운로드된 파일이 앱의 문서 폴더에 저장됩니다. 파일 앱을 통해 해당 파일에 접근할 수 있습니다';

  @override
  String get setupAppDocumentsFolder => '앱 문서 폴더';

  @override
  String get setupAppDocumentsFolderSubtitle => '권장 사항 - 파일 앱을 통해 접근 가능';

  @override
  String get setupChooseFromFiles => '파일 탐색기에서 선택';

  @override
  String get setupChooseFromFilesSubtitle => 'iCloud 또는 다른 위치를 선택하세요';

  @override
  String get setupIosEmptyFolderWarning =>
      'iOS 제한 사항: 빈 폴더는 선택할 수 없습니다. 파일이 하나 이상 있는 폴더를 선택하세요';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive는 지원되지 않습니다. 앱의 문서 폴더를 사용해 주세요';

  @override
  String get setupDownloadInFlac => 'Spotify 음악을 FLAC 형식으로 다운로드하세요';

  @override
  String get setupStorageGranted => '저장소 접근 권한이 부여되었습니다!';

  @override
  String get setupStorageRequired => '저장소 접근 권한 필요';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC은 다운로드된 음악 파일을 저장하기 위해 저장소 접근 권한이 필요합니다';

  @override
  String get setupNotificationGranted => '알림 권한이 부여되었습니다!';

  @override
  String get setupNotificationEnable => '알림 활성화';

  @override
  String get setupFolderChoose => '다운로드 폴더를 선택하세요';

  @override
  String get setupFolderDescription => '다운로드된 음악 파일이 저장될 폴더를 선택하세요';

  @override
  String get setupSelectFolder => '폴더 선택';

  @override
  String get setupEnableNotifications => '알림 활성화';

  @override
  String get setupNotificationBackgroundDescription =>
      '알림으로 다운로드 진행 상황을 확인하세요. 앱이 백그라운드에서 실행 중일 때 다운로드 상태와 완료 여부를 확인할 수 있습니다';

  @override
  String get setupSkipForNow => '다음에 할래요';

  @override
  String get setupNext => '다음';

  @override
  String get setupGetStarted => '시작하기';

  @override
  String get setupAllowAccessToManageFiles =>
      '다음 화면에서 \'모든 파일 관리 권한 허용\'을 활성화해 주세요';

  @override
  String get setupLanguageTitle => '언어 선택';

  @override
  String get setupLanguageDescription =>
      '앱에서 사용할 언어를 선택하세요\\n나중에 설정에서 변경할 수 있습니다';

  @override
  String get setupLanguageSystemDefault => '시스템 기본값';

  @override
  String get dialogCancel => '취소';

  @override
  String get dialogSave => '저장';

  @override
  String get dialogDelete => '삭제';

  @override
  String get dialogRetry => '다시 시도';

  @override
  String get dialogClear => '지우기';

  @override
  String get dialogDone => '완료';

  @override
  String get dialogImport => '불러오기';

  @override
  String get dialogDownload => '다운로드';

  @override
  String get previewPlay => '미리듣기 재생';

  @override
  String get previewStop => '미리듣기 중지';

  @override
  String get previewUnavailable => '미리듣기를 사용할 수 없음';

  @override
  String get dialogDiscard => '폐기';

  @override
  String get dialogRemove => '제거';

  @override
  String get dialogUninstall => '삭제';

  @override
  String get dialogDiscardChanges => '변경 사항 폐기';

  @override
  String get dialogUnsavedChanges => '저장되지 않은 변경 사항이 있습니다. 폐기하시겠습니까?';

  @override
  String get dialogClearAll => '모두 지우기';

  @override
  String get dialogRemoveExtension => '확장 프로그램 제거';

  @override
  String get dialogRemoveExtensionMessage =>
      '이 확장 프로그램을 제거하시겠습니까? 이 작업은 되돌릴 수 없습니다';

  @override
  String get dialogUninstallExtension => '확장 프로그램을 제거하시겠습니까?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return '\'\'$extensionName\'\'을 제거하시겠습니까?';
  }

  @override
  String get dialogClearHistoryTitle => '기록 지우기';

  @override
  String get dialogClearHistoryMessage =>
      '모든 다운로드 기록을 지우시겠습니까? 이 작업은 되돌릴 수 없습니다';

  @override
  String get dialogDeleteSelectedTitle => '선택 항목 삭제';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '기록에서 $count 개의 $_temp0을 삭제하시겠습니까?\n\n저장소에서도 파일이 삭제됩니다';
  }

  @override
  String get dialogImportPlaylistTitle => '재생목록 가져오기';

  @override
  String dialogImportPlaylistMessage(int count) {
    return 'CSV 파일에서 $count 개의 트랙을 찾았습니다. 다운로드 목록에 추가하시겠습니까?';
  }

  @override
  String csvImportTracks(int count) {
    return 'CSV 파일의 트랙: $count';
  }

  @override
  String get collectionExportM3u => 'Export as M3U8';

  @override
  String collectionExportM3uDone(int exported, int total) {
    return 'Exported $exported of $total tracks';
  }

  @override
  String get collectionExportM3uNone => 'No downloaded files to export';

  @override
  String get collectionExportM3uFailed => 'Export failed';

  @override
  String get trackOpenOn => 'Open on...';

  @override
  String get trackOpenOnNoLinks => 'No platform links found for this track.';

  @override
  String get libraryReviewDuplicates => 'Review duplicates';

  @override
  String get libraryReviewDuplicatesSubtitle =>
      'Find tracks stored more than once';

  @override
  String get duplicatesTitle => 'Duplicates';

  @override
  String get duplicatesEmpty => 'No duplicate tracks found.';

  @override
  String get duplicatesKeepBest => 'Keep best';

  @override
  String duplicatesKeepBestMessage(int count, String trackName) {
    return 'Delete $count lower-quality copies of \"$trackName\"?';
  }

  @override
  String duplicatesDeleteCopyMessage(String trackName) {
    return 'Delete this copy of \"$trackName\"?';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return '\'\'$trackName\'\'가 다운로드 목록에 추가됨';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return '다운로드 목록에 $count 개의 트랙이 추가됨';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\'\'$trackName\'\'은 이미 다운로드되어 있음';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '라이브러리에 \'\'$trackName\'\'이 이미 존재함';
  }

  @override
  String get snackbarHistoryCleared => '기록 지워짐';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 $_temp0이 삭제됨';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return '파일을 열 수 없음: $error';
  }

  @override
  String get snackbarViewQueue => '다운로드 목록 보기';

  @override
  String snackbarUrlCopied(String platform) {
    return '$platform 링크가 클립보드에 저장됨';
  }

  @override
  String get snackbarFileNotFound => '파일을 찾을 수 없음';

  @override
  String get snackbarSelectExtFile => '.spotiflac-ext 파일을 선택하세요';

  @override
  String get snackbarProviderPrioritySaved => '제공자 우선순위가 저장됨';

  @override
  String get snackbarMetadataProviderSaved => '메타데이터 제공자 우선순위가 저장됨';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '\'\'$extensionName\'\'이 설치됨';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '\'\'$extensionName\'\'이 설치됨';
  }

  @override
  String get snackbarFailedToInstall => '확장 프로그램 설치 실패';

  @override
  String get snackbarFailedToUpdate => '확장 프로그램 업데이트 실패';

  @override
  String get errorRateLimited => '사용 제한됨';

  @override
  String get errorRateLimitedMessage => '요청이 너무 많습니다. 잠시 후 다시 검색해 주세요';

  @override
  String get errorNoTracksFound => '트랙을 찾을 수 없음';

  @override
  String get searchEmptyResultSubtitle => '다른 키워드를 검색해 보세요';

  @override
  String get errorUrlNotRecognized => '링크를 인식할 수 없음';

  @override
  String get errorUrlNotRecognizedMessage =>
      '이 링크는 지원되지 않습니다. URL이 올바른지, 호환되는 확장 프로그램이 설치되어 있는지 확인하세요';

  @override
  String get errorUrlFetchFailed => '이 링크에서 콘텐츠를 불러오는 데 실패하였습니다. 다시 시도해 주세요';

  @override
  String errorMissingExtensionSource(String item) {
    return '\'\'$item\'\'을 불러올 수 없음: 확장 소스가 누락됨';
  }

  @override
  String get actionPause => '일시 중지';

  @override
  String get actionResume => '계속';

  @override
  String get actionCancel => '취소';

  @override
  String get actionSelectAll => '모두 선택';

  @override
  String get actionDeselect => '선택 해제';

  @override
  String selectionSelected(int count) {
    return '$count 개 선택됨';
  }

  @override
  String get selectionAllSelected => '모든 트랙 선택됨';

  @override
  String get selectionSelectToDelete => '삭제할 트랙을 선택';

  @override
  String progressFetchingMetadata(int current, int total) {
    return '메타데이터를 가져오는 중... $current/$total';
  }

  @override
  String get progressReadingCsv => 'CSV 파일을 읽는 중...';

  @override
  String get searchSongs => '노래';

  @override
  String get searchArtists => '아티스트';

  @override
  String get searchAlbums => '앨범';

  @override
  String get searchPlaylists => '재생목록';

  @override
  String get searchSortTitle => '결과 정렬';

  @override
  String get searchSortDefault => '기본값';

  @override
  String get searchSortTitleAZ => '제목 (오름차순)';

  @override
  String get searchSortTitleZA => '제목 (내림차순)';

  @override
  String get searchSortArtistAZ => '아티스트 (오름차순)';

  @override
  String get searchSortArtistZA => '아티스트 (내림차순)';

  @override
  String get searchSortDurationShort => '재생시간 (짧은순)';

  @override
  String get searchSortDurationLong => '재생시간 (긴순)';

  @override
  String get searchSortDateOldest => '발매일자 (오래된순)';

  @override
  String get searchSortDateNewest => '발매일자 (최신순)';

  @override
  String get tooltipPlay => '재생';

  @override
  String get filenameFormat => '파일 이름 형식';

  @override
  String get filenameShowAdvancedTags => '고급 태그 표시';

  @override
  String get filenameShowAdvancedTagsDescription =>
      '트랙 패딩 및 날짜 패턴에 대한 서식 있는 태그를 활성화합니다';

  @override
  String get folderOrganizationNone => '정리하지 않음';

  @override
  String get folderOrganizationByPlaylist => '재생목록별';

  @override
  String get folderOrganizationByPlaylistSubtitle => '각 재생목록별 별도 폴더';

  @override
  String get folderOrganizationByArtist => '아티스트별';

  @override
  String get folderOrganizationByAlbum => '앨범별';

  @override
  String get folderOrganizationByArtistAlbum => '아티스트/앨범';

  @override
  String get folderOrganizationDescription => '다운로드된 파일을 폴더로 정리';

  @override
  String get folderOrganizationNoneSubtitle => '다운로드 폴더의 모든 파일';

  @override
  String get folderOrganizationByArtistSubtitle => '각 아티스트별 별도 폴더';

  @override
  String get folderOrganizationByAlbumSubtitle => '각 앨범별 별도 폴더';

  @override
  String get folderOrganizationByArtistAlbumSubtitle => '아티스트 및 앨범용 중첩 폴더';

  @override
  String get updateAvailable => '업데이트 사용 가능';

  @override
  String get updateLater => '나중에';

  @override
  String get updateStartingDownload => '다운로드를 시작하는 중...';

  @override
  String get updateDownloadFailed => '다운로드 실패';

  @override
  String get updateFailedMessage => '업데이트 다운로드 실패';

  @override
  String get updateNewVersionReady => '새 버전이 준비되었습니다';

  @override
  String get updateRequiredTitle => '업데이트 필요';

  @override
  String updateRequiredNotice(int count) {
    return '이 버전은 최신 버전보다 $count 개 이전 버전이며 더 이상 지원되지 않습니다. 앱을 계속 사용하려면 업데이트하세요';
  }

  @override
  String get updateCurrent => '현재 버전';

  @override
  String get updateNew => '새 버전';

  @override
  String get updateDownloading => '다운로드하는 중...';

  @override
  String get updateWhatsNew => '새 기능';

  @override
  String get updateDownloadInstall => '다운로드 & 설치';

  @override
  String get updateDontRemind => '알림 안 함';

  @override
  String get providerPriorityTitle => '제공자 우선순위';

  @override
  String get providerPriorityDescription =>
      '드래그하여 다운로드 제공자 순서를 변경하세요. 앱은 트랙을 다운로드할 경우에 위에서 아래로 제공자를 차례로 시도합니다';

  @override
  String get providerPriorityInfo =>
      '첫 ​​번째 제공자에서 트랙을 사용할 수 없는 경우에 앱은 자동으로 다음 제공자를 시도합니다';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      '자동 대체 중에 사용할 수 있는 설치된 다운로드 확장 프로그램을 선택하세요';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      '다운로드 공급자 기능이 활성화된 확장 프로그램만 여기에 나열됩니다';

  @override
  String get providerExtension => '확장 프로그램';

  @override
  String get metadataProviderPriorityTitle => '메타데이터 우선순위';

  @override
  String get metadataProviderPriorityDescription =>
      '드래그하여 메타데이터 제공자 순서를 변경하세요. 앱은 트랙을 검색하고 메타데이터를 가져올 경우에 위에서 아래로 제공자를 시도합니다';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer는 요청 횟수 제한이 없으므로 기본 앱으로 사용하는 것이 좋습니다. Spotify는 요청 횟수가 많아지면 요청 횟수를 제한할 수 있습니다';

  @override
  String get logTitle => '로그';

  @override
  String get logCopied => '로그가 클립보드에 복사됨';

  @override
  String get logSearchHint => '로그 검색...';

  @override
  String get logFilterLevel => '레벨';

  @override
  String get logFilterSection => '필터';

  @override
  String get logShareLogs => '로그 공유';

  @override
  String get logClearLogs => '로그 지우기';

  @override
  String get logClearLogsTitle => '로그 지우기';

  @override
  String get logClearLogsMessage => '모든 로그를 지우시겠습니까?';

  @override
  String get logFilterBySeverity => '심각성에 따라 로그 분류';

  @override
  String get logNoLogsYet => '아직 로그 없음';

  @override
  String get logNoLogsYetSubtitle => '앱을 사용하는 동안에 로그가 여기에 표시됩니다';

  @override
  String logEntriesFiltered(int count) {
    return '항목 ($count 개 필터됨)';
  }

  @override
  String logEntries(int count) {
    return '항목 ($count)';
  }

  @override
  String get channelStable => '안정';

  @override
  String get channelPreview => '베타';

  @override
  String get sectionSearchSource => '검색 출처';

  @override
  String get sectionDownload => '다운로드';

  @override
  String get sectionPerformance => '성능';

  @override
  String get sectionApp => '앱';

  @override
  String get sectionData => '데이터';

  @override
  String get sectionDebug => '디버그';

  @override
  String get sectionService => '서비스';

  @override
  String get sectionAudioQuality => '오디오 음질';

  @override
  String get sectionFileSettings => '파일 설정';

  @override
  String get sectionLyrics => '가사';

  @override
  String get lyricsMode => '가사 설정';

  @override
  String get lyricsModeDescription => '다운로드된 파일에 가사를 저장하는 방법을 선택하세요';

  @override
  String get lyricsModeEmbed => '파일에 포함';

  @override
  String get lyricsModeEmbedSubtitle => 'FLAC 메타데이터 내에 저장됩니다';

  @override
  String get lyricsModeExternal => '외부 .lrc 파일';

  @override
  String get lyricsModeExternalSubtitle => '삼성 뮤직과 같은 플레이어용 별도 .lrc 파일';

  @override
  String get lyricsModeBoth => '둘 다';

  @override
  String get lyricsModeBothSubtitle => '.lrc 파일을 삽입하고 저장합니다';

  @override
  String get sectionColor => '색상';

  @override
  String get sectionTheme => '테마';

  @override
  String get sectionLayout => '레이아웃';

  @override
  String get sectionLanguage => '언어';

  @override
  String get appearanceLanguage => '앱 언어';

  @override
  String get settingsAppearanceSubtitle => '테마, 색상, 디스플레이';

  @override
  String get settingsDownloadSubtitle => '서비스, 음질, 대체';

  @override
  String get settingsExtensionsSubtitle => '다운로드 제공자 관리';

  @override
  String get settingsLogsSubtitle => '디버깅을 위한 앱 로그 보기';

  @override
  String get loadingSharedLink => '공유된 링크를 불러오는 중...';

  @override
  String get pressBackAgainToExit => '종료하려면 뒤로가기 버튼을 다시 탭하세요';

  @override
  String downloadAllCount(int count) {
    return '모두 다운로드 ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 트랙',
      one: '1 개의 트랙',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => '파일 경로 복사';

  @override
  String get trackRemoveFromDevice => '기기에서 제거';

  @override
  String get trackLoadLyrics => '가사 불러오기';

  @override
  String get trackMetadata => '메타데이터';

  @override
  String get trackFileInfo => '파일 정보';

  @override
  String get trackLyrics => '가사';

  @override
  String get trackFileNotFound => '파일을 찾을 수 없음';

  @override
  String get trackOpenInDeezer => 'Deezer에서 열기';

  @override
  String get trackOpenInSpotify => 'Spotify에서 열기';

  @override
  String get trackTrackName => '트랙 이름';

  @override
  String get trackArtist => '아티스트';

  @override
  String get trackAlbumArtist => '앨범 아티스트';

  @override
  String get trackAlbum => '앨범';

  @override
  String get trackTrackNumber => '트랙 번호';

  @override
  String get trackDiscNumber => '디스크 번호';

  @override
  String get trackDuration => '재생시간';

  @override
  String get trackAudioQuality => '오디오 음질';

  @override
  String get trackReleaseDate => '발매일자';

  @override
  String get trackGenre => '장르';

  @override
  String get trackLabel => '레이블';

  @override
  String get trackCopyright => '저작권';

  @override
  String get trackDownloaded => '다운로드됨';

  @override
  String get trackCopyLyrics => '가사 복사';

  @override
  String trackLyricsSource(String source) {
    return '출처: $source';
  }

  @override
  String get trackLyricsNotAvailable => '이 트랙의 가사를 사용할 수 없습니다';

  @override
  String get trackLyricsNotInFile => '이 파일에서 가사를 찾을 수 없습니다';

  @override
  String get trackFetchOnlineLyrics => '온라인에서 가져오기';

  @override
  String get trackLyricsTimeout => '요청 시간이 초과되었습니다. 나중에 다시 시도하세요';

  @override
  String get trackLyricsLoadFailed => '가사 불러오기 실패';

  @override
  String get trackEmbedLyrics => '가사 삽입';

  @override
  String get trackLyricsEmbedded => '가사 삽입 성공';

  @override
  String get trackInstrumental => '반주 트랙';

  @override
  String get trackCopiedToClipboard => '클립보드에 복사됨';

  @override
  String get trackDeleteConfirmTitle => '기기에서 제거하시겠습니까?';

  @override
  String get trackDeleteConfirmMessage =>
      '이렇게 하면 다운로드된 파일이 영구적으로 삭제되고 기록에서 제거됩니다';

  @override
  String get dateToday => '오늘';

  @override
  String get dateYesterday => '어제';

  @override
  String dateDaysAgo(int count) {
    return '$count 일 전';
  }

  @override
  String dateWeeksAgo(int count) {
    return '$count 주 전';
  }

  @override
  String dateMonthsAgo(int count) {
    return '$count 달 전';
  }

  @override
  String get storeFilterAll => '모두';

  @override
  String get storeFilterMetadata => '메타데이터';

  @override
  String get storeFilterDownload => '다운로드';

  @override
  String get storeFilterUtility => '유틸리티';

  @override
  String get storeFilterLyrics => '가사';

  @override
  String get storeFilterIntegration => '연동';

  @override
  String get storeClearFilters => '필터 지우기';

  @override
  String get storeAddRepoTitle => '확장 프로그램 레포지토리 추가';

  @override
  String get storeAddRepoDescription =>
      '확장 프로그램을 찾아보고 설치하려면 registry.json 파일이 포함된 GitHub 레포지토리 URL을 입력하세요';

  @override
  String get storeRepoUrlLabel => '레포지토리 URL';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeAddRepoButton => '레포지토리 추가';

  @override
  String get storeChangeRepoTooltip => '레포지토리 변경';

  @override
  String get storeRepoDialogTitle => '확장 프로그램 레포지토리';

  @override
  String get storeRepoDialogCurrent => '현재 레포지토리:';

  @override
  String get storeNewRepoUrlLabel => '새 레포지토리 URL';

  @override
  String get storeLoadError => '레포지토리 불러오기 실패';

  @override
  String get storeEmptyNoExtensions => '사용 가능한 확장 프로그램이 없음';

  @override
  String get storeEmptyNoResults => '확장 프로그램을 찾을 수 없음';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => '오류';

  @override
  String get extensionCapabilities => '기능';

  @override
  String get extensionMetadataProvider => '메타데이터 제공자';

  @override
  String get extensionDownloadProvider => '다운로드 제공자';

  @override
  String get extensionLyricsProvider => '가사 제공자';

  @override
  String get extensionUrlHandler => 'URL 핸들러';

  @override
  String get extensionQualityOptions => '음질 옵션';

  @override
  String get extensionPostProcessingHooks => '후처리 후크';

  @override
  String get extensionPermissions => '권한';

  @override
  String get extensionSettings => '설정';

  @override
  String get extensionRemoveButton => '확장 프로그램 제거';

  @override
  String get extensionUpdated => '업데이트됨';

  @override
  String get extensionMinAppVersion => '최소 앱 버전';

  @override
  String get extensionCustomTrackMatching => '사용자 정의 트랙 매칭';

  @override
  String get extensionPostProcessing => '후처리';

  @override
  String extensionHooksAvailable(int count) {
    return '$count 개의 후크 사용 가능';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count 개의 패턴';
  }

  @override
  String extensionStrategy(String strategy) {
    return '전략: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => '제공자 우선순위';

  @override
  String get extensionsInstalledSection => '설치된 확장 프로그램';

  @override
  String get extensionsNoExtensions => '설치된 확장 프로그램이 없음';

  @override
  String get extensionsNoExtensionsSubtitle =>
      '새 제공자를 추가하려면 .spotiflac-ext 파일을 설치하세요';

  @override
  String get extensionsInstallButton => '확장 프로그램 설치';

  @override
  String get extensionsInfoTip =>
      '확장 프로그램은 새 메타데이터와 다운로드 제공자를 추가할 수 있습니다. 신뢰할 수 있는 출처에서만 확장 프로그램을 설치하세요';

  @override
  String get extensionsInstalledSuccess => '확장 프로그램 설치 성공';

  @override
  String extensionsInstalledCount(int count) {
    return '$count 개의 확장 프로그램 설치 성공';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return '$attempted 개의 확장 프로그램 중 $installed 개가 설치됨';
  }

  @override
  String get extensionsDownloadPriority => '다운로드 우선순위';

  @override
  String get extensionsDownloadPrioritySubtitle => '다운로드 서비스 순서를 설정하세요';

  @override
  String get extensionsFallbackTitle => '대체 확장 프로그램';

  @override
  String get extensionsFallbackSubtitle =>
      '설치된 다운로드 확장 프로그램 중 대체 프로그램으로 사용할 항목을 선택하세요';

  @override
  String get extensionsNoDownloadProvider => '다운로드 제공자가 있는 확장 프로그램가 없음';

  @override
  String get extensionsMetadataPriority => '메타데이터 우선순위';

  @override
  String get extensionsMetadataPrioritySubtitle => '검색 & 메타데이터 출처 순서 설정';

  @override
  String get extensionsNoMetadataProvider => '메타데이터 제공자가 있는 확장 프로그램이 없음';

  @override
  String get extensionsSearchProvider => '검색 제공자';

  @override
  String get extensionsNoCustomSearch => '사용자 정의 검색이 있는 확장 프로그램이 없음';

  @override
  String get extensionsSearchProviderDescription => '트랙 검색에 사용할 서비스를 선택하세요';

  @override
  String get extensionsCustomSearch => '사용자 정의 검색';

  @override
  String get extensionsErrorLoading => '확장 프로그램 불러오기 오류';

  @override
  String get qualityFlacLossless => 'FLAC 무손실';

  @override
  String get qualityFlacLosslessSubtitle => '16-bit / 44.1kHz';

  @override
  String get qualityHiResFlac => 'Hi-Res FLAC';

  @override
  String get qualityHiResFlacSubtitle => '24-bit / 최대 96kHz';

  @override
  String get qualityHiResFlacMax => 'Hi-Res FLAC Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-bit / 최대 192kHz';

  @override
  String get downloadLossy320 => '손실 압축 320kbps';

  @override
  String get downloadLossyFormat => '손실 압축 형식';

  @override
  String get downloadLossy320Format => '손실 압축 320kbps 형식';

  @override
  String get downloadLossy320FormatDesc =>
      '320kbps 손실 다운로드의 출력 형식을 선택하세요. 필요에 따라 원본 스트림이 선택한 형식으로 변환됩니다';

  @override
  String get downloadLossyMp3 => 'MP3 320kbps';

  @override
  String get downloadLossyMp3Subtitle => '최상의 호환성, 트랙당 약 10MB';

  @override
  String get downloadLossyAac => 'AAC/M4A 320kbps';

  @override
  String get downloadLossyAacSubtitle => '최상의 모바일 호환성, M4A 컨테이너';

  @override
  String get downloadLossyOpus256 => 'Opus 256kbps';

  @override
  String get downloadLossyOpus256Subtitle => '최고 음질 Opus, 트랙당 약 8MB';

  @override
  String get downloadLossyOpus128 => 'Opus 128kbps';

  @override
  String get downloadLossyOpus128Subtitle => '트랙당 최소 크기, 약 4MB';

  @override
  String get downloadAskBeforeDownload => '다운로드 전 확인';

  @override
  String get downloadDirectory => '다운로드 디렉토리';

  @override
  String get downloadSeparateSinglesFolder => '싱글 폴더 별도 다운로드';

  @override
  String get downloadAlbumFolderStructure => '앨범 폴더 구조';

  @override
  String get albumFolderStructureDescription => '앨범 폴더 구조를 선택하세요';

  @override
  String get downloadUseAlbumArtistForFolders => '폴더에 앨범 아티스트 사용';

  @override
  String get downloadUsePrimaryArtistOnly => '폴더에 기본 아티스트만 사용';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      '폴더 이름에서 피처링 아티스트가 제거됩니다 (예: Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      '폴더 이름에 전체 아티스트 문자열이 사용됩니다';

  @override
  String get downloadSelectQuality => '음질 선택';

  @override
  String get downloadFrom => '다운로드 제공자 선택';

  @override
  String get appearanceAmoledDark => '아몰레드 블랙';

  @override
  String get appearanceAmoledDarkSubtitle => '순수 검정 배경화면';

  @override
  String get appearanceHeroAnimations => '히어로 애니메이션';

  @override
  String get appearanceHeroAnimationsSubtitle =>
      '화면 간 이동 시 표지 이미지가 날아가는 애니메이션을 표시합니다 (예시: 플레이어를 실행할 경우)';

  @override
  String get appearanceForceBlur => 'Always use blur effects';

  @override
  String get appearanceForceBlurSubtitle =>
      'Enable the navigation bar blur even on devices where it is off by default. May cost performance.';

  @override
  String get queueClearAll => '모두 지우기';

  @override
  String get queueClearAllMessage => '모든 다운로드를 지우시겠습니까?';

  @override
  String get settingsAutoExportFailed => '실패한 다운로드 자동 내보내기';

  @override
  String get settingsAutoExportFailedSubtitle => '실패한 다운로드를 TXT 파일으로 자동 저장합니다';

  @override
  String get settingsDownloadNetwork => '다운로드 네트워크';

  @override
  String get settingsDownloadNetworkAny => 'WiFi + 모바일 네트워크';

  @override
  String get settingsDownloadNetworkWifiOnly => 'WiFi 전용';

  @override
  String get settingsDownloadNetworkSubtitle =>
      '다운로드에 사용할 네트워크를 선택하세요. Wi-Fi 전용으로 설정하면 모바일 데이터 사용 시 다운로드가 일시 중지됩니다';

  @override
  String get settingsConcurrentDownloads => '동시 다운로드';

  @override
  String get settingsConcurrentDownloadsSubtitle =>
      '여러 트랙을 동시에 다운로드하면 속도는 빨라지지만, 일부 제공자는 동시 요청을 제한할 수 있습니다';

  @override
  String get concurrentDownloadsOne => '한 번에 1개의 트랙';

  @override
  String concurrentDownloadsCount(int count) {
    return '한 번에 최대 $count 개의 트랙';
  }

  @override
  String get albumFolderArtistAlbum => '아티스트 / 앨범';

  @override
  String get albumFolderArtistAlbumSubtitle => '앨범/아티스트 이름/앨범 이름/';

  @override
  String get albumFolderArtistYearAlbum => '아티스트 / [연도] 앨범';

  @override
  String get albumFolderArtistYearAlbumSubtitle => '앨범/아티스트 이름/[2005] 앨범 이름/';

  @override
  String get albumFolderAlbumOnly => '앨범만';

  @override
  String get albumFolderAlbumOnlySubtitle => '앨범/앨범 이름/';

  @override
  String get albumFolderYearAlbum => '[연도] 앨범';

  @override
  String get albumFolderYearAlbumSubtitle => '앨범/[2005] 앨범 이름/';

  @override
  String get albumFolderArtistAlbumSingles => '아티스트 / 앨범 + 싱글';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle => '아티스트/앨범/ 및 아티스트/싱글/';

  @override
  String get albumFolderArtistAlbumFlat => '아티스트 / 앨범 (싱글 플랫)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle => '아티스트/앨범/ 및 아티스트/song.flac';

  @override
  String get downloadedAlbumDeleteSelected => '선택 항목 삭제';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '앨범에서 $count 개의 $_temp0을 삭제하시겠습니까?\n\n저장소에서도 파일이 삭제됩니다';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count 개 선택됨';
  }

  @override
  String get downloadedAlbumTapToSelect => '트랙을 탭하여 선택하세요';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count $_temp0 삭제';
  }

  @override
  String get downloadedAlbumSelectToDelete => '삭제할 트랙 선택';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return '디스크 $discNumber';
  }

  @override
  String get recentTypeArtist => '아티스트';

  @override
  String get recentTypeAlbum => '앨범';

  @override
  String get recentTypeSong => '노래';

  @override
  String get recentTypePlaylist => '재생목록';

  @override
  String get recentEmpty => '최근 항목이 없음';

  @override
  String get recentShowAllDownloads => '모든 다운로드 표시';

  @override
  String recentPlaylistInfo(String name) {
    return '재생목록: $name';
  }

  @override
  String get discographyDownload => '디스코그래피 다운로드';

  @override
  String get discographyDownloadAll => '모두 다운로드';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$albumCount 개의 발매 음악에서 $count 개의 트랙';
  }

  @override
  String get discographyAlbumsOnly => '앨범만';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$albumCount 개의 앨범에서 $count 개의 트랙';
  }

  @override
  String get discographySinglesOnly => '싱글 & EP만';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$albumCount 개의 싱글에서 $count 개의 트랙';
  }

  @override
  String get discographySelectAlbums => '앨범 검색...';

  @override
  String get discographySelectAlbumsSubtitle => '특정 앨범 또는 싱글을 선택하세요';

  @override
  String get discographyFetchingTracks => '트랙을 가져오는 중...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return '$total 개 중 $current 개를 가져오는 중...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count 개 선택됨';
  }

  @override
  String get discographyDownloadSelected => '선택 항목 다운로드';

  @override
  String discographyAddedToQueue(int count) {
    return '다운로드 목록에 $count 개의 트랙이 추가됨';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added 개 추가됨, $skipped 개 이미 다운로드됨';
  }

  @override
  String get discographyNoAlbums => '사용 가능한 앨범이 없음';

  @override
  String get discographyFailedToFetch => '일부 앨범 가져오기 실패';

  @override
  String get sectionStorageAccess => '저장소 접근';

  @override
  String get allFilesAccess => '모든 파일 접근';

  @override
  String get allFilesAccessEnabledSubtitle => '모든 폴더에 쓰기 가능';

  @override
  String get allFilesAccessDisabledSubtitle => '미디어 폴더에만 제한됨';

  @override
  String get allFilesAccessDescription =>
      '사용자 정의 폴더에 저장할 경우에 쓰기 오류가 발생하면 이 옵션을 활성화하세요. Android 13 이상에서는 기본적으로 특정 디렉터리에 대한 접근이 제한됩니다';

  @override
  String get allFilesAccessDeniedMessage =>
      '권한이 거부되었습니다. 시스템 설정에서 \'모든 파일 접근\'를 수동으로 활성화하세요';

  @override
  String get allFilesAccessDisabledMessage =>
      '모든 파일 접근을 비활성화하였습니다. 앱은 제한된 저장소 접근을 사용합니다';

  @override
  String get settingsLocalLibrary => '로컬 라이브러리';

  @override
  String get settingsLocalLibrarySubtitle => '음악 스캔 & 중복 감지';

  @override
  String get settingsCache => '저장소 & 캐시';

  @override
  String get settingsCacheSubtitle => '크기 보기 및 캐시된 데이터 지우기';

  @override
  String get libraryTitle => '로컬 라이브러리';

  @override
  String get libraryScanSettings => '스캔 설정';

  @override
  String get libraryEnableLocalLibrary => '로컬 라이브러리 활성화';

  @override
  String get libraryEnableLocalLibrarySubtitle => '기존 음악을 스캔하고 추적하세요';

  @override
  String get libraryFolder => '라이브러리 폴더';

  @override
  String get libraryFolderHint => '탭하여 폴더를 선택하세요';

  @override
  String get libraryShowDuplicateIndicator => '중복 표시기 표시';

  @override
  String get libraryShowDuplicateIndicatorSubtitle => '기존 트랙을 검색할 때 표시';

  @override
  String get libraryAutoScan => '자동 스캔';

  @override
  String get libraryAutoScanSubtitle => '라이브러리에서 새 파일을 자동으로 스캔합니다';

  @override
  String get libraryAutoScanOff => '끄기';

  @override
  String get libraryAutoScanOnOpen => '앱을 열 때마다';

  @override
  String get libraryAutoScanDaily => '매일';

  @override
  String get libraryAutoScanWeekly => '주간';

  @override
  String get libraryActions => '작업';

  @override
  String get libraryScan => '라이브러리 스캔';

  @override
  String get libraryScanSubtitle => '오디오 파일 스캔';

  @override
  String get libraryScanSelectFolderFirst => '먼저 폴더를 선택하세요';

  @override
  String get libraryCleanupMissingFiles => '누락된 파일 정리';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      '더 이상 존재하지 않는 파일에 대한 항목을 제거합니다';

  @override
  String get libraryClear => '라이브러리 정리';

  @override
  String get libraryClearSubtitle => '스캔된 모든 트랙 제거';

  @override
  String get libraryClearConfirmTitle => '라이브러리 정리';

  @override
  String get libraryClearConfirmMessage =>
      '이렇게 하면 라이브러리에서 스캔된 모든 트랙이 제거됩니다. 실제 음악 파일은 삭제되지 않습니다';

  @override
  String get libraryAbout => '로컬 라이브러리에 대한 정보';

  @override
  String get libraryAboutDescription =>
      '기존 음악 라이브러리를 검사하여 다운로드 시 중복 곡을 감지합니다. FLAC, ALAC, M4A, MP3, Opus, OGG, WAV, AIFF 및 APE 형식을 지원합니다. 가능한 경우 파일 태그의 메타데이터를 읽어 사용합니다';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일',
      one: '파일',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return '마지막 스캔 시간: $time';
  }

  @override
  String get libraryLastScannedNever => '스캔한 적 없음';

  @override
  String get libraryScanning => '스캔하는 중...';

  @override
  String get libraryScanFinalizing => '라이브러리를 마무리하는 중...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$total 개의 파일 중 $progress%';
  }

  @override
  String get libraryInLibrary => 'in 라이브러리';

  @override
  String libraryRemovedMissingFiles(int count) {
    return '라이브러리에서 $count 개의 누락된 파일이 삭제됨';
  }

  @override
  String get libraryCleared => '라이브러리가 초기화됨';

  @override
  String get libraryStorageAccessRequired => '저장소 접근 권한 필요';

  @override
  String get libraryStorageAccessMessage =>
      'SpotifyFLAC은 음악 라이브러리를 스캔하기 위해 저장소 접근 권한이 필요합니다. 설정에서 권한을 부여해 주세요';

  @override
  String get libraryFolderNotExist => '선택한 폴더가 존재하지 않음';

  @override
  String get librarySourceDownloaded => '다운로드됨';

  @override
  String get librarySourceLocal => '로컬';

  @override
  String get libraryFilterAll => '모두';

  @override
  String get libraryFilterDownloaded => '다운로드됨';

  @override
  String get libraryFilterLocal => '로컬';

  @override
  String get libraryFilterTitle => '필터';

  @override
  String get libraryFilterReset => '초기화';

  @override
  String get libraryFilterApply => '적용';

  @override
  String get libraryFilterSource => '출처';

  @override
  String get libraryFilterQuality => '음질';

  @override
  String get libraryFilterQualityHiRes => 'Hi-Res (24bit)';

  @override
  String get libraryFilterQualityCD => 'CD (16bit)';

  @override
  String get libraryFilterQualityLossy => '손실 압축';

  @override
  String get libraryFilterFormat => '형식';

  @override
  String get libraryFilterMetadata => '메타데이터';

  @override
  String get libraryFilterMetadataComplete => '전체 메타데이터';

  @override
  String get libraryFilterMetadataMissingAny => '메타데이터 누락';

  @override
  String get libraryFilterMetadataMissingYear => '연도 누락';

  @override
  String get libraryFilterMetadataMissingGenre => '장르 누락';

  @override
  String get libraryFilterMetadataMissingAlbumArtist => '앨범 아티스트 누락';

  @override
  String get libraryFilterSort => '정렬';

  @override
  String get libraryFilterSortLatest => '최신순';

  @override
  String get libraryFilterSortOldest => '오래된순';

  @override
  String get libraryFilterSortAlbumAsc => '앨범 (오름차순)';

  @override
  String get libraryFilterSortAlbumDesc => '앨범 (내림차순)';

  @override
  String get libraryFilterSortGenreAsc => '장르 (오름차순)';

  @override
  String get libraryFilterSortGenreDesc => '장르 (내림차순)';

  @override
  String get timeJustNow => '방금 전';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 분 전',
      one: '1 분 전',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 시간 전',
      one: '1 시간 전',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => 'SpotiFLAC에 오신 것을 환영합니다!';

  @override
  String get tutorialWelcomeDesc =>
      '좋아하는 음악을 무손실 음질로 다운로드하는 방법을 알아보겠습니다. 이 간단한 튜토리얼은 기본 사항을 보여줍니다';

  @override
  String get tutorialWelcomeTip1 =>
      'Spotify, Deezer 또는 지원되는 URL에서 음악을 다운로드할 수 있습니다';

  @override
  String get tutorialWelcomeTip2 =>
      '설치된 다운로드 확장 프로그램으로 FLAC 고음질 오디오를 다운로드할 수 있습니다';

  @override
  String get tutorialWelcomeTip3 => '메타데이터, 표지 이미지 및 가사를 자동으로 추가할 수 있습니다';

  @override
  String get tutorialSearchTitle => '음악 찾기';

  @override
  String get tutorialSearchDesc => '다운로드하고 싶은 음악을 찾는 두 가지 쉬운 방법이 있습니다';

  @override
  String get tutorialDownloadTitle => '음악 다운로드';

  @override
  String get tutorialDownloadDesc => '음악 다운로드는 간단하고 빠릅니다\\n작동 방식은 다음과 같습니다';

  @override
  String get tutorialLibraryTitle => '내 라이브러리';

  @override
  String get tutorialLibraryDesc => '다운로드된 모든 음악은 라이브러리 탭에 정리되어 있습니다';

  @override
  String get tutorialLibraryTip1 => '라이브러리 탭에서 다운로드 진행 상황과 다운로드 목록을 확인할 수 있습니다';

  @override
  String get tutorialLibraryTip2 => '아무 트랙을 탭하여 음악 플레이어로 재생할 수 있습니다';

  @override
  String get tutorialLibraryTip3 => '리스트 보기 또는 그리드 보기로 전환하여 더 나은 탐색을 할 수 있습니다';

  @override
  String get tutorialExtensionsTitle => '확장 프로그램';

  @override
  String get tutorialExtensionsDesc => '커뮤니티 확장 프로그램을 사용하여 앱의 기능을 확장하세요';

  @override
  String get tutorialExtensionsTip1 => '레포 탭을 탐색하여 유용한 확장 프로그램을 찾을 수 있습니다';

  @override
  String get tutorialExtensionsTip2 => '새 다운로드 제공자 또는 검색 출처를 추가할 수 있습니다';

  @override
  String get tutorialExtensionsTip3 => '가사, 향상된 메타데이터 및 더 많은 기능을 사용할 수 있습니다';

  @override
  String get tutorialSettingsTitle => '사용자 환경 맞춤 설정';

  @override
  String get tutorialSettingsDesc => '설정에서 앱을 원하는 대로 맞춤 설정하세요';

  @override
  String get tutorialSettingsTip1 => '다운로드 위치 및 폴더 구성 변경';

  @override
  String get tutorialSettingsTip2 => '기본 오디오 음질 및 형식 설정';

  @override
  String get tutorialSettingsTip3 => '앱 테마 및 디자인 사용자 정의';

  @override
  String get tutorialReadyMessage => '모든 준비가 완료되었습니다! 지금 바로 좋아하는 음악을 다운로드하세요';

  @override
  String get libraryForceFullScan => '전제 스캔 강제 실행';

  @override
  String get libraryForceFullScanSubtitle => '캐시를 무시하고 모든 파일을 다시 스캔합니다';

  @override
  String get cleanupOrphanedDownloads => '불필요한 다운로드 파일 정리';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      '더 이상 존재하지 않는 파일의 기록 항목을 제거합니다';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return '기록에서 $count 개의 불필요한 항목이 제거됨';
  }

  @override
  String get cleanupOrphanedDownloadsNone => '불필요한 항목이 없습니다';

  @override
  String get cacheTitle => '저장소 & 캐시';

  @override
  String get cacheSummaryTitle => '캐시 요약';

  @override
  String get cacheSummarySubtitle => '캐시를 지워도 다운로드된 음악 파일은 삭제되지 않습니다';

  @override
  String cacheEstimatedTotal(String size) {
    return '예상 캐시 사용량: $size';
  }

  @override
  String get cacheSectionStorage => '캐시된 데이터';

  @override
  String get cacheSectionMaintenance => '유지 관리';

  @override
  String get cacheAppDirectory => '앱 캐시 디렉토리';

  @override
  String get cacheAppDirectoryDesc => 'HTTP 응답, WebView 데이터 및 기타 임시 앱 데이터입니다';

  @override
  String get cacheTempDirectory => '임시 디렉토리';

  @override
  String get cacheTempDirectoryDesc => '다운로드 및 오디오 변환으로 만들어진 임시 파일';

  @override
  String get cacheCoverImage => '표지 이미지 캐시';

  @override
  String get cacheCoverImageDesc => '다운로드된 앨범 및 트랙 표지 이미지입니다. 볼 때 다시 다운로드됩니다';

  @override
  String get cacheLibraryCover => '라이브러리 표지 캐시';

  @override
  String get cacheLibraryCoverDesc =>
      '로컬 음악 파일에서 추출된 표지 이미지입니다. 다음 스캔 시 다시 추출됩니다';

  @override
  String get libraryPlaybackNormalization => '볼륨 정규화';

  @override
  String get libraryPlaybackNormalizationSubtitle =>
      '트랙에 ReplayGain 또는 R128 태그가 있는 경우에 이를 사용하여 트랙 간 음량을 일정하게 맞춥니다';

  @override
  String get cacheAudioAnalysis => '오디오 분석 캐시';

  @override
  String get cacheAudioAnalysisDesc =>
      '저장된 스펙트로그램과 분석 결과입니다. 다음에 실행할 경우에 다시 분석합니다';

  @override
  String get cacheExploreFeed => '탐색 피드 캐시';

  @override
  String get cacheExploreFeedDesc =>
      '탐색 탭 콘텐츠(최신 발매 음악, 인기 콘텐츠)는 다음 방문 시 새로 고쳐집니다';

  @override
  String get cacheTrackLookup => '트랙 조회 캐시';

  @override
  String get cacheTrackLookupDesc =>
      '조회된 Spotify/Deezer 트랙 ID입니다. 지우면 속도가 느려질 수 있습니다';

  @override
  String get cacheCleanupUnusedDesc =>
      '누락된 파일에 대한 불필요한 다운로드 기록 및 라이브러리 항목을 제거합니다';

  @override
  String get cacheNoData => '캐시된 데이터가 없음';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$count 개의 파일에 $size 사용';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count 개의 항목';
  }

  @override
  String cacheClearSuccess(String target) {
    return '지워짐: $target';
  }

  @override
  String get cacheClearConfirmTitle => '캐시를 지우시겠습니까?';

  @override
  String cacheClearConfirmMessage(String target) {
    return '\'\'$target\'\'의 캐시된 데이터를 지웁니다. 다운로드된 음악 파일은 삭제되지 않습니다';
  }

  @override
  String get cacheClearAllConfirmTitle => '모든 캐시를 지우시겠습니까?';

  @override
  String get cacheClearAllConfirmMessage =>
      '이 페이지의 모든 캐시 카테고리가 지워집니다. 다운로드된 음악 파일은 삭제되지 않습니다';

  @override
  String get cacheClearAll => '모든 캐시 지우기';

  @override
  String get cacheCleanupUnused => '사용되지 않는 데이터 정리';

  @override
  String get cacheCleanupUnusedSubtitle => '불필요한 다운로드 기록 및 누락된 라이브러리 항목을 제거합니다';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return '정리 완료: $downloadCount 개의 사용되지 않는 다운로드, $libraryCount 개의 누락된 라이브러리 항목';
  }

  @override
  String get cacheRefreshStats => '통계 새로고침';

  @override
  String get trackSaveCoverArt => '표지 이미지 저장';

  @override
  String get trackSaveLyrics => '가사 (.lrc) 저장';

  @override
  String get trackSaveLyricsProgress => '가사를 저장하는 중...';

  @override
  String get trackReEnrich => '보강';

  @override
  String get trackReEnrichOnlineSubtitle => '온라인에서 메타데이터를 검색하고 파일에 삽입';

  @override
  String get trackReEnrichFieldCover => '표지 이미지';

  @override
  String get trackReEnrichFieldLyrics => '가사';

  @override
  String get trackReEnrichFieldBasicTags => '앨범, 앨범 아티스트';

  @override
  String get trackReEnrichFieldTrackInfo => '트랙 & 디스크 번호';

  @override
  String get trackReEnrichFieldReleaseInfo => '데이터 & ISRC';

  @override
  String get trackReEnrichFieldExtra => '장르, 레이블, 저작권';

  @override
  String get trackReEnrichSelectAll => '모두 선택';

  @override
  String get trackEditMetadata => '메타데이터 편집';

  @override
  String trackCoverSaved(String fileName) {
    return '표지 이미지가 \'\'$fileName\'\'에 저장됨';
  }

  @override
  String get trackCoverNoSource => '사용할 수 있는 표지 출처가 없음';

  @override
  String trackLyricsSaved(String fileName) {
    return '가사가 \'\'$fileName\'\'에 저장됨';
  }

  @override
  String get trackReEnrichProgress => '메타데이터를 다시 구성하는 중...';

  @override
  String get trackReEnrichSearching => '온라인에서 메타데이터를 검색하는 중...';

  @override
  String get trackReEnrichSuccess => '메타데이터 재구성 성공';

  @override
  String get trackReEnrichFfmpegFailed => 'FFmpeg 메타데이터 삽입 실패';

  @override
  String get queueFlacAction => 'FLAC 다운로드 목록';

  @override
  String queueFlacConfirmMessage(int count) {
    return '선택한 트랙에 대한 온라인 일치 항목을 검색하고 FLAC을 다운로드 목록에 추가합니다\n\n기존 파일은 수정되거나 삭제되지 않습니다\n\n신뢰도가 높은 일치 항목만 자동으로 대기열에 추가됩니다\n\n$count 개가 선택되었습니다';
  }

  @override
  String get queueFlacNoReliableMatches =>
      '선택한 항목에 대한 신뢰할 수 있는 온라인 일치 항목을 찾을 수 없음';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return '다운로드 목록에 $addedCount 개의 트랙을 추가하고, $skippedCount 개의 트랙을 건너뜀';
  }

  @override
  String trackSaveFailed(String error) {
    return '실패: $error';
  }

  @override
  String get trackConvertFormat => '형식 변환';

  @override
  String get trackConvertTitle => '오디오 변환';

  @override
  String get trackConvertTargetFormat => '변경될 형식';

  @override
  String get trackConvertBitrate => '비트레이트';

  @override
  String get trackConvertKeepOriginal => '원본 파일 유지';

  @override
  String get trackConvertKeepOriginalDescription =>
      '변환된 파일을 별도의 라이브러리 항목으로 추가합니다';

  @override
  String get trackConvertConfirmTitle => '변환 확인';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return '$bitrate 비트레이트로 $sourceFormat에서 $targetFormat으로 변환하시겠습니까?\n\n변환 후 원본 파일이 삭제됩니다';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return '$sourceFormat에서 $targetFormat으로 변환하시겠습니까? (무손실 — 음질 손실 없음)\n\n변환 후에 원본 파일이 삭제됩니다';
  }

  @override
  String trackConvertConfirmKeepOriginal(
    String sourceFormat,
    String targetFormat,
  ) {
    return '$sourceFormat에서 $targetFormat으로 변환하시겠습니까?\n\n원본 파일은 유지되고 변환된 파일은 별도의 라이브러리 항목으로 추가됩니다';
  }

  @override
  String get trackConvertLosslessHint => '무손실 변환 — 음질 손실 없음';

  @override
  String get trackConvertConverting => '오디오를 변환하는 중...';

  @override
  String trackConvertSuccess(String format) {
    return '$format으로 변환 성공';
  }

  @override
  String get trackConvertFailed => '변환 실패';

  @override
  String get cueSplitTitle => 'CUE 시트 분할';

  @override
  String cueSplitAlbum(String album) {
    return '앨범: $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return '아티스트: $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count 개의 트랙';
  }

  @override
  String get cueSplitConfirmTitle => 'CUE 앨범 분할';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return '\'\'$album\'\'을 $count 개의 개별 FLAC 파일로 분할하시겠습니까?\n\n파일은 동일한 디렉토리에 저장됩니다';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'CUE 시트를 분할하는 중... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return '$count 개의 트랙 분할 성공';
  }

  @override
  String get cueSplitFailed => 'CUE 분할 실패';

  @override
  String get cueSplitNoAudioFile => '이 CUE 시트에 대한 오디오 파일을 찾을 수 없습니다';

  @override
  String get cueSplitButton => '트랙으로 분할';

  @override
  String get actionCreate => '만들기';

  @override
  String get collectionFoldersTitle => '내 폴더';

  @override
  String get collectionWishlist => '위시리스트';

  @override
  String get collectionLoved => '좋아요 표시한 음악';

  @override
  String get collectionFavoriteArtists => '좋아하는 아티스트';

  @override
  String get collectionPlaylist => '재생목록';

  @override
  String get collectionAddToPlaylist => '재생목록에 추가';

  @override
  String get collectionCreatePlaylist => '재생목록 만들기';

  @override
  String get collectionNoPlaylistsYet => '아직 재생목록이 없음';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 트랙',
      one: '1 개의 트랙',
    );
    return '$_temp0';
  }

  @override
  String collectionArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 명의 아티스트',
      one: '1 명의 아티스트',
    );
    return '$_temp0';
  }

  @override
  String collectionAddedToPlaylist(String playlistName) {
    return '\'\'$playlistName\'\'에 추가됨';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return '이미 \'\'$playlistName\'\'에 있음';
  }

  @override
  String get collectionPlaylistNameHint => '재생목록 이름';

  @override
  String get collectionPlaylistNameRequired => '재생목록 이름은 필수입니다';

  @override
  String get collectionRenamePlaylist => '재생목록 이름 변경';

  @override
  String get collectionDeletePlaylist => '재생목록 삭제';

  @override
  String get collectionPlaylistRenamed => '재생목록 이름 변경 완료';

  @override
  String get collectionWishlistEmptyTitle => '위시리스트가 비어 있음';

  @override
  String get collectionWishlistEmptySubtitle =>
      '나중에 다운로드할 트랙을 저장하려면 트랙에서 +를 탭하세요';

  @override
  String get collectionLovedEmptyTitle => '\'좋아요 표시한 음악\' 폴더가 비어 있음';

  @override
  String get collectionLovedEmptySubtitle => '트랙에 하트를 탭하여 \'좋아요\'를 유지하세요';

  @override
  String get collectionFavoriteArtistsEmptyTitle => '아직 좋아하는 아티스트가 없음';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      '아티스트 페이지에서 하트를 탭하여 여기에 추가하세요';

  @override
  String get collectionPlaylistEmptyTitle => '재생목록이 비어 있음';

  @override
  String get collectionPlaylistEmptySubtitle => '아무 트랙에서 +를 길게 탭하여 여기에 추가하세요';

  @override
  String get collectionRemoveFromPlaylist => '재생목록에서 제거';

  @override
  String get collectionRemoveFromFolder => '폴더에서 제거';

  @override
  String collectionAddedToLoved(String trackName) {
    return '\'\'$trackName\'\'이 \'좋아요 표시한 음악\'에 추가됨';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\'\'$trackName\'\'이 \'좋아요 표시한 음악\'에서 제거됨';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '\'\'$trackName\'\'가 위시리스트에 추가됨';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '\'\'$trackName\'\'가 위시리스트에서 제거됨';
  }

  @override
  String collectionAddedToFavoriteArtists(String artistName) {
    return '\'\'$artistName\'\'가 좋아하는 아티스트에 추가됨';
  }

  @override
  String collectionRemovedFromFavoriteArtists(String artistName) {
    return '\'\'$artistName\'\'가 좋아하는 아티스트에서 제거됨';
  }

  @override
  String get trackOptionAddToLoved => '좋아요 표시한 음악에 추가';

  @override
  String get trackOptionRemoveFromLoved => '좋아요 표시한 음악에서 제거';

  @override
  String get trackOptionAddToWishlist => '위시리스트에 추가';

  @override
  String get trackOptionRemoveFromWishlist => '위시리스트에서 제거';

  @override
  String get artistOptionAddToFavorites => '즐겨찾는 아티스트에 추가';

  @override
  String get artistOptionRemoveFromFavorites => '즐겨찾는 아티스트에서 제거';

  @override
  String get collectionPlaylistChangeCover => '표지 이미지 변경';

  @override
  String get collectionPlaylistRemoveCover => '표지 이미지 제거';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count $_temp0 공유';
  }

  @override
  String get selectionShareNoFiles => '공유할 수 있는 파일을 찾을 수 없음';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count $_temp0 변환';
  }

  @override
  String get selectionConvertNoConvertible => '선택된 변환할 수 있는 트랙이 없음';

  @override
  String get selectionBatchConvertConfirmTitle => '일괄 변환';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 $_temp0을 $bitrate 비트레이트로 $format으로 변환하시겠습니까?\n\n변환 후 원본 파일이 삭제됩니다';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 $_temp0을 $format으로 변환하시겠습니까? (무손실 — 음질 손실 없음)\n\n변환 후 원본 파일이 삭제됩니다';
  }

  @override
  String selectionBatchConvertConfirmKeepOriginal(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 $_temp0을 $format으로 변환하시겠습니까?\n\n원본 파일은 유지되고 변환된 파일은 별도의 라이브러리 항목으로 추가됩니다';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return '$total 개 중 $success 개를 $format로 변환 완료';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count 개 다운로드됨';
  }

  @override
  String get downloadUseAlbumArtistForFoldersAlbumSubtitle =>
      '앨범 아티스트 태그로 이름이 지정된 폴더';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      '트랙 아티스트 태그로 이름이 지정된 폴더';

  @override
  String get lyricsProvidersTitle => '가사 제공자 우선순위';

  @override
  String get lyricsProvidersDescription =>
      '가사 출처를 활성화, 비활성화 및 재정렬할 수 있습니다. 가사가 발견될 때까지 위에서 아래로 제공자를 시도합니다';

  @override
  String get lyricsProvidersInfoText =>
      '확장 프로그램 가사 제공자는 내부 가사 제공자보다 먼저 실행됩니다. 하나 이상의 제공자가 활성화되어 있어야 합니다';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return '활성화됨 ($count)';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return '비활성화됨 ($count)';
  }

  @override
  String get lyricsProvidersAtLeastOne => '최소 한 명의 제공자가 활성화된 상태로 유지되어야 합니다';

  @override
  String get lyricsProvidersSaved => '가사 제공자 우선순위가 저장됨';

  @override
  String get lyricsProvidersDiscardContent => '저장되지 않은 변경 사항이 손실됩니다';

  @override
  String get lyricsProviderLrclibDesc => '오픈 소스 동기화 가사 데이터베이스';

  @override
  String get lyricsProviderNeteaseDesc => 'NetEase Cloud Music (아시아 노래에 적합)';

  @override
  String get lyricsProviderMusixmatchDesc => '최대 규모의 가사 데이터베이스 (다국어 지원)';

  @override
  String get lyricsProviderAppleMusicDesc => '단어별 동기화 가사 (프록시 경유)';

  @override
  String get lyricsProviderQqMusicDesc => 'QQ Music (중국 노래에 적합, 프록시 경유)';

  @override
  String get lyricsProviderLyricsPlusDesc =>
      '단어별 노래방 가사 (Apple/Musixmatch/Spotify/QQ, 프록시 이용)';

  @override
  String get lyricsProviderExtensionDesc => '확장 프로그램 제공자';

  @override
  String get safMigrationTitle => '저장소 업데이트 필요';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC은 이제 다운로드에 Android 저장소 접근 프레임워크(SAF)를 사용합니다. 이로써 Android 10 이상에서 \'권한 거부\' 오류가 해결됩니다';

  @override
  String get safMigrationMessage2 => '새 저장소 시스템으로 전환하려면 다운로드 폴더를 다시 선택하세요';

  @override
  String get safMigrationSuccess => '다운로드 폴더가 SAF 모드로 업데이트됨';

  @override
  String get settingsDonate => '개발 후원';

  @override
  String get settingsDonateSubtitle => '개발자에게 커피 한 잔 사주세요';

  @override
  String get settingsBackup => '백업 & 복원';

  @override
  String get settingsBackupSubtitle => '라이브러리, 기록 및 설정을 새 기기로 옮겨보세요';

  @override
  String get backupTitle => '백업 & 복원';

  @override
  String get backupExportSectionTitle => '백업 생성';

  @override
  String get backupExportSectionDescription =>
      '설정, 다운로드 기록, 좋아요 표시한 음악, 위시리스트, 즐겨찾는 아티스트 및 재생목록을 하나의 파일로 저장하여 보관하거나 다른 휴대전화로 옮길 수 있습니다';

  @override
  String get backupExportButton => '백업 파일 생성';

  @override
  String get backupImportSectionTitle => '백업 복원';

  @override
  String get backupImportSectionDescription =>
      '데이터를 복원할 백업 파일을 선택하세요. 이 작업을 수행하면 현재 기기에 저장된 설정, 기록 및 라이브러리가 백업 파일의 내용으로 대체됩니다';

  @override
  String get backupImportButton => '백업 파일 선택';

  @override
  String get backupCreated => '백업 생성 완료';

  @override
  String get backupCreateFailed => '백업 생성 실패';

  @override
  String get backupRestoreConfirmTitle => '이 백업을 복원하시겠습니까?';

  @override
  String get backupRestoreConfirmMessage =>
      '현재 설정, 다운로드 기록, 좋아요 표시한 음악, 위시리스트 및 재생목록이 백업 파일의 내용으로 대체됩니다. 이 작업은 되돌릴 수 없습니다';

  @override
  String get backupRestoreConfirmButton => '복원';

  @override
  String get backupRestored => '백업 복원 성공';

  @override
  String get backupRestoreFailed => '백업 복원 실패';

  @override
  String get backupInvalidFile => '이 파일은 유효한 SpotiFLAC 백업이 아닙니다';

  @override
  String get backupRestoreRestartHint => '모든 변경 사항을 적용하려면 앱을 다시 시작하세요';

  @override
  String get backupContentsTitle => '백업 콘텐츠';

  @override
  String get backupContentsSettings => '앱 설정';

  @override
  String backupContentsHistory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목',
      one: '항목',
    );
    return '$count 개의 기록 $_temp0';
  }

  @override
  String backupContentsLiked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '음악',
      one: '음악',
    );
    return '$count 개의 좋아요 표시한 $_temp0';
  }

  @override
  String backupContentsWishlist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 위시리스트 $_temp0';
  }

  @override
  String backupContentsPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 재생목록',
      one: '1 개의 재생목록',
    );
    return '$_temp0';
  }

  @override
  String backupContentsArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 명의 좋아하는 아티스트',
      one: '1 명의 좋아하는 아티스트',
    );
    return '$_temp0';
  }

  @override
  String backupContentsExtensions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 확장 프로그램',
      one: '1 개의 확장 프로그램',
    );
    return '$_temp0';
  }

  @override
  String get backupIncludeSecrets => '확장 프로그램 자격 증명 포함';

  @override
  String get backupIncludeSecretsDescription =>
      '확장 프로그램의 토큰과 API 키가 백업 파일에 함께 저장됩니다. 백업 파일은 안전하게 보관하세요. 비활성화하면 복원 후 다시 입력해야 합니다';

  @override
  String backupExtensionsRestoreFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '확장 프로그램',
      one: '확장 프로그램',
    );
    return '$count 개의 $_temp0을 다시 설치할 수 없습니다. 레포에서 수동으로 설치하세요';
  }

  @override
  String get tooltipLoveAll => '모두 좋아요 표시';

  @override
  String get tooltipAddToPlaylist => '재생목록에 추가';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return '\'좋아요 표시한 음악\'에서 $count 개의 트랙이 제거됨';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return '\'좋아요 표시한 음악\'에 $count 개의 트랙이 추가됨';
  }

  @override
  String get dialogDownloadAllTitle => '모두 다운로드';

  @override
  String dialogDownloadAllMessage(int count) {
    return '$count 개의 트랙을 다운로드하시겠습니까?';
  }

  @override
  String get homeSkipAlreadyDownloaded => '이미 다운로드된 노래 건너뛰기';

  @override
  String get homeGoToAlbum => '앨범으로 이동';

  @override
  String get homeAlbumInfoUnavailable => '앨범 정보를 사용할 수 없음';

  @override
  String get snackbarLoadingCueSheet => 'CUE 시트를 불러오는 중...';

  @override
  String get snackbarMetadataSaved => '메타데이터 저장 성공';

  @override
  String get snackbarFailedToEmbedLyrics => '가사 삽입 실패';

  @override
  String get snackbarFailedToWriteStorage => '저장소 다시 쓰기 실패';

  @override
  String snackbarError(String error) {
    return '오류: $error';
  }

  @override
  String get snackbarNoActionDefined => '이 버튼에 대해 정의된 작업이 없음';

  @override
  String get noTracksFoundForAlbum => '이 앨범에서 트랙을 찾을 수 없음';

  @override
  String get downloadLocationSubtitle => '다운로드된 트랙을 저장할 위치를 선택하세요';

  @override
  String get storageModeAppFolder => '앱 폴더 (추천)';

  @override
  String get storageModeAppFolderSubtitle => '기본적으로 Music/SpotiFLAC에 저장';

  @override
  String get storageModeSaf => '사용자 정의 폴더 (SAF)';

  @override
  String get storageModeSafSubtitle => 'SD 카드를 포함한 아무 폴더나 선택하세요';

  @override
  String get downloadFolderAccessLostTitle => '다운로드 폴더 접근 손실';

  @override
  String get downloadFolderAccessLostSubtitle => '폴더를 다시 선택할 때까지 다운로드할 수 없습니다';

  @override
  String get downloadFolderReselect => '폴더 다시 선택';

  @override
  String get downloadErrorSafPermissionLost =>
      'SAF 권한이 잘못되었거나 취소되었습니다. 설정에서 다운로드 위치를 다시 설정하세요';

  @override
  String get downloadErrorFolderAccessLost =>
      '다운로드 폴더 접근 권한이 없습니다. 설정에서 다운로드 폴더를 다시 설정하세요';

  @override
  String downloadFilenameDescription(
    Object album,
    Object artist,
    Object date,
    Object disc,
    Object title,
    Object track,
    Object year,
  ) {
    return '\'\'$artist\'\', \'\'$title\'\', \'\'$album\'\', \'\'$track\'\', \'\'$year\'\', \'\'$date\'\', \'\'$disc\'\'를 자리표시자로 사용하세요';
  }

  @override
  String get downloadFilenameInsertTag => '태그를 삽입하려면 탭하세요:';

  @override
  String get downloadSeparateSinglesEnabled => '싱글과 EP를 별도의 폴더에 저장합니다';

  @override
  String get downloadSeparateSinglesDisabled => '싱글과 앨범을 같은 폴더에 저장합니다';

  @override
  String get downloadArtistNameFilters => '아티스트 이름 필터';

  @override
  String get downloadCreatePlaylistSourceFolder => '재생목록 소스 폴더';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      '각 재생 목록에 대한 하위 폴더를 만듭니다';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      '모든 트랙을 다운로드 폴더에 직접 저장합니다';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant => '폴더 구성 설정에 의해 처리됨';

  @override
  String get downloadSongLinkRegion => 'SongLink 지역';

  @override
  String get downloadNetworkCompatibilityMode => '네트워크 호환 모드';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      '이전 네트워크에 대한 레거시 TLS 설정 사용';

  @override
  String get downloadNetworkCompatibilityModeDisabled => '표준 ​​네트워크 설정 사용';

  @override
  String get downloadAllowLocalNetwork => '로컬 네트워크 접근 허용';

  @override
  String get downloadAllowLocalNetworkEnabled =>
      '로컬/사설 주소에 대한 요청이 허용됨 (로컬 프록시 또는 사용자 지정 DNS용)';

  @override
  String get downloadAllowLocalNetworkDisabled => '보안을 위해 로컬/사설 주소가 차단됨';

  @override
  String get downloadSelectServiceToEnable =>
      '이 옵션을 활성화하려면 음질 옵션이 있는 공급자를 선택하세요';

  @override
  String get downloadEmbedLyricsDisabled => '먼저 메타데이터 삽입을 활성화하세요';

  @override
  String get downloadNeteaseIncludeTranslation => 'Netease: 번역 포함';

  @override
  String get downloadNeteaseIncludeTranslationEnabled => '중국어 번역 포함';

  @override
  String get downloadNeteaseIncludeTranslationDisabled => '원본 가사만';

  @override
  String get downloadNeteaseIncludeRomanization => 'Netease: 로마자 표기 포함';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled => '로마자 표기 포함';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled => '로마자 표기 없음';

  @override
  String get downloadAppleQqMultiPerson => 'Apple / QQ: 다인용 가사';

  @override
  String get downloadAppleQqMultiPersonEnabled => '듀엣 및 그룹 트랙이 포함된 스피커 레이블';

  @override
  String get downloadAppleQqMultiPersonDisabled => '스피커 레이블이 없는 표준 가사';

  @override
  String get downloadAppleElrcWordSync => 'Apple Music eLRC 단어 동기화';

  @override
  String get downloadAppleElrcWordSyncEnabled => '단어별 타임스탬프 원본 유지';

  @override
  String get downloadAppleElrcWordSyncDisabled => '더 안전한 Apple Music 가사 (줄 단위)';

  @override
  String get downloadMusixmatchLanguage => 'Musixmatch 언어';

  @override
  String get downloadMusixmatchLanguageAuto => '자동 (원본 언어)';

  @override
  String get downloadFilterContributing => '참여 아티스트 필터';

  @override
  String get downloadFilterContributingEnabled => '앨범 아티스트 폴더 이름에서 제거된 참여 아티스트';

  @override
  String get downloadFilterContributingDisabled => '전체 앨범 아티스트 문자열 사용';

  @override
  String get downloadProvidersNoneEnabled => '활성화된 제공자가 없음';

  @override
  String get downloadMusixmatchLanguageCode => '언어 코드';

  @override
  String get downloadMusixmatchLanguageHint => '예시: en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Musixmatch에서 번역된 가사를 요청하려면 BCP-47 언어 코드를 입력하세요 (예시: ko, en, ja)';

  @override
  String get downloadMusixmatchAuto => '자동';

  @override
  String get downloadNetworkAnySubtitle => 'Wi-Fi 또는 모바일 네트워크 사용';

  @override
  String get downloadNetworkWifiOnlySubtitle => '모바일 네트워크 사용 시 다운로드 일시 중지';

  @override
  String get downloadSongLinkRegionDesc =>
      'SongLink를 통해 트랙 링크를 해결할 경우에 사용되는 지역입니다. 스트리밍 서비스를 이용할 수 있는 국가를 선택하세요';

  @override
  String get snackbarUnsupportedAudioFormat => '지원되지 않는 오디오 형식';

  @override
  String get cacheRefresh => '새로고침';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: '재생록록',
      one: '재생목록',
    );
    String _temp1 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$playlistCount 개의 $_temp0에서 $trackCount 개의 $_temp1을 다운로드하시겠습니까?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '재생목록',
      one: '재생목록',
    );
    return '$count 개의 $_temp0 다운로드';
  }

  @override
  String get bulkDownloadSelectPlaylists => '다운로드할 재생목록 선택';

  @override
  String get snackbarSelectedPlaylistsEmpty => '선택한 재생목록에 트랙이 없습니다';

  @override
  String playlistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 재생목록',
      one: '1 개의 재생목록',
    );
    return '$_temp0';
  }

  @override
  String get editMetadataAutoFill => '온라인에서 자동 채우기';

  @override
  String get editMetadataAutoFillDesc => '온라인 메타데이터에서 자동으로 채워질 필드를 선택하세요';

  @override
  String get editMetadataAutoFillSource => 'Metadata source';

  @override
  String get editMetadataAutoFillSourceAutomatic =>
      'Automatic (provider priority)';

  @override
  String get editMetadataAutoFillFind => 'Find metadata';

  @override
  String editMetadataAutoFillPreview(String source) {
    return 'Data from $source';
  }

  @override
  String get editMetadataAutoFillCoverAvailable => 'Cover artwork available';

  @override
  String get editMetadataAutoFillApply => 'Apply selected data';

  @override
  String editMetadataAutoFillDoneFromSource(int count, String source) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fields',
      one: 'field',
    );
    return 'Filled $count $_temp0 from $source';
  }

  @override
  String get editMetadataAutoFillFetch => '가져오기 & 채우기';

  @override
  String get editMetadataAutoFillSearching => '온라인에서 검색하는 중...';

  @override
  String get editMetadataAutoFillNoResults => '온라인에서 일치하는 메타데이터를 찾을 수 없음';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '필드',
      one: '필드',
    );
    return '온라인 메타데이터로부터 $count 개의 $_temp0가 채워짐';
  }

  @override
  String get editMetadataAutoFillNoneSelected => '자동 채우기를 위해 하나 이상의 필드를 선택하세요';

  @override
  String get editMetadataFieldTitle => '제목';

  @override
  String get editMetadataFieldArtist => '아티스트';

  @override
  String get editMetadataFieldAlbum => '앨범';

  @override
  String get editMetadataFieldAlbumArtist => '앨범 아티스트';

  @override
  String get editMetadataFieldDate => '날짜';

  @override
  String get editMetadataFieldTrackNum => '트랙 #';

  @override
  String get editMetadataFieldDiscNum => '디스크 #';

  @override
  String get editMetadataFieldGenre => '장르';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => '레이블';

  @override
  String get editMetadataFieldCopyright => '저작권';

  @override
  String get editMetadataFieldCover => '표지 이미지';

  @override
  String get editMetadataSelectAll => '모두';

  @override
  String get editMetadataSelectEmpty => '비어 있음만';

  @override
  String queueDownloadingCount(int count) {
    return '다운로드하는 중 ($count)';
  }

  @override
  String get queueFilteringIndicator => '필터링하는 중...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 트랙',
      one: '1 개의 트랙',
    );
    return '$_temp0';
  }

  @override
  String queueAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 앨범',
      one: '1 개의 앨범',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyAlbums => '앨범 다운로드가 없음';

  @override
  String get queueEmptyAlbumsSubtitle => '앨범에서 여러 트랙을 다운로드하면 여기에 표시됩니다';

  @override
  String get queueEmptySingles => '싱글 다운로드가 없음';

  @override
  String get queueEmptySinglesSubtitle => '싱글 트랙 다운로드는 여기에 표시됩니다';

  @override
  String queuePlaylistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyPlaylistsSubtitle =>
      'Create a playlist to organize your tracks';

  @override
  String get libraryDefaultView => 'Default view';

  @override
  String get libraryDefaultViewLastUsed => 'Last used';

  @override
  String get queueEmptyHistory => '다운로드 기록이 없음';

  @override
  String get queueEmptyHistorySubtitle => '다운로드된 트랙이 여기에 표시됩니다';

  @override
  String get selectionAllPlaylistsSelected => '모든 재생목록이 선택됨';

  @override
  String get selectionTapPlaylistsToSelect => '선택할 재생목록을 탭하세요';

  @override
  String get selectionSelectPlaylistsToDelete => '삭제할 재생 목록 선택';

  @override
  String get audioAnalysisTitle => '오디오 음질 분석';

  @override
  String get audioAnalysisDescription => '스펙트럼 분석으로 무손실 음질을 확인합니다';

  @override
  String get audioAnalysisAnalyzing => '오디오를 분석하는 중...';

  @override
  String get audioAnalysisSampleRate => '샘플링 레이트';

  @override
  String get audioAnalysisCodec => '코덱';

  @override
  String get audioAnalysisContainer => '컨테이너';

  @override
  String get audioAnalysisDecodedFormat => '디코딩 형식';

  @override
  String get audioAnalysisBitDepth => '비트 심도';

  @override
  String get audioAnalysisChannels => '채널';

  @override
  String get audioAnalysisDuration => '재생시간';

  @override
  String get audioAnalysisNyquist => '나이퀴스트';

  @override
  String get audioAnalysisFileSize => '크기';

  @override
  String get audioAnalysisDynamicRange => '다이나믹 레인지';

  @override
  String get audioAnalysisPeak => '최대 피크';

  @override
  String get audioAnalysisRms => 'RMS';

  @override
  String get audioAnalysisLufs => 'LUFS';

  @override
  String get audioAnalysisTruePeak => '트루 피크';

  @override
  String get audioAnalysisClipping => '클리핑';

  @override
  String get audioAnalysisNoClipping => '클리핑 없음';

  @override
  String get audioAnalysisSpectralCutoff => '주파수 컷오프';

  @override
  String get audioAnalysisCutoffNotDetected => 'Not detected';

  @override
  String get audioAnalysisChannelStats => '채널별 통계';

  @override
  String get audioAnalysisSamples => '샘플';

  @override
  String get audioAnalysisRescan => '다시 분석';

  @override
  String get audioAnalysisRescanning => '오디오를 다시 분석하는 중...';

  @override
  String get extensionsHomeFeedProvider => '홈 피드 제공자';

  @override
  String get extensionsHomeFeedDescription =>
      '메인 화면에 홈 피드를 제공하는 확장 프로그램을 선택하세요';

  @override
  String get extensionsHomeFeedAuto => '자동';

  @override
  String get extensionsHomeFeedAutoSubtitle => '사용 가능한 최적의 항목을 자동으로 선택합니다';

  @override
  String get extensionsHomeFeedOff => '끄기';

  @override
  String get extensionsHomeFeedOffSubtitle => '메인 화면에 홈 피드를 표시하지 않습니다';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return '$extensionName 홈 피드 사용';
  }

  @override
  String get extensionsNoHomeFeedExtensions => '홈 피드가 있는 확장 프로그램가 없음';

  @override
  String get cancelDownloadTitle => '다운로드를 취소하시겠습니까?';

  @override
  String cancelDownloadContent(String trackName) {
    return '\'\'$trackName\'\'에 대한 활성 다운로드를 취소합니다';
  }

  @override
  String get cancelDownloadKeep => '유지';

  @override
  String get queueCancelledTitle => 'Download cancelled';

  @override
  String get queueCancelledMessage =>
      'This download was cancelled. Retry it or remove it from the queue.';

  @override
  String get metadataSaveFailedFfmpeg => 'FFmpeg를 통해 메타데이터 저장 실패';

  @override
  String get metadataSaveFailedStorage => '저장소에 메타데이터 다시 쓰기 실패';

  @override
  String snackbarFolderPickerFailed(String error) {
    return '폴더 선택기 열기 실패: $error';
  }

  @override
  String notifDownloadingTrack(String trackName) {
    return '\'\'$trackName\'\'를 다운로드하는 중';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return '\'\'$trackName\'\'를 마무리하는 중';
  }

  @override
  String get notifEmbeddingMetadata => '메타데이터를 삽입하는 중...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return '이미 라이브러리에 있음 ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => '이미 라이브러리에 있음';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return '다운로드 완료 ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => '다운로드 완료';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return '다운로드 완료 ($completed 개 완료, $failed 개 실패)';
  }

  @override
  String get notifVerificationRequiredTitle => '인증 필요';

  @override
  String get notifVerificationRequiredBody => '앱을 실행하여 인증을 완료하고 다운로드를 재개하세요';

  @override
  String get notifAllDownloadsComplete => '모든 다운로드 완료';

  @override
  String notifTracksDownloadedSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 트랙 다운로드 성공',
      one: '1 개의 트랙 다운로드 성공',
    );
    return '$_temp0';
  }

  @override
  String notifDownloadsFinishedBody(int completed, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      completed,
      locale: localeName,
      other: '$completed 개의 트랙 다운로드 성공',
      one: '1 개의 트랙 다운로드 성공',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed 개 실패',
      one: '1 개 실패',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get notifDownloadsCanceledTitle => '다운로드 취소됨';

  @override
  String notifDownloadsCanceledBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 개의 다운로드가 사용자에 의해 취소됨',
      one: '1 개의 다운로드가 사용자에 의해 취소됨',
    );
    return '$_temp0';
  }

  @override
  String get notifScanningLibrary => '로컬 라이브러리를 스캔하는 중';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total 개의 파일 • $percentage%';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned 게의 파일이 스캔됨 • $percentage%';
  }

  @override
  String get notifLibraryScanComplete => '라이브러리 스캔 완료';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count 개의 트랙이 색인됨';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count 개가 제외됨';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count 개의 오류';
  }

  @override
  String get notifLibraryScanFailed => '라이브러리 스캔 실패';

  @override
  String get notifLibraryScanCancelled => '라이브러리 스캔이 취소됨';

  @override
  String get notifLibraryScanStopped => '스캔이 완료되기 전에 중단되었습니다';

  @override
  String notifDownloadingUpdate(String version) {
    return 'SpotiFLAC Mobile v$version을 다운로드하는 중';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total MB • $percentage%';
  }

  @override
  String get notifUpdateReady => '업데이트 준비 완료';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC Mobile v$version 다운로드 완료. 설치하려면 탭하세요';
  }

  @override
  String get notifUpdateFailed => '업데이트 실패';

  @override
  String get notifUpdateFailedBody => '업데이트를 다운로드할 수 없습니다. 나중에 다시 시도하세요';

  @override
  String get searchTracks => '트랙';

  @override
  String get homeSearchHintDefault => '지원되는 URL을 붙여넣거나 검색...';

  @override
  String homeSearchHintProvider(String providerName) {
    return '$providerName으로 검색...';
  }

  @override
  String get homeImportCsvTooltip => 'CSV 가져오기';

  @override
  String get homeChangeSearchProviderTooltip => '검색 제공자 변경';

  @override
  String get actionPaste => '붙여넣기';

  @override
  String get tutorialSearchHint => '붙여넣기 또는 검색하기...';

  @override
  String get tutorialDownloadCompletedSemantics => '다운로드 완료';

  @override
  String get tutorialDownloadInProgressSemantics => '다운로드를 진행하는 중';

  @override
  String get tutorialStartDownloadSemantics => '다운로드 시작';

  @override
  String get optionsEmbedMetadata => '메타데이터 삽입';

  @override
  String get optionsEmbedMetadataSubtitleOn => '메타데이터, 표지 이미지 및 내장 가사를 파일에 기록';

  @override
  String get optionsEmbedMetadataSubtitleOff => '비활성화됨 (고급): 모든 메타데이터 삽입 건너뛰기';

  @override
  String get trackCoverNoEmbeddedArt => '내장된 표지 이미지가 없음';

  @override
  String get trackCoverReplace => '표지 교체';

  @override
  String get trackCoverPick => '표지 선택';

  @override
  String get trackCoverClearSelected => '선택된 표지 지우기';

  @override
  String get trackCoverCurrent => '현재 표지';

  @override
  String get trackCoverSelected => '선택된 표지';

  @override
  String get trackCoverReplaceNotice => '저장을 탭하면 선택한 표지가 현재 내장된 표지를 대체합니다';

  @override
  String get trackCoverResolution => 'Cover resolution';

  @override
  String get trackCoverResolutionHint =>
      'Sets the longest edge when saved. Enlarging does not add image detail.';

  @override
  String get trackCoverResizeFailed =>
      'The cover image could not be resized. Please try another size or image.';

  @override
  String get actionStop => '중지';

  @override
  String get queueFinalizingDownload => '다운로드를 마무리하는 중';

  @override
  String get queueDownloadNext => 'Download next';

  @override
  String get queueMoveUp => 'Move up';

  @override
  String get queueMoveDown => 'Move down';

  @override
  String get editMetadataMusicBrainzButton => 'Fetch from MusicBrainz';

  @override
  String get editMetadataMusicBrainzFilled => 'Updated from MusicBrainz';

  @override
  String get editMetadataMusicBrainzNothing => 'Nothing found on MusicBrainz';

  @override
  String get editMetadataMusicBrainzNeedsIsrc => 'Requires an ISRC tag';

  @override
  String get nowPlayingRepeatOff => 'Repeat off';

  @override
  String get nowPlayingRepeatAll => 'Repeat all';

  @override
  String get nowPlayingRepeatOne => 'Repeat one';

  @override
  String queueNetworkFailedOffline(int count) {
    return '$count downloads failed while offline';
  }

  @override
  String get queueDownloadedFileMissing => '다운로드된 파일이 없음';

  @override
  String get queueDownloadCompleted => '다운로드 완료';

  @override
  String get queueRateLimitTitle => '서비스 사용 제한됨';

  @override
  String get queueRateLimitMessage =>
      '이 트랙은 아직 사용 가능할 수 있습니다. 몇 분 기다렸다가 병렬 다운로드를 줄인 후에 다시 시도하세요';

  @override
  String appearanceSelectAccentColor(String hex) {
    return '강조 색상 $hex 선택';
  }

  @override
  String get logAutoScrollOn => '자동 스크롤: ON';

  @override
  String get logAutoScrollOff => '자동 스크롤: OFF';

  @override
  String get logCopyLogs => '로그 복사';

  @override
  String get logClearSearch => '로그 지우기';

  @override
  String get logIssueIspBlockingLabel => 'ISP 차단 감지됨';

  @override
  String get logIssueIspBlockingDescription => 'ISP에서 다운로드 서비스 접속을 차단했을 수 있습니다';

  @override
  String get logIssueIspBlockingSuggestion =>
      'VPN을 사용하거나 DNS를 1.1.1.1 또는 8.8.8.8로 변경해 보세요';

  @override
  String get logIssueRateLimitedLabel => '사용 제한';

  @override
  String get logIssueRateLimitedDescription => '서비스에 대한 요청이 너무 많습니다';

  @override
  String get logIssueRateLimitedSuggestion => '몇 분 기다린 후에 다시 시도하세요';

  @override
  String get logIssueNetworkErrorLabel => '네트워크 오류';

  @override
  String get logIssueNetworkErrorDescription => '연결 문제가 감지됨';

  @override
  String get logIssueNetworkErrorSuggestion => '인터넷 연결 상태를 확인하세요';

  @override
  String get logIssueTrackNotFoundLabel => '트랙을 찾을 수 없음';

  @override
  String get logIssueTrackNotFoundDescription => '일부 트랙은 다운로드 서비스에서 찾을 수 없습니다';

  @override
  String get logIssueTrackNotFoundSuggestion => '트랙이 무손실 음질로 제공되지 않을 수 있습니다';

  @override
  String get clickableLookingUpArtist => '아티스트를 검색하는 중...';

  @override
  String clickableInformationUnavailable(String type) {
    return '$type 정보를 사용할 수 없음';
  }

  @override
  String get extensionDetailsTags => '태그';

  @override
  String get extensionDetailsInformation => '정보';

  @override
  String get extensionUtilityFunctions => '유틸리티 함수';

  @override
  String get actionDismiss => '닫기';

  @override
  String get setupChangeFolderTooltip => '폴더 변경';

  @override
  String a11yOpenTrackByArtist(String trackName, String artistName) {
    return '\'\'$artistName\'\'의 트랙 \'\'$trackName\'\' 열기';
  }

  @override
  String a11yOpenItem(String itemType, String name) {
    return '$itemType $name 열기';
  }

  @override
  String a11yOpenItemCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목',
      one: '항목',
    );
    return '$title, $count 개의 $_temp0 열기';
  }

  @override
  String a11yOpenAlbumByArtistTrackCount(
    String albumName,
    String artistName,
    int trackCount,
  ) {
    return '\'\'$artistName\'\'의 앨범 \'\'$albumName\'\' 열기 ($trackCount 번째 곡)';
  }

  @override
  String a11yTrackByArtist(String trackName, String artistName) {
    return '\'\'$artistName\'\'의 \'\'$trackName\'\'';
  }

  @override
  String a11ySelectAlbum(String albumName) {
    return '앨범 \'\'$albumName\'\' 선택';
  }

  @override
  String a11yOpenAlbum(String albumName) {
    return '앨범 \'\'$albumName\'\' 열기';
  }

  @override
  String get settingsFiles => '파일 & 폴더';

  @override
  String get settingsFilesSubtitle => '다운로드 위치, 파일 이름, 폴더 구조';

  @override
  String get settingsMetadata => '메타데이터';

  @override
  String get settingsMetadataSubtitle => '표지 이미지, 태그, 리플레이게인, 제공자';

  @override
  String get settingsLyrics => '가사';

  @override
  String get settingsLyricsSubtitle => '삽입, 모드, 제공자, 언어 옵션';

  @override
  String get settingsApp => '앱';

  @override
  String get settingsAppSubtitle => '업데이트, 데이터, 확장프로그램 레포, 디버그';

  @override
  String get sectionMetadataProviders => '제공자';

  @override
  String get sectionDuplicates => '중복';

  @override
  String get sectionLyricsProviderOptions => '제공자 옵션';

  @override
  String get metadataProvidersTitle => '메타데이터 제공자 우선순위';

  @override
  String get metadataProvidersSubtitle => '드래그하여 검색 및 메타데이터 출처 순서를 설정하세요';

  @override
  String get downloadDeduplication => '중복 다운로드 건너뛰기';

  @override
  String get downloadDeduplicationEnabled => '이미 다운로드된 트랙은 건너뜁니다';

  @override
  String get downloadDeduplicationWithQualityVariants => '선택된 음질의 기존 파일은 건너뜁니다';

  @override
  String get downloadDeduplicationDisabled => '기록과 관계없이 모든 트랙이 다운로드됩니다';

  @override
  String get downloadQualityVariants => '다양한 음질 버전 허용';

  @override
  String get downloadQualityVariantsDescription =>
      '각 음질 버전을 유지하고, 같은 이름이 이미 사용 중일 때만 측정된 음질을 파일 이름에 추가합니다';

  @override
  String get trackOptionDownloadQualityVariant => '다른 음질 다운로드';

  @override
  String get downloadFallbackExtensions => '대체 확장 프로그램';

  @override
  String get downloadFallbackExtensionsSubtitle =>
      '대체 확장 프로그램으로 사용할 확장 프로그램을 선택하세요';

  @override
  String get editMetadataFieldDateHint => 'YYYY-MM-DD 또는 YYYY';

  @override
  String get editMetadataFieldTrackTotal => '전체 트랙 수';

  @override
  String get editMetadataFieldDiscTotal => '전체 디스크 수';

  @override
  String get editMetadataFieldComposer => '작곡가';

  @override
  String get editMetadataFieldComment => '주석';

  @override
  String get editMetadataAdvanced => '고급';

  @override
  String get libraryFilterMetadataMissingTrackNumber => '트랙 번호 누락';

  @override
  String get libraryFilterMetadataMissingDiscNumber => '디스크 번호 누락';

  @override
  String get libraryFilterMetadataMissingArtist => '아티스트 누락';

  @override
  String get libraryFilterMetadataIncorrectIsrcFormat => 'ISRC 형식이 잘못됨';

  @override
  String get libraryFilterMetadataMissingIsrc => 'Missing ISRC';

  @override
  String get libraryFilterMetadataMissingLabel => '레이블 누락';

  @override
  String collectionDeletePlaylistsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '재생목록',
      one: '재생목록',
    );
    return '$count 개의 $_temp0을 삭제하시겠습니까?';
  }

  @override
  String collectionPlaylistsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '재생목록',
      one: '재생목록',
    );
    return '$count 개의 $_temp0이 삭제됨';
  }

  @override
  String collectionAddedTracksToPlaylist(int count, String playlistName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '\'\'$playlistName\'\'에 $count 개의 $_temp0이 추가됨';
  }

  @override
  String collectionAddedTracksToPlaylistWithExisting(
    int count,
    String playlistName,
    int alreadyCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '\'\'$playlistName\'\'에 $count 개의 $_temp0이 추가됨 ($alreadyCount 개의 트랙은 이미 재생목록에 있음)';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목',
      one: '항목',
    );
    return '$count 개의 $_temp0';
  }

  @override
  String trackReEnrichSuccessWithFailures(
    int successCount,
    int total,
    int failedCount,
  ) {
    return '메타데이터 재구성 성공 ($successCount/$total) - 실패: $failedCount';
  }

  @override
  String selectionDeleteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count $_temp0 삭제';
  }

  @override
  String queueDownloadSpeedStatus(String speed) {
    return '다운로드하는 중 - $speed MB/s';
  }

  @override
  String get queueDownloadStarting => '시작하는 중...';

  @override
  String get queueCheckingDownloadSession => '다운로드 세션을 확인하는 중...';

  @override
  String get queueResolvingDownloadMetadata => '트랙 메타데이터를 확인하는 중...';

  @override
  String get queueResolvingDownloadStream => '오디오 스트림을 준비하는 중...';

  @override
  String get queueWaitingForVerification => '확인을 기다리는 중...';

  @override
  String get queueResumingAfterVerification => '확인 후 재개하는 중...';

  @override
  String get a11ySelectTrack => '트랙 선택';

  @override
  String get a11yDeselectTrack => '트랙 선택 해제';

  @override
  String a11yPlayTrackByArtist(String trackName, String artistName) {
    return '\'\'$artistName\'\'의 \'\'$trackName\'\' 재생';
  }

  @override
  String storeExtensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '확장 프로그램',
      one: '확장 프로그램',
    );
    return '$count 개의 $_temp0';
  }

  @override
  String storeRequiresVersion(String version) {
    return 'v$version 이상 필요';
  }

  @override
  String get actionGo => '이동';

  @override
  String get logIssueSummary => '문제 요약';

  @override
  String logTotalErrors(int count) {
    return '총 오류 수: $count';
  }

  @override
  String logAffectedDomains(String domains) {
    return '영향받은 도메인: $domains';
  }

  @override
  String get libraryScanCancelled => '스캔이 취소됨';

  @override
  String get libraryScanCancelledSubtitle => '준비가 되면 스캔을 다시 시도할 수 있습니다';

  @override
  String libraryDownloadsHistoryExcluded(int count) {
    return '다운로드 기록에서 $count 개 (목록에서 제외됨)';
  }

  @override
  String get downloadNativeWorker => '기본 다운로드 워커';

  @override
  String get downloadNativeWorkerSubtitle =>
      '확장 프로그램 다운로드를 위한 Android 백그라운드 서비스';

  @override
  String get extensionServiceStatus => '서비스 상태';

  @override
  String get extensionServiceHealth => '서비스 상태';

  @override
  String extensionHealthChecksConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '검사',
      one: '검사',
    );
    return '$count 개의 $_temp0가 설정됨';
  }

  @override
  String get extensionOauthConnectHint => 'Spotify에 연결을 탭하여 이 필드를 채우세요';

  @override
  String extensionLastChecked(String time) {
    return '마지막 확인 시간: $time';
  }

  @override
  String get extensionRefreshStatus => '상태 새로고침';

  @override
  String get extensionCustomUrlHandling => '사용자 정의 URL 처리';

  @override
  String get extensionCustomUrlHandlingSubtitle =>
      '이 확장 프로그램은 다음 사이트의 링크를 처리할 수 있습니다';

  @override
  String get extensionCustomUrlHandlingShareHint =>
      '이 사이트의 링크를 SpotiFLAC Mobile로 공유하면 이 확장 프로그램이 처리합니다';

  @override
  String extensionSettingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '설정',
      one: '설정',
    );
    return '$count 개의 $_temp0';
  }

  @override
  String get extensionHealthOnline => '온라인';

  @override
  String get extensionHealthDegraded => '저하됨';

  @override
  String get extensionHealthOffline => '오프라인';

  @override
  String get extensionHealthNotConfigured => '설정되지 않음';

  @override
  String get extensionHealthUnknown => '알 수 없음';

  @override
  String get extensionHealthRequired => '필수';

  @override
  String get extensionSettingNotSet => '설정되지 않음';

  @override
  String get extensionActionFailed => '작업 실패';

  @override
  String get extensionEnterValue => '값을 입력하세요';

  @override
  String get extensionHealthServiceOnline => '서비스 온라인';

  @override
  String get extensionHealthServiceDegraded => '서비스 저하됨';

  @override
  String get extensionHealthServiceOffline => '서비스 오프라인';

  @override
  String get extensionHealthServiceUnknown => '서비스 상태 알 수 없음';

  @override
  String get audioAnalysisStereo => '스테레오';

  @override
  String get audioAnalysisMono => '모노';

  @override
  String trackOpenInService(String serviceName) {
    return '$serviceName에서 열기';
  }

  @override
  String get trackLyricsEmbeddedSource => '내장';

  @override
  String get unknownAlbum => '알 수 없는 앨범';

  @override
  String get unknownArtist => '알 수 없는 아티스트';

  @override
  String get permissionAudio => '오디오';

  @override
  String get permissionStorage => '저장소';

  @override
  String get permissionNotification => '알림';

  @override
  String get errorInvalidFolderSelected => '잘못된 폴더가 선택됨';

  @override
  String get storeAnyVersion => '모든';

  @override
  String get storeCategoryMetadata => '메타데이터';

  @override
  String get storeCategoryDownload => '다운로드';

  @override
  String get storeCategoryUtility => '유틸리티';

  @override
  String get storeCategoryLyrics => '가사';

  @override
  String get storeCategoryIntegration => '연동';

  @override
  String get artistReleases => '발매 음악';

  @override
  String get editMetadataSelectNone => '없음';

  @override
  String queueRetryAllFailed(int count) {
    return '재시도 $count 번 실패';
  }

  @override
  String get settingsSaveDownloadHistory => '다운로드 기록 저장';

  @override
  String get settingsSaveDownloadHistorySubtitle =>
      '완료된 다운로드를 기록 및 라이브러리 보기에 유지합니다';

  @override
  String get dialogDisableHistoryTitle => '다운로드 기록을 끄시겠습니까?';

  @override
  String get dialogDisableHistoryMessage => '기존 기록이 삭제됩니다. 다운로드된 파일은 삭제되지 않습니다';

  @override
  String get dialogDisableAndClear => '끄고 지우기';

  @override
  String get openInOtherServices => '다른 서비스에서 열기';

  @override
  String get shareSheetNoExtensions => '호환되는 다른 서비스가 없음';

  @override
  String get shareSheetNotFound => '찾을 수 없음';

  @override
  String get shareSheetCopyLink => '링크 복사';

  @override
  String shareSheetLinkCopied(Object service) {
    return '$service 링크가 복사됨';
  }

  @override
  String get libraryPlayback => '재생';

  @override
  String get libraryExternalPlayer => '외부 플레이어';

  @override
  String get libraryExternalPlayerSubtitle =>
      '감상용으로 권장됩니다. 최고 음질, 갭리스 재생, EQ 및 다양한 오디오 형식을 지원합니다';

  @override
  String get libraryBuiltInPreviewPlayer => '내부 미리듣기 플레이어';

  @override
  String get libraryBuiltInPreviewPlayerSubtitle =>
      'SpotiFLAC Mobile에서 빠른 로컬 미리듣기 전용이며, 일반적인 음악 감상에는 권장되지 않습니다';

  @override
  String get libraryBuiltInPlayerInfo =>
      '내부 플레이어는 로컬 트랙을 빠르게 미리듣기 위한 도구입니다. 실제 음악 감상은 외부 음악 플레이어를 이용하는 것을 권장합니다';

  @override
  String get nowPlayingTitle => '현재 재생 중';

  @override
  String get nowPlayingNothingPlaying => '재생 중인 노래가 없음';

  @override
  String get nowPlayingMinimize => '최소화';

  @override
  String get nowPlayingUpNext => '다음 곡';

  @override
  String get nowPlayingDetails => '트랙 세부 정보';

  @override
  String get nowPlayingOpenInExternalPlayer => '외부 플레이어에서 열기';

  @override
  String get nowPlayingTabPlayer => '플레이어';

  @override
  String get nowPlayingTabLyrics => '가사';

  @override
  String get nowPlayingNoLyrics => '이 파일에는 가사가 없음';

  @override
  String get nowPlayingLibraryEmpty => '라이브러리가 비어 있음';

  @override
  String nowPlayingShuffleLibraryFailed(String error) {
    return '라이브러리에서 셔플을 사용할 수 없음: $error';
  }

  @override
  String get nowPlayingShuffleOn => '셔플 켜기';

  @override
  String get nowPlayingPlayInOrder => '순서대로 재생';

  @override
  String get nowPlayingShuffleLibrary => '라이브러리 셔플';

  @override
  String get nowPlayingQueueEmpty => '현재 다운로드 목록이 비어 있음';

  @override
  String get nowPlayingNoMetadata => '사용할 수 있는 메타데이터가 없음';

  @override
  String get announcementUnableToOpenLink => '링크를 열 수 없습니다. 다시 시도해 주세요';

  @override
  String trackConvertLosslessOutputWithCap(String quality) {
    return '$quality 제한이 있는 무손실 출력';
  }

  @override
  String trackConvertConfirmMessageLosslessCapped(
    String sourceFormat,
    String targetFormat,
    String quality,
  ) {
    return '$sourceFormat에서 $targetFormat($quality)으로 변환하시겠습니까?\n\n출력은 무손실 코덱을 유지하지만 비트 심도/샘플 속도가 제한됩니다. 변환 후 원본 파일이 삭제됩니다';
  }

  @override
  String selectionBatchConvertConfirmMessageLosslessCapped(
    int count,
    String format,
    String quality,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '트랙',
      one: '트랙',
    );
    return '$count 개의 $_temp0을 $format($quality)으로 변환하시겠습니까?\n\n출력은 무손실 코덱을 유지하지만 비트 심도/샘플 속도가 제한됩니다. 변환 후 원본 파일이 삭제됩니다';
  }

  @override
  String trackConvertActionLabelLossless(
    String sourceFormat,
    String targetFormat,
    String quality,
  ) {
    return '$sourceFormat → $targetFormat ($quality)';
  }

  @override
  String trackConvertActionLabelLossy(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return '$sourceFormat → $targetFormat @ $bitrate';
  }

  @override
  String get aboutPaxsenixSubtitle =>
      'Musixmatch, Netease, Apple Music, QQ Music, Spotify, Deezer, YouTube, Kugou 및 Genius용 가사 프록시';

  @override
  String get snackbarPlayingNext => '다음 곡 재생';

  @override
  String get snackbarAddedToQueueGeneric => '현재 다운로드 목록에 추가됨';

  @override
  String selectionDeletePlaylistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '재생목록',
      one: '재생목록',
    );
    return '$count $_temp0 삭제';
  }

  @override
  String get actionShuffle => '셔플';

  @override
  String get downloadPrimaryArtistOnlyOn => '기본 아티스트만: ON';

  @override
  String get downloadPrimaryArtistOnlyOff => '기본 아티스트만: OFF';

  @override
  String get downloadAlbumArtistMetadataPrimaryOnly => '앨범 아티스트 메타데이터: 기본만';

  @override
  String get downloadAlbumArtistMetadataFull => '앨범 아티스트 메타데이터: 전체';

  @override
  String get trackConvertOriginal => '원본';

  @override
  String get trackConvertOriginalQuality => '원본 음질';

  @override
  String get trackConvertLosslessSuffix => '무손실';

  @override
  String get trackConvertDithering => '디더링';

  @override
  String get trackConvertResampler => '리샘플러';

  @override
  String get trackConvertDitherNone => '없음';

  @override
  String get trackConvertDitherTriangular => 'TPDF';

  @override
  String get trackConvertDitherTriangularHp => '삼각형 HP';

  @override
  String get trackConvertResamplerSwr => 'SWR';

  @override
  String get trackConvertResamplerSoxr => 'SoXr';

  @override
  String get updateSeeReleaseNotes => '자세한 내용은 릴리스 노트를 참조하세요';

  @override
  String get unknownTitle => '알 수 없는 제목';

  @override
  String get trackPlayNext => '다음 곡 재생';

  @override
  String get trackAddToQueue => '다운로드 목록에 추가';

  @override
  String snackbarExtensionInstalledEnable(String extensionName) {
    return '\'\'$extensionName\'\'이 설치됨. \'설정 > 확장 프로그램\'에서 활성화하세요';
  }

  @override
  String snackbarExtensionUpdatedVersion(String extensionName, String version) {
    return '\'\'$extensionName\'\'이 v$version으로 업데이트됨';
  }

  @override
  String snackbarFailedToInstallNamed(String extensionName) {
    return '$extensionName 설치 실패';
  }

  @override
  String snackbarFailedToUpdateNamed(String extensionName) {
    return '$extensionName 업데이트 실패';
  }

  @override
  String get releaseTypeEp => 'EP';

  @override
  String get releaseTypeSingle => '싱글';

  @override
  String get trackCoverOnline => '온라인 표지';

  @override
  String get regionCountryUS => '미국';

  @override
  String get regionCountryGB => '영국';

  @override
  String get regionCountryFR => '프랑스';

  @override
  String get regionCountryDE => '독일';

  @override
  String get regionCountryJP => '일본';

  @override
  String get regionCountryKR => '한국';

  @override
  String get regionCountryIN => '인도';

  @override
  String get regionCountryID => '인도네시아';

  @override
  String get regionCountryBR => '브라질';

  @override
  String get regionCountryMX => '멕시코';

  @override
  String get regionCountryAU => '호주';

  @override
  String get regionCountryCA => '캐나다';

  @override
  String get regionCountryXK => '코소보';

  @override
  String get extensionVerificationBrowserTitle => '인증 브라우저';

  @override
  String get extensionVerificationBrowserSubtitleExternal =>
      '인증을 기본 브라우저에서 먼저 실행합니다';

  @override
  String get extensionVerificationBrowserSubtitleInApp =>
      '인증을 앱 내 브라우저에서 먼저 실행합니다';

  @override
  String get extensionVerificationBrowserExternal => '외부';

  @override
  String get extensionVerificationBrowserInApp => '내부';

  @override
  String get extensionVerificationHelpTitleManual => '수동으로 인증 열기';

  @override
  String get extensionVerificationHelpTitleWaiting => '아직 인증을 기다리는 중';

  @override
  String get extensionVerificationHelpMessageManual =>
      'SpotiFLAC Mobile에서 브라우저를 자동으로 열지 못하였습니다. 아래 링크를 브라우저에서 열거나 직접 복사하세요';

  @override
  String get extensionVerificationHelpMessageWaiting =>
      '브라우저가 열리지 않았거나 인증을 완료한 후에도 SpotiFLAC Mobile로 돌아오지 않았다면, 아래 링크를 다시 열거나 직접 복사하세요';

  @override
  String get extensionVerificationClose => '닫기';

  @override
  String get extensionVerificationCopyLink => '링크 복사';

  @override
  String get extensionVerificationLinkCopied => '인증 링크가 복사됨';

  @override
  String get extensionVerificationOpenBrowser => '브라우저 열기';

  @override
  String get settingsSearchHint => '설정 검색';

  @override
  String settingsSearchNoResults(String query) {
    return '\"$query\"와(과) 일치하는 설정이 없습니다';
  }

  @override
  String get settingsGroupInterface => '확장 기능 및 외관';

  @override
  String get settingsGroupContent => '콘텐츠 및 메타데이터';

  @override
  String get settingsGroupDownloads => '다운로드 및 파일';

  @override
  String get settingsGroupSystem => '시스템';

  @override
  String get settingsGroupHelp => '정보 및 지원';
}
