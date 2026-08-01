// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get navStore => 'Repo';

  @override
  String get homeTitle => 'Home';

  @override
  String get homeSubtitle => 'Paste a Spotify link or search by name';

  @override
  String get homeEmptyTitle => 'No search providers yet';

  @override
  String get homeEmptySubtitle => 'Install an extension to continue.';

  @override
  String get homeSupports => 'Supports: Track, Album, Playlist, Artist URLs';

  @override
  String get homeRecent => 'Recent';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterAlbums => 'Albums';

  @override
  String get historyFilterSingles => 'Singles';

  @override
  String get historySearchHint => 'Search history...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDownload => 'Download';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsExtensions => 'Extensions';

  @override
  String get settingsAbout => 'About';

  @override
  String get downloadTitle => 'Download';

  @override
  String get downloadAskQualitySubtitle =>
      'Show quality picker for each download';

  @override
  String get downloadFilenameFormat => 'Filename Format';

  @override
  String get downloadSingleFilenameFormat => 'Single Filename Format';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Filename pattern for singles and EPs. Uses the same tags as the album format.';

  @override
  String get downloadFolderOrganization => 'Folder Organization';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceThemeSystem => 'System';

  @override
  String get appearanceThemeLight => 'Light';

  @override
  String get appearanceThemeDark => 'Dark';

  @override
  String get appearanceDynamicColor => 'Dynamic Color';

  @override
  String get appearanceDynamicColorSubtitle => 'Use colors from your wallpaper';

  @override
  String get appearanceHistoryView => 'History View';

  @override
  String get appearanceHistoryViewList => 'List';

  @override
  String get appearanceHistoryViewGrid => 'Grid';

  @override
  String get optionsPrimaryProvider => 'Primary Provider';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Service used when searching by track name.';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Using extension: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Default Search Tab';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Choose which tab opens first for new search results.';

  @override
  String get optionsAutoFallback => 'Auto Fallback';

  @override
  String get optionsAutoFallbackSubtitle =>
      'Try other services if download fails';

  @override
  String get optionsEmbedLyrics => 'Embed Lyrics';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Embed synced lyrics into FLAC files';

  @override
  String get optionsMaxQualityCover => 'Max Quality Cover';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'Download highest resolution cover art';

  @override
  String get optionsReplayGain => 'ReplayGain';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Scan loudness and embed ReplayGain tags (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Disabled: no loudness normalization tags';

  @override
  String get trackReplayGain => 'Rescan ReplayGain';

  @override
  String get trackReplayGainScanning => 'Analyzing loudness...';

  @override
  String get trackReplayGainSuccess => 'ReplayGain tags added';

  @override
  String get trackReplayGainFailed => 'Failed to add ReplayGain tags';

  @override
  String selectionReplayGainCount(int count) {
    return 'ReplayGain ($count)';
  }

  @override
  String get replayGainBatchConfirmTitle => 'Add ReplayGain';

  @override
  String replayGainBatchConfirmMessage(int count) {
    return 'Analyze loudness and write ReplayGain tags to $count track(s)?';
  }

  @override
  String get replayGainBatchAnalyzing => 'Analyzing ReplayGain...';

  @override
  String replayGainBatchSuccess(int success, int total) {
    return 'ReplayGain added to $success of $total tracks';
  }

  @override
  String get optionsArtistTagMode => 'Artist Tag Mode';

  @override
  String get optionsArtistTagModeDescription =>
      'Choose how multiple artists are written into embedded tags.';

  @override
  String get optionsArtistTagModeJoined => 'Single joined value';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Write one ARTIST value like \"Artist A, Artist B\" for maximum player compatibility.';

  @override
  String get optionsArtistTagModeSplitVorbis => 'Split tags for FLAC/Opus';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'Write one artist tag per artist for FLAC and Opus; MP3 and M4A stay joined.';

  @override
  String get optionsExtensionStore => 'Extension Repo';

  @override
  String get optionsExtensionStoreSubtitle => 'Show Repo tab in navigation';

  @override
  String get optionsCheckUpdates => 'Check for Updates';

  @override
  String get optionsCheckUpdatesSubtitle =>
      'Notify when new version is available';

  @override
  String get optionsUpdateChannel => 'Update Channel';

  @override
  String get optionsUpdateChannelStable => 'Stable releases only';

  @override
  String get optionsUpdateChannelPreview => 'Get preview releases';

  @override
  String get optionsUpdateChannelWarning =>
      'Preview may contain bugs or incomplete features';

  @override
  String get optionsClearHistory => 'Clear Download History';

  @override
  String get optionsClearHistorySubtitle =>
      'Remove all downloaded tracks from history';

  @override
  String get optionsDetailedLogging => 'Detailed Logging';

  @override
  String get optionsDetailedLoggingOn => 'Detailed logs are being recorded';

  @override
  String get optionsDetailedLoggingOff => 'Enable for bug reports';

  @override
  String get extensionsTitle => 'Extensions';

  @override
  String get extensionsDisabled => 'Disabled';

  @override
  String extensionsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get extensionsUninstall => 'Uninstall';

  @override
  String get storeTitle => 'Extension Repo';

  @override
  String get storeSearch => 'Search extensions...';

  @override
  String get storeInstall => 'Install';

  @override
  String get storeInstalled => 'Installed';

  @override
  String get storeUpdate => 'Update';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutContributors => 'Contributors';

  @override
  String get aboutMobileDeveloper => 'Mobile version developer';

  @override
  String get aboutOriginalCreator => 'Creator of the original SpotiFLAC';

  @override
  String get aboutLogoArtist =>
      'The talented artist who created our beautiful app logo!';

  @override
  String get aboutTranslators => 'Translators';

  @override
  String get aboutSpecialThanks => 'Special Thanks';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutMobileSource => 'Mobile source code';

  @override
  String get aboutPCSource => 'PC source code';

  @override
  String get aboutKeepAndroidOpen => 'Keep Android Open';

  @override
  String get aboutReportIssue => 'Report an issue';

  @override
  String get aboutReportIssueSubtitle => 'Report any problems you encounter';

  @override
  String get aboutFeatureRequest => 'Feature request';

  @override
  String get aboutFeatureRequestSubtitle => 'Suggest new features for the app';

  @override
  String get aboutTelegramChannel => 'Telegram Channel';

  @override
  String get aboutTelegramChannelSubtitle => 'Announcements and updates';

  @override
  String get aboutTelegramChat => 'Telegram Community';

  @override
  String get aboutTelegramChatSubtitle => 'Chat with other users';

  @override
  String get aboutSocial => 'Social';

  @override
  String get aboutApp => 'App';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBinimumDesc =>
      'The creator of QQDL & HiFi API. This project helped shape lossless download support.';

  @override
  String get aboutSachinsenalDesc =>
      'The original HiFi project creator. A foundation for lossless-source integration.';

  @override
  String get aboutSjdonadoDesc =>
      'Creator of I Don\'t Have Spotify (IDHS). The fallback link resolver that saves the day!';

  @override
  String get aboutAppDescription =>
      'Search music metadata, manage extensions, and organize your library.';

  @override
  String get artistAlbums => 'Albums';

  @override
  String get artistSingles => 'Singles & EPs';

  @override
  String get artistCompilations => 'Compilations';

  @override
  String get artistPopular => 'Popular';

  @override
  String artistMonthlyListeners(String count) {
    return '$count monthly listeners';
  }

  @override
  String get trackMetadataService => 'Service';

  @override
  String get trackMetadataPlay => 'Play';

  @override
  String get trackMetadataShare => 'Share';

  @override
  String get trackMetadataDelete => 'Delete';

  @override
  String get setupGrantPermission => 'Grant Permission';

  @override
  String get setupSkip => 'Skip for now';

  @override
  String get setupStorageAccessRequired => 'Storage Access Required';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Android 11+ requires \"All files access\" permission to save files to your chosen download folder.';

  @override
  String get setupOpenSettings => 'Open Settings';

  @override
  String get setupPermissionDeniedMessage =>
      'Permission denied. Please grant all permissions to continue.';

  @override
  String setupPermissionRequired(String permissionType) {
    return '$permissionType Permission Required';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return '$permissionType permission is required for the best experience. You can change this later in Settings.';
  }

  @override
  String get setupUseDefaultFolder => 'Use Default Folder?';

  @override
  String get setupNoFolderSelected =>
      'No folder selected. Would you like to use the default Music folder?';

  @override
  String get setupUseDefault => 'Use Default';

  @override
  String get setupDownloadLocationTitle => 'Download Location';

  @override
  String get setupDownloadLocationIosMessage =>
      'On iOS, downloads are saved to the app\'s Documents folder. You can access them via the Files app.';

  @override
  String get setupAppDocumentsFolder => 'App Documents Folder';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Recommended - accessible via Files app';

  @override
  String get setupChooseFromFiles => 'Choose from Files';

  @override
  String get setupChooseFromFilesSubtitle => 'Select iCloud or other location';

  @override
  String get setupIosEmptyFolderWarning =>
      'iOS limitation: Empty folders cannot be selected. Choose a folder with at least one file.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive is not supported. Please use the app Documents folder.';

  @override
  String get setupDownloadInFlac => 'Download Spotify tracks in FLAC';

  @override
  String get setupStorageGranted => 'Storage Permission Granted!';

  @override
  String get setupStorageRequired => 'Storage Permission Required';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC needs storage permission to save your downloaded music files.';

  @override
  String get setupNotificationGranted => 'Notification Permission Granted!';

  @override
  String get setupNotificationEnable => 'Enable Notifications';

  @override
  String get setupFolderChoose => 'Choose Download Folder';

  @override
  String get setupFolderDescription =>
      'Select a folder where your downloaded music will be saved.';

  @override
  String get setupSelectFolder => 'Select Folder';

  @override
  String get setupEnableNotifications => 'Enable Notifications';

  @override
  String get setupNotificationBackgroundDescription =>
      'Get notified about download progress and completion. This helps you track downloads when the app is in background.';

  @override
  String get setupSkipForNow => 'Skip for now';

  @override
  String get setupNext => 'Next';

  @override
  String get setupGetStarted => 'Get Started';

  @override
  String get setupAllowAccessToManageFiles =>
      'Please enable \"Allow access to manage all files\" in the next screen.';

  @override
  String get setupLanguageTitle => 'Choose Language';

  @override
  String get setupLanguageDescription =>
      'Select your preferred language for the app. You can change this later in Settings.';

  @override
  String get setupLanguageSystemDefault => 'System Default';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get dialogSave => 'Save';

  @override
  String get dialogDelete => 'Delete';

  @override
  String get dialogRetry => 'Retry';

  @override
  String get dialogClear => 'Clear';

  @override
  String get dialogDone => 'Done';

  @override
  String get dialogImport => 'Import';

  @override
  String get dialogDownload => 'Download';

  @override
  String get previewPlay => 'Play preview';

  @override
  String get previewStop => 'Stop preview';

  @override
  String get previewUnavailable => 'Preview unavailable';

  @override
  String get dialogDiscard => 'Discard';

  @override
  String get dialogRemove => 'Remove';

  @override
  String get dialogUninstall => 'Uninstall';

  @override
  String get dialogDiscardChanges => 'Discard Changes?';

  @override
  String get dialogUnsavedChanges =>
      'You have unsaved changes. Do you want to discard them?';

  @override
  String get dialogClearAll => 'Clear All';

  @override
  String get dialogRemoveExtension => 'Remove Extension';

  @override
  String get dialogRemoveExtensionMessage =>
      'Are you sure you want to remove this extension? This cannot be undone.';

  @override
  String get dialogUninstallExtension => 'Uninstall Extension?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return 'Are you sure you want to remove $extensionName?';
  }

  @override
  String get dialogClearHistoryTitle => 'Clear History';

  @override
  String get dialogClearHistoryMessage =>
      'Are you sure you want to clear all download history? This cannot be undone.';

  @override
  String get dialogDeleteSelectedTitle => 'Delete Selected';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Delete $count $_temp0 from history?\n\nThis will also delete the files from storage.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Import Playlist';

  @override
  String dialogImportPlaylistMessage(int count) {
    return 'Found $count tracks in CSV. Add them to download queue?';
  }

  @override
  String csvImportTracks(int count) {
    return '$count tracks from CSV';
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
    return 'Added \"$trackName\" to queue';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return 'Added $count tracks to queue';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\"$trackName\" already downloaded';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '\"$trackName\" already exists in your library';
  }

  @override
  String get snackbarHistoryCleared => 'History cleared';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Deleted $count $_temp0';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'Cannot open file: $error';
  }

  @override
  String get snackbarViewQueue => 'View Queue';

  @override
  String snackbarUrlCopied(String platform) {
    return '$platform URL copied to clipboard';
  }

  @override
  String get snackbarFileNotFound => 'File not found';

  @override
  String get snackbarSelectExtFile => 'Please select a .spotiflac-ext file';

  @override
  String get snackbarProviderPrioritySaved => 'Provider priority saved';

  @override
  String get snackbarMetadataProviderSaved =>
      'Metadata provider priority saved';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '$extensionName installed.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName updated.';
  }

  @override
  String get snackbarFailedToInstall => 'Failed to install extension';

  @override
  String get snackbarFailedToUpdate => 'Failed to update extension';

  @override
  String get errorRateLimited => 'Rate Limited';

  @override
  String get errorRateLimitedMessage =>
      'Too many requests. Please wait a moment before searching again.';

  @override
  String get errorNoTracksFound => 'No tracks found';

  @override
  String get searchEmptyResultSubtitle => 'Try another keyword';

  @override
  String get errorUrlNotRecognized => 'Link not recognized';

  @override
  String get errorUrlNotRecognizedMessage =>
      'This link is not supported. Make sure the URL is correct and a compatible extension is installed.';

  @override
  String get errorUrlFetchFailed =>
      'Failed to load content from this link. Please try again.';

  @override
  String errorMissingExtensionSource(String item) {
    return 'Cannot load $item: missing extension source';
  }

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSelectAll => 'Select All';

  @override
  String get actionDeselect => 'Deselect';

  @override
  String selectionSelected(int count) {
    return '$count selected';
  }

  @override
  String get selectionAllSelected => 'All tracks selected';

  @override
  String get selectionSelectToDelete => 'Select tracks to delete';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Fetching metadata... $current/$total';
  }

  @override
  String get progressReadingCsv => 'Reading CSV...';

  @override
  String get searchSongs => 'Songs';

  @override
  String get searchArtists => 'Artists';

  @override
  String get searchAlbums => 'Albums';

  @override
  String get searchPlaylists => 'Playlists';

  @override
  String get searchSortTitle => 'Sort Results';

  @override
  String get searchSortDefault => 'Default';

  @override
  String get searchSortTitleAZ => 'Title (A-Z)';

  @override
  String get searchSortTitleZA => 'Title (Z-A)';

  @override
  String get searchSortArtistAZ => 'Artist (A-Z)';

  @override
  String get searchSortArtistZA => 'Artist (Z-A)';

  @override
  String get searchSortDurationShort => 'Duration (Shortest)';

  @override
  String get searchSortDurationLong => 'Duration (Longest)';

  @override
  String get searchSortDateOldest => 'Release Date (Oldest)';

  @override
  String get searchSortDateNewest => 'Release Date (Newest)';

  @override
  String get tooltipPlay => 'Play';

  @override
  String get filenameFormat => 'Filename Format';

  @override
  String get filenameShowAdvancedTags => 'Show advanced tags';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Enable formatted tags for track padding and date patterns';

  @override
  String get folderOrganizationNone => 'No organization';

  @override
  String get folderOrganizationByPlaylist => 'By Playlist';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Separate folder for each playlist';

  @override
  String get folderOrganizationByArtist => 'By Artist';

  @override
  String get folderOrganizationByAlbum => 'By Album';

  @override
  String get folderOrganizationByArtistAlbum => 'Artist/Album';

  @override
  String get folderOrganizationDescription =>
      'Organize downloaded files into folders';

  @override
  String get folderOrganizationNoneSubtitle => 'All files in download folder';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Separate folder for each artist';

  @override
  String get folderOrganizationByAlbumSubtitle =>
      'Separate folder for each album';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Nested folders for artist and album';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String get updateLater => 'Later';

  @override
  String get updateStartingDownload => 'Starting download...';

  @override
  String get updateDownloadFailed => 'Download failed';

  @override
  String get updateFailedMessage => 'Failed to download update';

  @override
  String get updateNewVersionReady => 'A new version is ready';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String updateRequiredNotice(int count) {
    return 'This version is $count releases behind and is no longer supported. Update to keep using the app.';
  }

  @override
  String get updateCurrent => 'Current';

  @override
  String get updateNew => 'New';

  @override
  String get updateDownloading => 'Downloading...';

  @override
  String get updateWhatsNew => 'What\'s New';

  @override
  String get updateDownloadInstall => 'Download & Install';

  @override
  String get updateDontRemind => 'Don\'t remind';

  @override
  String get providerPriorityTitle => 'Provider Priority';

  @override
  String get providerPriorityDescription =>
      'Drag to reorder download providers. The app will try providers from top to bottom when downloading tracks.';

  @override
  String get providerPriorityInfo =>
      'If a track is not available on the first provider, the app will automatically try the next one.';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Choose which installed download extensions can be used during automatic fallback.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Only enabled extensions with download-provider capability are listed here.';

  @override
  String get providerExtension => 'Extension';

  @override
  String get metadataProviderPriorityTitle => 'Metadata Priority';

  @override
  String get metadataProviderPriorityDescription =>
      'Drag to reorder metadata providers. The app will try providers from top to bottom when searching for tracks and fetching metadata.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer has no rate limits and is recommended as primary. Spotify may rate limit after many requests.';

  @override
  String get logTitle => 'Logs';

  @override
  String get logCopied => 'Logs copied to clipboard';

  @override
  String get logSearchHint => 'Search logs...';

  @override
  String get logFilterLevel => 'Level';

  @override
  String get logFilterSection => 'Filter';

  @override
  String get logShareLogs => 'Share logs';

  @override
  String get logClearLogs => 'Clear logs';

  @override
  String get logClearLogsTitle => 'Clear Logs';

  @override
  String get logClearLogsMessage => 'Are you sure you want to clear all logs?';

  @override
  String get logFilterBySeverity => 'Filter logs by severity';

  @override
  String get logNoLogsYet => 'No logs yet';

  @override
  String get logNoLogsYetSubtitle => 'Logs will appear here as you use the app';

  @override
  String logEntriesFiltered(int count) {
    return 'Entries ($count filtered)';
  }

  @override
  String logEntries(int count) {
    return 'Entries ($count)';
  }

  @override
  String get channelStable => 'Stable';

  @override
  String get channelPreview => 'Preview';

  @override
  String get sectionSearchSource => 'Search Source';

  @override
  String get sectionDownload => 'Download';

  @override
  String get sectionPerformance => 'Performance';

  @override
  String get sectionApp => 'App';

  @override
  String get sectionData => 'Data';

  @override
  String get sectionDebug => 'Debug';

  @override
  String get sectionService => 'Service';

  @override
  String get sectionAudioQuality => 'Audio Quality';

  @override
  String get sectionFileSettings => 'File Settings';

  @override
  String get sectionLyrics => 'Lyrics';

  @override
  String get lyricsMode => 'Lyrics Mode';

  @override
  String get lyricsModeDescription =>
      'Choose how lyrics are saved with your downloads';

  @override
  String get lyricsModeEmbed => 'Embed in file';

  @override
  String get lyricsModeEmbedSubtitle => 'Lyrics stored inside FLAC metadata';

  @override
  String get lyricsModeExternal => 'External .lrc file';

  @override
  String get lyricsModeExternalSubtitle =>
      'Separate .lrc file for players like Samsung Music';

  @override
  String get lyricsModeBoth => 'Both';

  @override
  String get lyricsModeBothSubtitle => 'Embed and save .lrc file';

  @override
  String get sectionColor => 'Color';

  @override
  String get sectionTheme => 'Theme';

  @override
  String get sectionLayout => 'Layout';

  @override
  String get sectionLanguage => 'Language';

  @override
  String get appearanceLanguage => 'App Language';

  @override
  String get settingsAppearanceSubtitle => 'Theme, colors, display';

  @override
  String get settingsDownloadSubtitle => 'Service, quality, filename format';

  @override
  String get settingsExtensionsSubtitle => 'Manage download providers';

  @override
  String get settingsLogsSubtitle => 'View app logs for debugging';

  @override
  String get loadingSharedLink => 'Loading shared link...';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String downloadAllCount(int count) {
    return 'Download All ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Copy file path';

  @override
  String get trackRemoveFromDevice => 'Remove from device';

  @override
  String get trackLoadLyrics => 'Load Lyrics';

  @override
  String get trackMetadata => 'Metadata';

  @override
  String get trackFileInfo => 'File Info';

  @override
  String get trackLyrics => 'Lyrics';

  @override
  String get trackFileNotFound => 'File not found';

  @override
  String get trackOpenInDeezer => 'Open in Deezer';

  @override
  String get trackOpenInSpotify => 'Open in Spotify';

  @override
  String get trackTrackName => 'Track name';

  @override
  String get trackArtist => 'Artist';

  @override
  String get trackAlbumArtist => 'Album artist';

  @override
  String get trackAlbum => 'Album';

  @override
  String get trackTrackNumber => 'Track number';

  @override
  String get trackDiscNumber => 'Disc number';

  @override
  String get trackDuration => 'Duration';

  @override
  String get trackAudioQuality => 'Audio quality';

  @override
  String get trackReleaseDate => 'Release date';

  @override
  String get trackGenre => 'Genre';

  @override
  String get trackLabel => 'Label';

  @override
  String get trackCopyright => 'Copyright';

  @override
  String get trackDownloaded => 'Downloaded';

  @override
  String get trackCopyLyrics => 'Copy lyrics';

  @override
  String trackLyricsSource(String source) {
    return 'Source: $source';
  }

  @override
  String get trackLyricsNotAvailable => 'Lyrics not available for this track';

  @override
  String get trackLyricsNotInFile => 'No lyrics found in this file';

  @override
  String get trackFetchOnlineLyrics => 'Fetch from Online';

  @override
  String get trackLyricsTimeout => 'Request timed out. Try again later.';

  @override
  String get trackLyricsLoadFailed => 'Failed to load lyrics';

  @override
  String get trackEmbedLyrics => 'Embed Lyrics';

  @override
  String get trackLyricsEmbedded => 'Lyrics embedded successfully';

  @override
  String get trackInstrumental => 'Instrumental track';

  @override
  String get trackCopiedToClipboard => 'Copied to clipboard';

  @override
  String get trackDeleteConfirmTitle => 'Remove from device?';

  @override
  String get trackDeleteConfirmMessage =>
      'This will permanently delete the downloaded file and remove it from your history.';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String dateDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String dateWeeksAgo(int count) {
    return '$count weeks ago';
  }

  @override
  String dateMonthsAgo(int count) {
    return '$count months ago';
  }

  @override
  String get storeFilterAll => 'All';

  @override
  String get storeFilterMetadata => 'Metadata';

  @override
  String get storeFilterDownload => 'Download';

  @override
  String get storeFilterUtility => 'Utility';

  @override
  String get storeFilterLyrics => 'Lyrics';

  @override
  String get storeFilterIntegration => 'Integration';

  @override
  String get storeClearFilters => 'Clear filters';

  @override
  String get storeAddRepoTitle => 'Add Extension Repository';

  @override
  String get storeAddRepoDescription =>
      'Enter a GitHub repository URL that contains a registry.json file to browse and install extensions.';

  @override
  String get storeRepoUrlLabel => 'Repository URL';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeAddRepoButton => 'Add Repository';

  @override
  String get storeChangeRepoTooltip => 'Change repository';

  @override
  String get storeRepoDialogTitle => 'Extension Repository';

  @override
  String get storeRepoDialogCurrent => 'Current repository:';

  @override
  String get storeNewRepoUrlLabel => 'New Repository URL';

  @override
  String get storeLoadError => 'Failed to load repository';

  @override
  String get storeEmptyNoExtensions => 'No extensions available';

  @override
  String get storeEmptyNoResults => 'No extensions found';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => 'Error';

  @override
  String get extensionCapabilities => 'Capabilities';

  @override
  String get extensionMetadataProvider => 'Metadata Provider';

  @override
  String get extensionDownloadProvider => 'Download Provider';

  @override
  String get extensionLyricsProvider => 'Lyrics Provider';

  @override
  String get extensionUrlHandler => 'URL Handler';

  @override
  String get extensionQualityOptions => 'Quality Options';

  @override
  String get extensionPostProcessingHooks => 'Post-Processing Hooks';

  @override
  String get extensionPermissions => 'Permissions';

  @override
  String get extensionSettings => 'Settings';

  @override
  String get extensionRemoveButton => 'Remove Extension';

  @override
  String get extensionUpdated => 'Updated';

  @override
  String get extensionMinAppVersion => 'Min App Version';

  @override
  String get extensionCustomTrackMatching => 'Custom Track Matching';

  @override
  String get extensionPostProcessing => 'Post-Processing';

  @override
  String extensionHooksAvailable(int count) {
    return '$count hook(s) available';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count pattern(s)';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Strategy: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => 'Provider Priority';

  @override
  String get extensionsInstalledSection => 'Installed Extensions';

  @override
  String get extensionsNoExtensions => 'No extensions installed';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Install .spotiflac-ext files to add new providers';

  @override
  String get extensionsInstallButton => 'Install Extension';

  @override
  String get extensionsInfoTip =>
      'Extensions can add new metadata and download providers. Only install extensions from trusted sources.';

  @override
  String get extensionsInstalledSuccess => 'Extension installed successfully';

  @override
  String extensionsInstalledCount(int count) {
    return '$count extensions installed successfully';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return 'Installed $installed of $attempted extensions';
  }

  @override
  String get extensionsDownloadPriority => 'Download Priority';

  @override
  String get extensionsDownloadPrioritySubtitle => 'Set download service order';

  @override
  String get extensionsFallbackTitle => 'Fallback Extensions';

  @override
  String get extensionsFallbackSubtitle =>
      'Choose which installed download extensions can be used as fallback';

  @override
  String get extensionsNoDownloadProvider =>
      'No extensions with download provider';

  @override
  String get extensionsMetadataPriority => 'Metadata Priority';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Set search & metadata source order';

  @override
  String get extensionsNoMetadataProvider =>
      'No extensions with metadata provider';

  @override
  String get extensionsSearchProvider => 'Search Provider';

  @override
  String get extensionsNoCustomSearch => 'No extensions with custom search';

  @override
  String get extensionsSearchProviderDescription =>
      'Choose which service to use for searching tracks';

  @override
  String get extensionsCustomSearch => 'Custom search';

  @override
  String get extensionsErrorLoading => 'Error loading extension';

  @override
  String get qualityFlacLossless => 'FLAC Lossless';

  @override
  String get qualityFlacLosslessSubtitle => '16-bit / 44.1kHz';

  @override
  String get qualityHiResFlac => 'Hi-Res FLAC';

  @override
  String get qualityHiResFlacSubtitle => '24-bit / up to 96kHz';

  @override
  String get qualityHiResFlacMax => 'Hi-Res FLAC Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-bit / up to 192kHz';

  @override
  String get downloadLossy320 => 'Lossy 320kbps';

  @override
  String get downloadLossyFormat => 'Lossy Format';

  @override
  String get downloadLossy320Format => 'Lossy 320kbps Format';

  @override
  String get downloadLossy320FormatDesc =>
      'Choose the output format for 320kbps lossy downloads. The original stream will be converted to your selected format when needed.';

  @override
  String get downloadLossyMp3 => 'MP3 320kbps';

  @override
  String get downloadLossyMp3Subtitle => 'Best compatibility, ~10MB per track';

  @override
  String get downloadLossyAac => 'AAC/M4A 320kbps';

  @override
  String get downloadLossyAacSubtitle =>
      'Best mobile compatibility, M4A container';

  @override
  String get downloadLossyOpus256 => 'Opus 256kbps';

  @override
  String get downloadLossyOpus256Subtitle =>
      'Best quality Opus, ~8MB per track';

  @override
  String get downloadLossyOpus128 => 'Opus 128kbps';

  @override
  String get downloadLossyOpus128Subtitle => 'Smallest size, ~4MB per track';

  @override
  String get downloadAskBeforeDownload => 'Ask Before Download';

  @override
  String get downloadDirectory => 'Download Directory';

  @override
  String get downloadSeparateSinglesFolder => 'Separate Singles Folder';

  @override
  String get downloadAlbumFolderStructure => 'Album Folder Structure';

  @override
  String get albumFolderStructureDescription =>
      'Choose how album folders are structured';

  @override
  String get downloadUseAlbumArtistForFolders => 'Use Album Artist for folders';

  @override
  String get downloadUsePrimaryArtistOnly => 'Primary artist only for folders';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Featured artists removed from folder name (e.g. Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Full artist string used for folder name';

  @override
  String get downloadSelectQuality => 'Select Quality';

  @override
  String get downloadFrom => 'Download From';

  @override
  String get appearanceAmoledDark => 'AMOLED Dark';

  @override
  String get appearanceAmoledDarkSubtitle => 'Pure black background';

  @override
  String get appearanceHeroAnimations => 'Hero animations';

  @override
  String get appearanceHeroAnimationsSubtitle =>
      'Fly covers between screens, e.g. when opening the player';

  @override
  String get appearanceForceBlur => 'Always use blur effects';

  @override
  String get appearanceForceBlurSubtitle =>
      'Enable the navigation bar blur even on devices where it is off by default. May cost performance.';

  @override
  String get queueClearAll => 'Clear All';

  @override
  String get queueClearAllMessage =>
      'Are you sure you want to clear all downloads?';

  @override
  String get settingsAutoExportFailed => 'Auto-export failed downloads';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Save failed downloads to TXT file automatically';

  @override
  String get settingsDownloadNetwork => 'Download Network';

  @override
  String get settingsDownloadNetworkAny => 'WiFi + Mobile Data';

  @override
  String get settingsDownloadNetworkWifiOnly => 'WiFi Only';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'Choose which network to use for downloads. When set to WiFi Only, downloads will pause on mobile data.';

  @override
  String get settingsConcurrentDownloads => 'Concurrent downloads';

  @override
  String get settingsConcurrentDownloadsSubtitle =>
      'Downloading several tracks at once is faster, but some providers may rate-limit parallel requests.';

  @override
  String get concurrentDownloadsOne => '1 track at a time';

  @override
  String concurrentDownloadsCount(int count) {
    return 'Up to $count tracks at once';
  }

  @override
  String get albumFolderArtistAlbum => 'Artist / Album';

  @override
  String get albumFolderArtistAlbumSubtitle => 'Albums/Artist Name/Album Name/';

  @override
  String get albumFolderArtistYearAlbum => 'Artist / [Year] Album';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Albums/Artist Name/[2005] Album Name/';

  @override
  String get albumFolderAlbumOnly => 'Album Only';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Albums/Album Name/';

  @override
  String get albumFolderYearAlbum => '[Year] Album';

  @override
  String get albumFolderYearAlbumSubtitle => 'Albums/[2005] Album Name/';

  @override
  String get albumFolderArtistAlbumSingles => 'Artist / Album + Singles';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Artist/Album/ and Artist/Singles/';

  @override
  String get albumFolderArtistAlbumFlat => 'Artist / Album (Singles flat)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Artist/Album/ and Artist/song.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Delete Selected';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Delete $count $_temp0 from this album?\n\nThis will also delete the files from storage.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get downloadedAlbumTapToSelect => 'Tap tracks to select';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Delete $count $_temp0';
  }

  @override
  String get downloadedAlbumSelectToDelete => 'Select tracks to delete';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Disc $discNumber';
  }

  @override
  String get recentTypeArtist => 'Artist';

  @override
  String get recentTypeAlbum => 'Album';

  @override
  String get recentTypeSong => 'Song';

  @override
  String get recentTypePlaylist => 'Playlist';

  @override
  String get recentEmpty => 'No recent items yet';

  @override
  String get recentShowAllDownloads => 'Show All Downloads';

  @override
  String recentPlaylistInfo(String name) {
    return 'Playlist: $name';
  }

  @override
  String get discographyDownload => 'Download Discography';

  @override
  String get discographyDownloadAll => 'Download All';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$count tracks from $albumCount releases';
  }

  @override
  String get discographyAlbumsOnly => 'Albums Only';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$count tracks from $albumCount albums';
  }

  @override
  String get discographySinglesOnly => 'Singles & EPs Only';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$count tracks from $albumCount singles';
  }

  @override
  String get discographySelectAlbums => 'Select Albums...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Choose specific albums or singles';

  @override
  String get discographyFetchingTracks => 'Fetching tracks...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return 'Fetching $current of $total...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get discographyDownloadSelected => 'Download Selected';

  @override
  String discographyAddedToQueue(int count) {
    return 'Added $count tracks to queue';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added added, $skipped already downloaded';
  }

  @override
  String get discographyNoAlbums => 'No albums available';

  @override
  String get discographyFailedToFetch => 'Failed to fetch some albums';

  @override
  String get sectionStorageAccess => 'Storage Access';

  @override
  String get allFilesAccess => 'All Files Access';

  @override
  String get allFilesAccessEnabledSubtitle => 'Can write to any folder';

  @override
  String get allFilesAccessDisabledSubtitle => 'Limited to media folders only';

  @override
  String get allFilesAccessDescription =>
      'Enable this if you encounter write errors when saving to custom folders. Android 13+ restricts access to certain directories by default.';

  @override
  String get allFilesAccessDeniedMessage =>
      'Permission was denied. Please enable \'All files access\' manually in system settings.';

  @override
  String get allFilesAccessDisabledMessage =>
      'All Files Access disabled. The app will use limited storage access.';

  @override
  String get settingsLocalLibrary => 'Local Library';

  @override
  String get settingsLocalLibrarySubtitle => 'Scan music & detect duplicates';

  @override
  String get settingsCache => 'Storage & Cache';

  @override
  String get settingsCacheSubtitle => 'View size and clear cached data';

  @override
  String get libraryTitle => 'Local Library';

  @override
  String get libraryScanSettings => 'Scan Settings';

  @override
  String get libraryEnableLocalLibrary => 'Enable Local Library';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Scan and track your existing music';

  @override
  String get libraryFolder => 'Library Folder';

  @override
  String get libraryFolderHint => 'Tap to select folder';

  @override
  String get libraryShowDuplicateIndicator => 'Show Duplicate Indicator';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Show when searching for existing tracks';

  @override
  String get libraryAutoScan => 'Auto Scan';

  @override
  String get libraryAutoScanSubtitle =>
      'Automatically scan your library for new files';

  @override
  String get libraryAutoScanOff => 'Off';

  @override
  String get libraryAutoScanOnOpen => 'Every app open';

  @override
  String get libraryAutoScanDaily => 'Daily';

  @override
  String get libraryAutoScanWeekly => 'Weekly';

  @override
  String get libraryActions => 'Actions';

  @override
  String get libraryScan => 'Scan Library';

  @override
  String get libraryScanSubtitle => 'Scan for audio files';

  @override
  String get libraryScanSelectFolderFirst => 'Select a folder first';

  @override
  String get libraryCleanupMissingFiles => 'Cleanup Missing Files';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Remove entries for files that no longer exist';

  @override
  String get libraryClear => 'Clear Library';

  @override
  String get libraryClearSubtitle => 'Remove all scanned tracks';

  @override
  String get libraryClearConfirmTitle => 'Clear Library';

  @override
  String get libraryClearConfirmMessage =>
      'This will remove all scanned tracks from your library. Your actual music files will not be deleted.';

  @override
  String get libraryAbout => 'About Local Library';

  @override
  String get libraryAboutDescription =>
      'Scans your existing music collection to detect duplicates when downloading. Supports FLAC, M4A, MP3, Opus, and OGG formats. Metadata is read from file tags when available.';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return 'Last scanned: $time';
  }

  @override
  String get libraryLastScannedNever => 'Never';

  @override
  String get libraryScanning => 'Scanning...';

  @override
  String get libraryScanFinalizing => 'Finalizing library...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$progress% of $total files';
  }

  @override
  String get libraryInLibrary => 'In Library';

  @override
  String libraryRemovedMissingFiles(int count) {
    return 'Removed $count missing files from library';
  }

  @override
  String get libraryCleared => 'Library cleared';

  @override
  String get libraryStorageAccessRequired => 'Storage Access Required';

  @override
  String get libraryStorageAccessMessage =>
      'SpotiFLAC needs storage access to scan your music library. Please grant permission in settings.';

  @override
  String get libraryFolderNotExist => 'Selected folder does not exist';

  @override
  String get librarySourceDownloaded => 'Downloaded';

  @override
  String get librarySourceLocal => 'Local';

  @override
  String get libraryFilterAll => 'All';

  @override
  String get libraryFilterDownloaded => 'Downloaded';

  @override
  String get libraryFilterLocal => 'Local';

  @override
  String get libraryFilterTitle => 'Filters';

  @override
  String get libraryFilterReset => 'Reset';

  @override
  String get libraryFilterApply => 'Apply';

  @override
  String get libraryFilterSource => 'Source';

  @override
  String get libraryFilterQuality => 'Quality';

  @override
  String get libraryFilterQualityHiRes => 'Hi-Res (24bit)';

  @override
  String get libraryFilterQualityCD => 'CD (16bit)';

  @override
  String get libraryFilterQualityLossy => 'Lossy';

  @override
  String get libraryFilterFormat => 'Format';

  @override
  String get libraryFilterMetadata => 'Metadata';

  @override
  String get libraryFilterMetadataComplete => 'Complete metadata';

  @override
  String get libraryFilterMetadataMissingAny => 'Missing any metadata';

  @override
  String get libraryFilterMetadataMissingYear => 'Missing year';

  @override
  String get libraryFilterMetadataMissingGenre => 'Missing genre';

  @override
  String get libraryFilterMetadataMissingAlbumArtist => 'Missing album artist';

  @override
  String get libraryFilterSort => 'Sort';

  @override
  String get libraryFilterSortLatest => 'Latest';

  @override
  String get libraryFilterSortOldest => 'Oldest';

  @override
  String get libraryFilterSortAlbumAsc => 'Album (A-Z)';

  @override
  String get libraryFilterSortAlbumDesc => 'Album (Z-A)';

  @override
  String get libraryFilterSortGenreAsc => 'Genre (A-Z)';

  @override
  String get libraryFilterSortGenreDesc => 'Genre (Z-A)';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => 'Welcome to SpotiFLAC!';

  @override
  String get tutorialWelcomeDesc =>
      'Let\'s learn how to download your favorite music in lossless quality. This quick tutorial will show you the basics.';

  @override
  String get tutorialWelcomeTip1 =>
      'Download music from Spotify, Deezer, or paste any supported URL';

  @override
  String get tutorialWelcomeTip2 =>
      'Get FLAC quality audio from installed download extensions';

  @override
  String get tutorialWelcomeTip3 =>
      'Automatic metadata, cover art, and lyrics embedding';

  @override
  String get tutorialSearchTitle => 'Finding Music';

  @override
  String get tutorialSearchDesc =>
      'There are two easy ways to find music you want to download.';

  @override
  String get tutorialDownloadTitle => 'Downloading Music';

  @override
  String get tutorialDownloadDesc =>
      'Downloading music is simple and fast. Here\'s how it works.';

  @override
  String get tutorialLibraryTitle => 'Your Library';

  @override
  String get tutorialLibraryDesc =>
      'All your downloaded music is organized in the Library tab.';

  @override
  String get tutorialLibraryTip1 =>
      'View download progress and queue in the Library tab';

  @override
  String get tutorialLibraryTip2 =>
      'Tap any track to play it with your music player';

  @override
  String get tutorialLibraryTip3 =>
      'Switch between list and grid view for better browsing';

  @override
  String get tutorialExtensionsTitle => 'Extensions';

  @override
  String get tutorialExtensionsDesc =>
      'Extend the app\'s capabilities with community extensions.';

  @override
  String get tutorialExtensionsTip1 =>
      'Browse the Repo tab to discover useful extensions';

  @override
  String get tutorialExtensionsTip2 =>
      'Add new download providers or search sources';

  @override
  String get tutorialExtensionsTip3 =>
      'Get lyrics, enhanced metadata, and more features';

  @override
  String get tutorialSettingsTitle => 'Customize Your Experience';

  @override
  String get tutorialSettingsDesc =>
      'Personalize the app in Settings to match your preferences.';

  @override
  String get tutorialSettingsTip1 =>
      'Change download location and folder organization';

  @override
  String get tutorialSettingsTip2 =>
      'Set default audio quality and format preferences';

  @override
  String get tutorialSettingsTip3 => 'Customize app theme and appearance';

  @override
  String get tutorialReadyMessage =>
      'You\'re all set! Start downloading your favorite music now.';

  @override
  String get libraryForceFullScan => 'Force Full Scan';

  @override
  String get libraryForceFullScanSubtitle => 'Rescan all files, ignoring cache';

  @override
  String get cleanupOrphanedDownloads => 'Cleanup Orphaned Downloads';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      'Remove history entries for files that no longer exist';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return 'Removed $count orphaned entries from history';
  }

  @override
  String get cleanupOrphanedDownloadsNone => 'No orphaned entries found';

  @override
  String get cacheTitle => 'Storage & Cache';

  @override
  String get cacheSummaryTitle => 'Cache overview';

  @override
  String get cacheSummarySubtitle =>
      'Clearing cache will not remove downloaded music files.';

  @override
  String cacheEstimatedTotal(String size) {
    return 'Estimated cache usage: $size';
  }

  @override
  String get cacheSectionStorage => 'Cached Data';

  @override
  String get cacheSectionMaintenance => 'Maintenance';

  @override
  String get cacheAppDirectory => 'App cache directory';

  @override
  String get cacheAppDirectoryDesc =>
      'HTTP responses, WebView data, and other temporary app data.';

  @override
  String get cacheTempDirectory => 'Temporary directory';

  @override
  String get cacheTempDirectoryDesc =>
      'Temporary files from downloads and audio conversion.';

  @override
  String get cacheCoverImage => 'Cover image cache';

  @override
  String get cacheCoverImageDesc =>
      'Downloaded album and track cover art. Will re-download when viewed.';

  @override
  String get cacheLibraryCover => 'Library cover cache';

  @override
  String get cacheLibraryCoverDesc =>
      'Cover art extracted from local music files. Will re-extract on next scan.';

  @override
  String get libraryPlaybackNormalization => 'Volume normalization';

  @override
  String get libraryPlaybackNormalizationSubtitle =>
      'Even out loudness between tracks using their ReplayGain or R128 tags, when present';

  @override
  String get cacheAudioAnalysis => 'Audio analysis cache';

  @override
  String get cacheAudioAnalysisDesc =>
      'Saved spectrograms and analysis results. Will re-analyze on next open.';

  @override
  String get cacheExploreFeed => 'Explore feed cache';

  @override
  String get cacheExploreFeedDesc =>
      'Explore tab content (new releases, trending). Will refresh on next visit.';

  @override
  String get cacheTrackLookup => 'Track lookup cache';

  @override
  String get cacheTrackLookupDesc =>
      'Spotify/Deezer track ID lookups. Clearing may slow next few searches.';

  @override
  String get cacheCleanupUnusedDesc =>
      'Remove orphaned download history and library entries for missing files.';

  @override
  String get cacheNoData => 'No cached data';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$size in $count files';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count entries';
  }

  @override
  String cacheClearSuccess(String target) {
    return 'Cleared: $target';
  }

  @override
  String get cacheClearConfirmTitle => 'Clear cache?';

  @override
  String cacheClearConfirmMessage(String target) {
    return 'This will clear cached data for $target. Downloaded music files will not be deleted.';
  }

  @override
  String get cacheClearAllConfirmTitle => 'Clear all cache?';

  @override
  String get cacheClearAllConfirmMessage =>
      'This will clear all cache categories on this page. Downloaded music files will not be deleted.';

  @override
  String get cacheClearAll => 'Clear all cache';

  @override
  String get cacheCleanupUnused => 'Cleanup unused data';

  @override
  String get cacheCleanupUnusedSubtitle =>
      'Remove orphaned download history and missing library entries';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return 'Cleanup completed: $downloadCount orphaned downloads, $libraryCount missing library entries';
  }

  @override
  String get cacheRefreshStats => 'Refresh stats';

  @override
  String get trackSaveCoverArt => 'Save Cover Art';

  @override
  String get trackSaveLyrics => 'Save Lyrics (.lrc)';

  @override
  String get trackSaveLyricsProgress => 'Saving lyrics...';

  @override
  String get trackReEnrich => 'Re-enrich';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Search metadata online and embed into file';

  @override
  String get trackReEnrichFieldCover => 'Cover Art';

  @override
  String get trackReEnrichFieldLyrics => 'Lyrics';

  @override
  String get trackReEnrichFieldBasicTags => 'Album, Album Artist';

  @override
  String get trackReEnrichFieldTrackInfo => 'Track & Disc Number';

  @override
  String get trackReEnrichFieldReleaseInfo => 'Date & ISRC';

  @override
  String get trackReEnrichFieldExtra => 'Genre, Label, Copyright';

  @override
  String get trackReEnrichSelectAll => 'Select All';

  @override
  String get trackEditMetadata => 'Edit Metadata';

  @override
  String trackCoverSaved(String fileName) {
    return 'Cover art saved to $fileName';
  }

  @override
  String get trackCoverNoSource => 'No cover art source available';

  @override
  String trackLyricsSaved(String fileName) {
    return 'Lyrics saved to $fileName';
  }

  @override
  String get trackReEnrichProgress => 'Re-enriching metadata...';

  @override
  String get trackReEnrichSearching => 'Searching metadata online...';

  @override
  String get trackReEnrichSuccess => 'Metadata re-enriched successfully';

  @override
  String get trackReEnrichFfmpegFailed => 'FFmpeg metadata embed failed';

  @override
  String get queueFlacAction => 'Queue FLAC';

  @override
  String queueFlacConfirmMessage(int count) {
    return 'Search online matches for the selected tracks and queue FLAC downloads.\n\nExisting files will not be modified or deleted.\n\nOnly high-confidence matches are queued automatically.\n\n$count selected';
  }

  @override
  String get queueFlacNoReliableMatches =>
      'No reliable online matches found for the selection';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return 'Added $addedCount tracks to queue, skipped $skippedCount';
  }

  @override
  String trackSaveFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get trackConvertFormat => 'Convert Format';

  @override
  String get trackConvertTitle => 'Convert Audio';

  @override
  String get trackConvertTargetFormat => 'Target Format';

  @override
  String get trackConvertBitrate => 'Bitrate';

  @override
  String get trackConvertKeepOriginal => 'Keep original file';

  @override
  String get trackConvertKeepOriginalDescription =>
      'Add the converted file as a separate library entry';

  @override
  String get trackConvertConfirmTitle => 'Confirm Conversion';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return 'Convert from $sourceFormat to $targetFormat at $bitrate?\n\nThe original file will be deleted after conversion.';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Convert from $sourceFormat to $targetFormat? (Lossless — no quality loss)\n\nThe original file will be deleted after conversion.';
  }

  @override
  String trackConvertConfirmKeepOriginal(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Convert from $sourceFormat to $targetFormat?\n\nThe original file will be kept and the converted file will be added as a separate library entry.';
  }

  @override
  String get trackConvertLosslessHint =>
      'Lossless conversion — no quality loss';

  @override
  String get trackConvertConverting => 'Converting audio...';

  @override
  String trackConvertSuccess(String format) {
    return 'Converted to $format successfully';
  }

  @override
  String get trackConvertFailed => 'Conversion failed';

  @override
  String get cueSplitTitle => 'Split CUE Sheet';

  @override
  String cueSplitAlbum(String album) {
    return 'Album: $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return 'Artist: $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count tracks';
  }

  @override
  String get cueSplitConfirmTitle => 'Split CUE Album';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return 'Split \"$album\" into $count individual FLAC files?\n\nFiles will be saved to the same directory.';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'Splitting CUE sheet... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return 'Split into $count tracks successfully';
  }

  @override
  String get cueSplitFailed => 'CUE split failed';

  @override
  String get cueSplitNoAudioFile => 'Audio file not found for this CUE sheet';

  @override
  String get cueSplitButton => 'Split into Tracks';

  @override
  String get actionCreate => 'Create';

  @override
  String get collectionFoldersTitle => 'My folders';

  @override
  String get collectionWishlist => 'Wishlist';

  @override
  String get collectionLoved => 'Loved';

  @override
  String get collectionFavoriteArtists => 'Favorite Artists';

  @override
  String get collectionPlaylist => 'Playlist';

  @override
  String get collectionAddToPlaylist => 'Add to playlist';

  @override
  String get collectionCreatePlaylist => 'Create playlist';

  @override
  String get collectionNoPlaylistsYet => 'No playlists yet';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String collectionArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artists',
      one: '1 artist',
    );
    return '$_temp0';
  }

  @override
  String collectionAddedToPlaylist(String playlistName) {
    return 'Added to \"$playlistName\"';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return 'Already in \"$playlistName\"';
  }

  @override
  String get collectionPlaylistNameHint => 'Playlist name';

  @override
  String get collectionPlaylistNameRequired => 'Playlist name is required';

  @override
  String get collectionRenamePlaylist => 'Rename playlist';

  @override
  String get collectionDeletePlaylist => 'Delete playlist';

  @override
  String get collectionPlaylistRenamed => 'Playlist renamed';

  @override
  String get collectionWishlistEmptyTitle => 'Wishlist is empty';

  @override
  String get collectionWishlistEmptySubtitle =>
      'Tap + on tracks to save what you want to download later';

  @override
  String get collectionLovedEmptyTitle => 'Loved folder is empty';

  @override
  String get collectionLovedEmptySubtitle =>
      'Tap love on tracks to keep your favorites';

  @override
  String get collectionFavoriteArtistsEmptyTitle => 'No favorite artists yet';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      'Tap the heart on an artist page to keep them here';

  @override
  String get collectionPlaylistEmptyTitle => 'Playlist is empty';

  @override
  String get collectionPlaylistEmptySubtitle =>
      'Long-press + on any track to add it here';

  @override
  String get collectionRemoveFromPlaylist => 'Remove from playlist';

  @override
  String get collectionRemoveFromFolder => 'Remove from folder';

  @override
  String collectionAddedToLoved(String trackName) {
    return '\"$trackName\" added to Loved';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\"$trackName\" removed from Loved';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '\"$trackName\" added to Wishlist';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '\"$trackName\" removed from Wishlist';
  }

  @override
  String collectionAddedToFavoriteArtists(String artistName) {
    return '\"$artistName\" added to Favorite Artists';
  }

  @override
  String collectionRemovedFromFavoriteArtists(String artistName) {
    return '\"$artistName\" removed from Favorite Artists';
  }

  @override
  String get trackOptionAddToLoved => 'Add to Loved';

  @override
  String get trackOptionRemoveFromLoved => 'Remove from Loved';

  @override
  String get trackOptionAddToWishlist => 'Add to Wishlist';

  @override
  String get trackOptionRemoveFromWishlist => 'Remove from Wishlist';

  @override
  String get artistOptionAddToFavorites => 'Add to Favorite Artists';

  @override
  String get artistOptionRemoveFromFavorites => 'Remove from Favorite Artists';

  @override
  String get collectionPlaylistChangeCover => 'Change cover image';

  @override
  String get collectionPlaylistRemoveCover => 'Remove cover image';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Share $count $_temp0';
  }

  @override
  String get selectionShareNoFiles => 'No shareable files found';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0';
  }

  @override
  String get selectionConvertNoConvertible => 'No convertible tracks selected';

  @override
  String get selectionBatchConvertConfirmTitle => 'Batch Convert';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format at $bitrate?\n\nOriginal files will be deleted after conversion.';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format? (Lossless — no quality loss)\n\nOriginal files will be deleted after conversion.';
  }

  @override
  String selectionBatchConvertConfirmKeepOriginal(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format?\n\nOriginal files will be kept and converted files will be added as separate library entries.';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return 'Converted $success of $total tracks to $format';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count downloaded';
  }

  @override
  String get downloadUseAlbumArtistForFoldersAlbumSubtitle =>
      'Folder named after Album Artist tag';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      'Folder named after Track Artist tag';

  @override
  String get lyricsProvidersTitle => 'Lyrics Provider Priority';

  @override
  String get lyricsProvidersDescription =>
      'Enable, disable and reorder lyrics sources. Providers are tried top-to-bottom until lyrics are found.';

  @override
  String get lyricsProvidersInfoText =>
      'Extension lyrics providers run before built-in lyrics providers. At least one provider must remain enabled.';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return 'Enabled ($count)';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return 'Disabled ($count)';
  }

  @override
  String get lyricsProvidersAtLeastOne =>
      'At least one provider must remain enabled';

  @override
  String get lyricsProvidersSaved => 'Lyrics provider priority saved';

  @override
  String get lyricsProvidersDiscardContent =>
      'You have unsaved changes that will be lost.';

  @override
  String get lyricsProviderLrclibDesc => 'Open-source synced lyrics database';

  @override
  String get lyricsProviderNeteaseDesc =>
      'NetEase Cloud Music (good for Asian songs)';

  @override
  String get lyricsProviderMusixmatchDesc =>
      'Largest lyrics database (multi-language)';

  @override
  String get lyricsProviderAppleMusicDesc =>
      'Word-by-word synced lyrics (via proxy)';

  @override
  String get lyricsProviderQqMusicDesc =>
      'QQ Music (good for Chinese songs, via proxy)';

  @override
  String get lyricsProviderLyricsPlusDesc =>
      'Word-by-word karaoke lyrics (Apple/Musixmatch/Spotify/QQ, via proxy)';

  @override
  String get lyricsProviderExtensionDesc => 'Extension provider';

  @override
  String get safMigrationTitle => 'Storage Update Required';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC now uses Android Storage Access Framework (SAF) for downloads. This fixes \"permission denied\" errors on Android 10+.';

  @override
  String get safMigrationMessage2 =>
      'Please select your download folder again to switch to the new storage system.';

  @override
  String get safMigrationSuccess => 'Download folder updated to SAF mode';

  @override
  String get settingsDonate => 'Support Development';

  @override
  String get settingsDonateSubtitle => 'Buy the developer a coffee';

  @override
  String get settingsBackup => 'Backup & Restore';

  @override
  String get settingsBackupSubtitle =>
      'Move your library, history and settings to a new device';

  @override
  String get backupTitle => 'Backup & Restore';

  @override
  String get backupExportSectionTitle => 'Create backup';

  @override
  String get backupExportSectionDescription =>
      'Save your settings, download history, liked tracks, wishlist, favorite artists and playlists into a single file you can keep or move to another phone.';

  @override
  String get backupExportButton => 'Create backup file';

  @override
  String get backupImportSectionTitle => 'Restore backup';

  @override
  String get backupImportSectionDescription =>
      'Pick a backup file to restore your data. This replaces the current settings, history and library on this device.';

  @override
  String get backupImportButton => 'Choose backup file';

  @override
  String get backupCreated => 'Backup created';

  @override
  String get backupCreateFailed => 'Failed to create backup';

  @override
  String get backupRestoreConfirmTitle => 'Restore this backup?';

  @override
  String get backupRestoreConfirmMessage =>
      'This will replace your current settings, download history, liked tracks, wishlist and playlists with the contents of the backup. This cannot be undone.';

  @override
  String get backupRestoreConfirmButton => 'Restore';

  @override
  String get backupRestored => 'Backup restored successfully';

  @override
  String get backupRestoreFailed => 'Failed to restore backup';

  @override
  String get backupInvalidFile => 'This file is not a valid SpotiFLAC backup';

  @override
  String get backupRestoreRestartHint =>
      'Restart the app to make sure every change is applied.';

  @override
  String get backupContentsTitle => 'Backup contents';

  @override
  String get backupContentsSettings => 'App settings';

  @override
  String backupContentsHistory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$count history $_temp0';
  }

  @override
  String backupContentsLiked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count liked $_temp0';
  }

  @override
  String backupContentsWishlist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count wishlist $_temp0';
  }

  @override
  String backupContentsPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String backupContentsArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favorite artists',
      one: '1 favorite artist',
    );
    return '$_temp0';
  }

  @override
  String backupContentsExtensions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count extensions',
      one: '1 extension',
    );
    return '$_temp0';
  }

  @override
  String get backupIncludeSecrets => 'Include extension credentials';

  @override
  String get backupIncludeSecretsDescription =>
      'Tokens and API keys from extensions will be saved into the backup file. Keep the file private. When off, you re-enter them after restoring.';

  @override
  String backupExtensionsRestoreFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'extensions',
      one: 'extension',
    );
    return '$count $_temp0 could not be reinstalled. Install them manually from the repo.';
  }

  @override
  String get tooltipLoveAll => 'Love All';

  @override
  String get tooltipAddToPlaylist => 'Add to Playlist';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return 'Removed $count tracks from Loved';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return 'Added $count tracks to Loved';
  }

  @override
  String get dialogDownloadAllTitle => 'Download All';

  @override
  String dialogDownloadAllMessage(int count) {
    return 'Download $count tracks?';
  }

  @override
  String get homeSkipAlreadyDownloaded => 'Skip already downloaded songs';

  @override
  String get homeGoToAlbum => 'Go to Album';

  @override
  String get homeAlbumInfoUnavailable => 'Album info not available';

  @override
  String get snackbarLoadingCueSheet => 'Loading CUE sheet...';

  @override
  String get snackbarMetadataSaved => 'Metadata saved successfully';

  @override
  String get snackbarFailedToEmbedLyrics => 'Failed to embed lyrics';

  @override
  String get snackbarFailedToWriteStorage => 'Failed to write back to storage';

  @override
  String snackbarError(String error) {
    return 'Error: $error';
  }

  @override
  String get snackbarNoActionDefined => 'No action defined for this button';

  @override
  String get noTracksFoundForAlbum => 'No tracks found for this album';

  @override
  String get downloadLocationSubtitle =>
      'Choose where to save your downloaded tracks';

  @override
  String get storageModeAppFolder => 'App Folder (Recommended)';

  @override
  String get storageModeAppFolderSubtitle =>
      'Saves to Music/SpotiFLAC by default';

  @override
  String get storageModeSaf => 'Custom Folder (SAF)';

  @override
  String get storageModeSafSubtitle => 'Pick any folder, including SD card';

  @override
  String get downloadFolderAccessLostTitle => 'Download folder access lost';

  @override
  String get downloadFolderAccessLostSubtitle =>
      'Downloads will fail until you re-select the folder';

  @override
  String get downloadFolderReselect => 'Re-select folder';

  @override
  String get downloadErrorSafPermissionLost =>
      'SAF permission invalid or revoked. Please reconfigure download location in Settings.';

  @override
  String get downloadErrorFolderAccessLost =>
      'Download folder access lost. Please re-select your download folder in Settings.';

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
    return 'Use $artist, $title, $album, $track, $year, $date, $disc as placeholders.';
  }

  @override
  String get downloadFilenameInsertTag => 'Tap to insert tag:';

  @override
  String get downloadSeparateSinglesEnabled =>
      'Singles and EPs saved in a separate folder';

  @override
  String get downloadSeparateSinglesDisabled =>
      'Singles and albums saved in the same folder';

  @override
  String get downloadArtistNameFilters => 'Artist Name Filters';

  @override
  String get downloadCreatePlaylistSourceFolder => 'Playlist Source Folder';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      'A subfolder is created for each playlist';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      'All tracks saved directly to download folder';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant =>
      'Handled by folder organization setting';

  @override
  String get downloadSongLinkRegion => 'SongLink Region';

  @override
  String get downloadNetworkCompatibilityMode => 'Network Compatibility Mode';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Using legacy TLS settings for older networks';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Using standard network settings';

  @override
  String get downloadAllowLocalNetwork => 'Allow Local Network Access';

  @override
  String get downloadAllowLocalNetworkEnabled =>
      'Requests to local/private addresses are allowed (for local proxy or custom DNS)';

  @override
  String get downloadAllowLocalNetworkDisabled =>
      'Local/private addresses are blocked for security';

  @override
  String get downloadSelectServiceToEnable =>
      'Select a provider with quality options to enable this option';

  @override
  String get downloadEmbedLyricsDisabled => 'Enable metadata embedding first';

  @override
  String get downloadNeteaseIncludeTranslation =>
      'Netease: Include Translation';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Chinese translation lines included';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Original lyrics only';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease: Include Romanization';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled =>
      'Romanization lines included';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled => 'No romanization';

  @override
  String get downloadAppleQqMultiPerson => 'Apple / QQ: Multi-Person Lyrics';

  @override
  String get downloadAppleQqMultiPersonEnabled =>
      'Speaker labels included for duets and group tracks';

  @override
  String get downloadAppleQqMultiPersonDisabled =>
      'Standard lyrics without speaker labels';

  @override
  String get downloadAppleElrcWordSync => 'Apple Music eLRC Word Sync';

  @override
  String get downloadAppleElrcWordSyncEnabled =>
      'Raw word-by-word timestamps preserved';

  @override
  String get downloadAppleElrcWordSyncDisabled =>
      'Safer line-by-line Apple Music lyrics';

  @override
  String get downloadMusixmatchLanguage => 'Musixmatch Language';

  @override
  String get downloadMusixmatchLanguageAuto => 'Auto (original language)';

  @override
  String get downloadFilterContributing => 'Filter Contributing Artists';

  @override
  String get downloadFilterContributingEnabled =>
      'Contributing artists removed from Album Artist folder name';

  @override
  String get downloadFilterContributingDisabled =>
      'Full Album Artist string used';

  @override
  String get downloadProvidersNoneEnabled => 'No providers enabled';

  @override
  String get downloadMusixmatchLanguageCode => 'Language code';

  @override
  String get downloadMusixmatchLanguageHint => 'e.g. en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Enter a BCP-47 language code (e.g. en, de, ja) to request translated lyrics from Musixmatch.';

  @override
  String get downloadMusixmatchAuto => 'Auto';

  @override
  String get downloadNetworkAnySubtitle => 'Use WiFi or mobile data';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Downloads pause when on mobile data';

  @override
  String get downloadSongLinkRegionDesc =>
      'Region used when resolving track links via SongLink. Choose the country where your streaming services are available.';

  @override
  String get snackbarUnsupportedAudioFormat => 'Unsupported audio format';

  @override
  String get cacheRefresh => 'Refresh';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    String _temp1 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Download $trackCount $_temp0 from $playlistCount $_temp1?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Download $count $_temp0';
  }

  @override
  String get bulkDownloadSelectPlaylists => 'Select playlists to download';

  @override
  String get snackbarSelectedPlaylistsEmpty =>
      'Selected playlists have no tracks';

  @override
  String playlistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get editMetadataAutoFill => 'Auto-fill from online';

  @override
  String get editMetadataAutoFillDesc =>
      'Select fields to fill automatically from online metadata';

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
  String get editMetadataAutoFillFetch => 'Fetch & Fill';

  @override
  String get editMetadataAutoFillSearching => 'Searching online...';

  @override
  String get editMetadataAutoFillNoResults =>
      'No matching metadata found online';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fields',
      one: 'field',
    );
    return 'Filled $count $_temp0 from online metadata';
  }

  @override
  String get editMetadataAutoFillNoneSelected =>
      'Select at least one field to auto-fill';

  @override
  String get editMetadataFieldTitle => 'Title';

  @override
  String get editMetadataFieldArtist => 'Artist';

  @override
  String get editMetadataFieldAlbum => 'Album';

  @override
  String get editMetadataFieldAlbumArtist => 'Album Artist';

  @override
  String get editMetadataFieldDate => 'Date';

  @override
  String get editMetadataFieldTrackNum => 'Track #';

  @override
  String get editMetadataFieldDiscNum => 'Disc #';

  @override
  String get editMetadataFieldGenre => 'Genre';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => 'Label';

  @override
  String get editMetadataFieldCopyright => 'Copyright';

  @override
  String get editMetadataFieldCover => 'Cover Art';

  @override
  String get editMetadataSelectAll => 'All';

  @override
  String get editMetadataSelectEmpty => 'Empty only';

  @override
  String queueDownloadingCount(int count) {
    return 'Downloading ($count)';
  }

  @override
  String get queueFilteringIndicator => 'Filtering...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String queueAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyAlbums => 'No album downloads';

  @override
  String get queueEmptyAlbumsSubtitle =>
      'Download multiple tracks from an album to see them here';

  @override
  String get queueEmptySingles => 'No single downloads';

  @override
  String get queueEmptySinglesSubtitle =>
      'Single track downloads will appear here';

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
  String get queueEmptyHistory => 'No download history';

  @override
  String get queueEmptyHistorySubtitle => 'Downloaded tracks will appear here';

  @override
  String get selectionAllPlaylistsSelected => 'All playlists selected';

  @override
  String get selectionTapPlaylistsToSelect => 'Tap playlists to select';

  @override
  String get selectionSelectPlaylistsToDelete => 'Select playlists to delete';

  @override
  String get audioAnalysisTitle => 'Audio Quality Analysis';

  @override
  String get audioAnalysisDescription =>
      'Verify lossless quality with spectrum analysis';

  @override
  String get audioAnalysisAnalyzing => 'Analyzing audio...';

  @override
  String get audioAnalysisSampleRate => 'Sample Rate';

  @override
  String get audioAnalysisCodec => 'Codec';

  @override
  String get audioAnalysisContainer => 'Container';

  @override
  String get audioAnalysisDecodedFormat => 'Decoded Format';

  @override
  String get audioAnalysisBitDepth => 'Bit Depth';

  @override
  String get audioAnalysisChannels => 'Channels';

  @override
  String get audioAnalysisDuration => 'Duration';

  @override
  String get audioAnalysisNyquist => 'Nyquist';

  @override
  String get audioAnalysisFileSize => 'Size';

  @override
  String get audioAnalysisDynamicRange => 'Dynamic Range';

  @override
  String get audioAnalysisPeak => 'Peak';

  @override
  String get audioAnalysisRms => 'RMS';

  @override
  String get audioAnalysisLufs => 'LUFS';

  @override
  String get audioAnalysisTruePeak => 'True Peak';

  @override
  String get audioAnalysisClipping => 'Clipping';

  @override
  String get audioAnalysisNoClipping => 'No clipping';

  @override
  String get audioAnalysisSpectralCutoff => 'Spectral Cutoff';

  @override
  String get audioAnalysisCutoffNotDetected => 'Not detected';

  @override
  String get audioAnalysisChannelStats => 'Per-channel Stats';

  @override
  String get audioAnalysisSamples => 'Samples';

  @override
  String get audioAnalysisRescan => 'Re-analyze';

  @override
  String get audioAnalysisRescanning => 'Re-analyzing audio...';

  @override
  String get extensionsHomeFeedProvider => 'Home Feed Provider';

  @override
  String get extensionsHomeFeedDescription =>
      'Choose which extension provides the home feed on the main screen';

  @override
  String get extensionsHomeFeedAuto => 'Auto';

  @override
  String get extensionsHomeFeedAutoSubtitle =>
      'Automatically select the best available';

  @override
  String get extensionsHomeFeedOff => 'Off';

  @override
  String get extensionsHomeFeedOffSubtitle =>
      'Do not show the home feed on the main screen';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return 'Use $extensionName home feed';
  }

  @override
  String get extensionsNoHomeFeedExtensions => 'No extensions with home feed';

  @override
  String get cancelDownloadTitle => 'Cancel download?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'This will cancel the active download for \"$trackName\".';
  }

  @override
  String get cancelDownloadKeep => 'Keep';

  @override
  String get queueCancelledTitle => 'Download cancelled';

  @override
  String get queueCancelledMessage =>
      'This download was cancelled. Retry it or remove it from the queue.';

  @override
  String get metadataSaveFailedFfmpeg => 'Failed to save metadata via FFmpeg';

  @override
  String get metadataSaveFailedStorage =>
      'Failed to write metadata back to storage';

  @override
  String snackbarFolderPickerFailed(String error) {
    return 'Failed to open folder picker: $error';
  }

  @override
  String notifDownloadingTrack(String trackName) {
    return 'Downloading $trackName';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return 'Finalizing $trackName';
  }

  @override
  String get notifEmbeddingMetadata => 'Embedding metadata...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return 'Already in Library ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => 'Already in Library';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return 'Download Complete ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => 'Download Complete';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return 'Downloads Finished ($completed done, $failed failed)';
  }

  @override
  String get notifVerificationRequiredTitle => 'Verification required';

  @override
  String get notifVerificationRequiredBody =>
      'Open the app to complete verification and resume downloads';

  @override
  String get notifAllDownloadsComplete => 'All Downloads Complete';

  @override
  String notifTracksDownloadedSuccess(int count) {
    return '$count tracks downloaded successfully';
  }

  @override
  String notifDownloadsFinishedBody(int completed, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      completed,
      locale: localeName,
      other: '$completed tracks downloaded',
      one: '1 track downloaded',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed failed',
      one: '1 failed',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get notifDownloadsCanceledTitle => 'Downloads canceled';

  @override
  String notifDownloadsCanceledBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count downloads canceled by user',
      one: '1 download canceled by user',
    );
    return '$_temp0';
  }

  @override
  String get notifScanningLibrary => 'Scanning local library';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total files • $percentage%';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned files scanned • $percentage%';
  }

  @override
  String get notifLibraryScanComplete => 'Library scan complete';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count tracks indexed';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count excluded';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count errors';
  }

  @override
  String get notifLibraryScanFailed => 'Library scan failed';

  @override
  String get notifLibraryScanCancelled => 'Library scan cancelled';

  @override
  String get notifLibraryScanStopped => 'Scan stopped before completion.';

  @override
  String notifDownloadingUpdate(String version) {
    return 'Downloading SpotiFLAC Mobile v$version';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total MB • $percentage%';
  }

  @override
  String get notifUpdateReady => 'Update Ready';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC Mobile v$version downloaded. Tap to install.';
  }

  @override
  String get notifUpdateFailed => 'Update Failed';

  @override
  String get notifUpdateFailedBody =>
      'Could not download update. Try again later.';

  @override
  String get searchTracks => 'Tracks';

  @override
  String get homeSearchHintDefault => 'Paste supported URL or search...';

  @override
  String homeSearchHintProvider(String providerName) {
    return 'Search with $providerName...';
  }

  @override
  String get homeImportCsvTooltip => 'Import playlist (CSV, M3U)';

  @override
  String get homeChangeSearchProviderTooltip => 'Change search provider';

  @override
  String get actionPaste => 'Paste';

  @override
  String get tutorialSearchHint => 'Paste or search...';

  @override
  String get tutorialDownloadCompletedSemantics => 'Download completed';

  @override
  String get tutorialDownloadInProgressSemantics => 'Download in progress';

  @override
  String get tutorialStartDownloadSemantics => 'Start download';

  @override
  String get optionsEmbedMetadata => 'Embed Metadata';

  @override
  String get optionsEmbedMetadataSubtitleOn =>
      'Write metadata, cover art, and embedded lyrics to files';

  @override
  String get optionsEmbedMetadataSubtitleOff =>
      'Disabled (advanced): skip all metadata embedding';

  @override
  String get trackCoverNoEmbeddedArt => 'No embedded album art found';

  @override
  String get trackCoverReplace => 'Replace Cover';

  @override
  String get trackCoverPick => 'Pick Cover';

  @override
  String get trackCoverClearSelected => 'Clear selected cover';

  @override
  String get trackCoverCurrent => 'Current cover';

  @override
  String get trackCoverSelected => 'Selected cover';

  @override
  String get trackCoverReplaceNotice =>
      'The selected cover will replace the current embedded cover when you tap Save.';

  @override
  String get trackCoverResolution => 'Cover resolution';

  @override
  String get trackCoverResolutionHint =>
      'Sets the longest edge when saved. Enlarging does not add image detail.';

  @override
  String get trackCoverResizeFailed =>
      'The cover image could not be resized. Please try another size or image.';

  @override
  String get actionStop => 'Stop';

  @override
  String get queueFinalizingDownload => 'Finalizing download';

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
  String get queueDownloadedFileMissing => 'Downloaded file missing';

  @override
  String get queueDownloadCompleted => 'Download completed';

  @override
  String get queueRateLimitTitle => 'Service rate limited';

  @override
  String get queueRateLimitMessage =>
      'This track may still be available. Wait a few minutes, reduce parallel downloads, then retry.';

  @override
  String appearanceSelectAccentColor(String hex) {
    return 'Select accent color $hex';
  }

  @override
  String get logAutoScrollOn => 'Auto-scroll ON';

  @override
  String get logAutoScrollOff => 'Auto-scroll OFF';

  @override
  String get logCopyLogs => 'Copy logs';

  @override
  String get logClearSearch => 'Clear search';

  @override
  String get logIssueIspBlockingLabel => 'ISP BLOCKING DETECTED';

  @override
  String get logIssueIspBlockingDescription =>
      'Your ISP may be blocking access to download services';

  @override
  String get logIssueIspBlockingSuggestion =>
      'Try using a VPN or change DNS to 1.1.1.1 or 8.8.8.8';

  @override
  String get logIssueRateLimitedLabel => 'RATE LIMITED';

  @override
  String get logIssueRateLimitedDescription =>
      'Too many requests to the service';

  @override
  String get logIssueRateLimitedSuggestion =>
      'Wait a few minutes before trying again';

  @override
  String get logIssueNetworkErrorLabel => 'NETWORK ERROR';

  @override
  String get logIssueNetworkErrorDescription => 'Connection issues detected';

  @override
  String get logIssueNetworkErrorSuggestion => 'Check your internet connection';

  @override
  String get logIssueTrackNotFoundLabel => 'TRACK NOT FOUND';

  @override
  String get logIssueTrackNotFoundDescription =>
      'Some tracks could not be found on download services';

  @override
  String get logIssueTrackNotFoundSuggestion =>
      'The track may not be available in lossless quality';

  @override
  String get clickableLookingUpArtist => 'Looking up artist...';

  @override
  String clickableInformationUnavailable(String type) {
    return '$type information not available';
  }

  @override
  String get extensionDetailsTags => 'Tags';

  @override
  String get extensionDetailsInformation => 'Information';

  @override
  String get extensionUtilityFunctions => 'Utility Functions';

  @override
  String get actionDismiss => 'Dismiss';

  @override
  String get setupChangeFolderTooltip => 'Change folder';

  @override
  String a11yOpenTrackByArtist(String trackName, String artistName) {
    return 'Open track $trackName by $artistName';
  }

  @override
  String a11yOpenItem(String itemType, String name) {
    return 'Open $itemType $name';
  }

  @override
  String a11yOpenItemCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return 'Open $title, $count $_temp0';
  }

  @override
  String a11yOpenAlbumByArtistTrackCount(
    String albumName,
    String artistName,
    int trackCount,
  ) {
    return 'Open album $albumName by $artistName, $trackCount tracks';
  }

  @override
  String a11yTrackByArtist(String trackName, String artistName) {
    return '$trackName by $artistName';
  }

  @override
  String a11ySelectAlbum(String albumName) {
    return 'Select album $albumName';
  }

  @override
  String a11yOpenAlbum(String albumName) {
    return 'Open album $albumName';
  }

  @override
  String get settingsFiles => 'Files & Folders';

  @override
  String get settingsFilesSubtitle =>
      'Download location, filename, folder structure';

  @override
  String get settingsMetadata => 'Metadata';

  @override
  String get settingsMetadataSubtitle =>
      'Cover art, tags, ReplayGain, providers';

  @override
  String get settingsLyrics => 'Lyrics';

  @override
  String get settingsLyricsSubtitle =>
      'Embed, mode, providers, language options';

  @override
  String get settingsApp => 'App';

  @override
  String get settingsAppSubtitle => 'Updates, data, extension repo, debug';

  @override
  String get sectionMetadataProviders => 'Providers';

  @override
  String get sectionDuplicates => 'Duplicates';

  @override
  String get sectionLyricsProviderOptions => 'Provider Options';

  @override
  String get metadataProvidersTitle => 'Metadata Provider Priority';

  @override
  String get metadataProvidersSubtitle =>
      'Drag to set search and metadata source order';

  @override
  String get downloadDeduplication => 'Skip Duplicate Downloads';

  @override
  String get downloadDeduplicationEnabled =>
      'Already-downloaded tracks will be skipped';

  @override
  String get downloadDeduplicationWithQualityVariants =>
      'Existing files at the selected quality will be skipped';

  @override
  String get downloadDeduplicationDisabled =>
      'All tracks will be downloaded regardless of history';

  @override
  String get downloadQualityVariants => 'Allow different quality versions';

  @override
  String get downloadQualityVariantsDescription =>
      'Keep every quality version; add its measured quality to the filename only when the name is already used';

  @override
  String get trackOptionDownloadQualityVariant => 'Download another quality';

  @override
  String get downloadFallbackExtensions => 'Fallback Extensions';

  @override
  String get downloadFallbackExtensionsSubtitle =>
      'Choose which extensions can be used as fallback';

  @override
  String get editMetadataFieldDateHint => 'YYYY-MM-DD or YYYY';

  @override
  String get editMetadataFieldTrackTotal => 'Track Total';

  @override
  String get editMetadataFieldDiscTotal => 'Disc Total';

  @override
  String get editMetadataFieldComposer => 'Composer';

  @override
  String get editMetadataFieldComment => 'Comment';

  @override
  String get editMetadataAdvanced => 'Advanced';

  @override
  String get libraryFilterMetadataMissingTrackNumber => 'Missing track number';

  @override
  String get libraryFilterMetadataMissingDiscNumber => 'Missing disc number';

  @override
  String get libraryFilterMetadataMissingArtist => 'Missing artist';

  @override
  String get libraryFilterMetadataIncorrectIsrcFormat =>
      'Incorrect ISRC format';

  @override
  String get libraryFilterMetadataMissingIsrc => 'Missing ISRC';

  @override
  String get libraryFilterMetadataMissingLabel => 'Missing label';

  @override
  String collectionDeletePlaylistsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Delete $count $_temp0?';
  }

  @override
  String collectionPlaylistsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return '$count $_temp0 deleted';
  }

  @override
  String collectionAddedTracksToPlaylist(int count, String playlistName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Added $count $_temp0 to $playlistName';
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
      other: 'tracks',
      one: 'track',
    );
    return 'Added $count $_temp0 to $playlistName ($alreadyCount already in playlist)';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$count $_temp0';
  }

  @override
  String trackReEnrichSuccessWithFailures(
    int successCount,
    int total,
    int failedCount,
  ) {
    return 'Metadata re-enriched successfully ($successCount/$total) - Failed: $failedCount';
  }

  @override
  String selectionDeleteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Delete $count $_temp0';
  }

  @override
  String queueDownloadSpeedStatus(String speed) {
    return 'Downloading - $speed MB/s';
  }

  @override
  String get queueDownloadStarting => 'Starting...';

  @override
  String get queueCheckingDownloadSession => 'Checking download session...';

  @override
  String get queueResolvingDownloadMetadata => 'Resolving track metadata...';

  @override
  String get queueResolvingDownloadStream => 'Preparing audio stream...';

  @override
  String get queueWaitingForVerification => 'Waiting for verification...';

  @override
  String get queueResumingAfterVerification => 'Resuming after verification...';

  @override
  String get a11ySelectTrack => 'Select track';

  @override
  String get a11yDeselectTrack => 'Deselect track';

  @override
  String a11yPlayTrackByArtist(String trackName, String artistName) {
    return 'Play $trackName by $artistName';
  }

  @override
  String storeExtensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'extensions',
      one: 'extension',
    );
    return '$count $_temp0';
  }

  @override
  String storeRequiresVersion(String version) {
    return 'Requires v$version+';
  }

  @override
  String get actionGo => 'Go';

  @override
  String get logIssueSummary => 'Issue Summary';

  @override
  String logTotalErrors(int count) {
    return 'Total errors: $count';
  }

  @override
  String logAffectedDomains(String domains) {
    return 'Affected: $domains';
  }

  @override
  String get libraryScanCancelled => 'Scan cancelled';

  @override
  String get libraryScanCancelledSubtitle =>
      'You can retry the scan when ready.';

  @override
  String libraryDownloadsHistoryExcluded(int count) {
    return '$count from Downloads history (excluded from list)';
  }

  @override
  String get downloadNativeWorker => 'Native download worker';

  @override
  String get downloadNativeWorkerSubtitle =>
      'Android background service for extension downloads';

  @override
  String get extensionServiceStatus => 'Service Status';

  @override
  String get extensionServiceHealth => 'Service health';

  @override
  String extensionHealthChecksConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'checks',
      one: 'check',
    );
    return '$count $_temp0 configured';
  }

  @override
  String get extensionOauthConnectHint =>
      'Tap Connect to Spotify to fill this field.';

  @override
  String extensionLastChecked(String time) {
    return 'Last checked $time';
  }

  @override
  String get extensionRefreshStatus => 'Refresh status';

  @override
  String get extensionCustomUrlHandling => 'Custom URL Handling';

  @override
  String get extensionCustomUrlHandlingSubtitle =>
      'This extension can handle links from these sites';

  @override
  String get extensionCustomUrlHandlingShareHint =>
      'Share links from these sites to SpotiFLAC Mobile and this extension will handle them.';

  @override
  String extensionSettingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'settings',
      one: 'setting',
    );
    return '$count $_temp0';
  }

  @override
  String get extensionHealthOnline => 'Online';

  @override
  String get extensionHealthDegraded => 'Degraded';

  @override
  String get extensionHealthOffline => 'Offline';

  @override
  String get extensionHealthNotConfigured => 'Not configured';

  @override
  String get extensionHealthUnknown => 'Unknown';

  @override
  String get extensionHealthRequired => 'required';

  @override
  String get extensionSettingNotSet => 'Not set';

  @override
  String get extensionActionFailed => 'Action failed';

  @override
  String get extensionEnterValue => 'Enter value';

  @override
  String get extensionHealthServiceOnline => 'Service online';

  @override
  String get extensionHealthServiceDegraded => 'Service degraded';

  @override
  String get extensionHealthServiceOffline => 'Service offline';

  @override
  String get extensionHealthServiceUnknown => 'Service status unknown';

  @override
  String get audioAnalysisStereo => 'Stereo';

  @override
  String get audioAnalysisMono => 'Mono';

  @override
  String trackOpenInService(String serviceName) {
    return 'Open in $serviceName';
  }

  @override
  String get trackLyricsEmbeddedSource => 'Embedded';

  @override
  String get unknownAlbum => 'Unknown Album';

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String get permissionAudio => 'Audio';

  @override
  String get permissionStorage => 'Storage';

  @override
  String get permissionNotification => 'Notification';

  @override
  String get errorInvalidFolderSelected => 'Invalid folder selected';

  @override
  String get storeAnyVersion => 'Any';

  @override
  String get storeCategoryMetadata => 'Metadata';

  @override
  String get storeCategoryDownload => 'Download';

  @override
  String get storeCategoryUtility => 'Utility';

  @override
  String get storeCategoryLyrics => 'Lyrics';

  @override
  String get storeCategoryIntegration => 'Integration';

  @override
  String get artistReleases => 'Releases';

  @override
  String get editMetadataSelectNone => 'None';

  @override
  String queueRetryAllFailed(int count) {
    return 'Retry $count failed';
  }

  @override
  String get settingsSaveDownloadHistory => 'Save download history';

  @override
  String get settingsSaveDownloadHistorySubtitle =>
      'Keep completed downloads in history and library views';

  @override
  String get dialogDisableHistoryTitle => 'Turn off download history?';

  @override
  String get dialogDisableHistoryMessage =>
      'Existing history will be cleared. Downloaded files will not be deleted.';

  @override
  String get dialogDisableAndClear => 'Turn off and clear';

  @override
  String get openInOtherServices => 'Open in Other Services';

  @override
  String get shareSheetNoExtensions => 'No other compatible services';

  @override
  String get shareSheetNotFound => 'Not found';

  @override
  String get shareSheetCopyLink => 'Copy Link';

  @override
  String shareSheetLinkCopied(Object service) {
    return '$service link copied';
  }

  @override
  String get libraryPlayback => 'Playback';

  @override
  String get libraryExternalPlayer => 'External player';

  @override
  String get libraryExternalPlayerSubtitle =>
      'Recommended for listening, best quality, gapless playback, EQ, and wider format support';

  @override
  String get libraryBuiltInPreviewPlayer => 'Built-in preview player';

  @override
  String get libraryBuiltInPreviewPlayerSubtitle =>
      'Only for quick local previews inside SpotiFLAC Mobile, not recommended for regular listening';

  @override
  String get libraryBuiltInPlayerInfo =>
      'The built-in player is a preview tool for checking local tracks quickly. Use an external music player for actual listening.';

  @override
  String get nowPlayingTitle => 'Now Playing';

  @override
  String get nowPlayingNothingPlaying => 'Nothing is playing';

  @override
  String get nowPlayingMinimize => 'Minimize';

  @override
  String get nowPlayingUpNext => 'Up next';

  @override
  String get nowPlayingDetails => 'Details';

  @override
  String get nowPlayingOpenInExternalPlayer => 'Open in external player';

  @override
  String get nowPlayingTabPlayer => 'Player';

  @override
  String get nowPlayingTabLyrics => 'Lyrics';

  @override
  String get nowPlayingNoLyrics => 'No lyrics in this file';

  @override
  String get nowPlayingLibraryEmpty => 'Your library is empty';

  @override
  String nowPlayingShuffleLibraryFailed(String error) {
    return 'Could not shuffle library: $error';
  }

  @override
  String get nowPlayingShuffleOn => 'Shuffle on';

  @override
  String get nowPlayingPlayInOrder => 'Play in order';

  @override
  String get nowPlayingShuffleLibrary => 'Shuffle library';

  @override
  String get nowPlayingQueueEmpty => 'Queue is empty';

  @override
  String get nowPlayingNoMetadata => 'No metadata available';

  @override
  String get announcementUnableToOpenLink =>
      'Unable to open link. Please try again.';

  @override
  String trackConvertLosslessOutputWithCap(String quality) {
    return 'Lossless output with $quality cap';
  }

  @override
  String trackConvertConfirmMessageLosslessCapped(
    String sourceFormat,
    String targetFormat,
    String quality,
  ) {
    return 'Convert from $sourceFormat to $targetFormat ($quality)?\n\nThe output stays in a lossless codec, but bit depth/sample rate will be capped. Original file will be deleted after conversion.';
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
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format ($quality)?\n\nThe output stays in a lossless codec, but bit depth/sample rate will be capped. Original files will be deleted after conversion.';
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
      'Lyrics proxy for Musixmatch, Netease, Apple Music, QQ Music, Spotify, Deezer, YouTube, Kugou, and Genius';

  @override
  String get snackbarPlayingNext => 'Playing next';

  @override
  String get snackbarAddedToQueueGeneric => 'Added to queue';

  @override
  String selectionDeletePlaylistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Delete $count $_temp0';
  }

  @override
  String get actionShuffle => 'Shuffle';

  @override
  String get downloadPrimaryArtistOnlyOn => 'Primary only: On';

  @override
  String get downloadPrimaryArtistOnlyOff => 'Primary only: Off';

  @override
  String get downloadAlbumArtistMetadataPrimaryOnly =>
      'Album Artist metadata: Primary only';

  @override
  String get downloadAlbumArtistMetadataFull => 'Album Artist metadata: Full';

  @override
  String get trackConvertOriginal => 'Original';

  @override
  String get trackConvertOriginalQuality => 'Original quality';

  @override
  String get trackConvertLosslessSuffix => 'Lossless';

  @override
  String get trackConvertDithering => 'Dithering';

  @override
  String get trackConvertResampler => 'Resampler';

  @override
  String get trackConvertDitherNone => 'None';

  @override
  String get trackConvertDitherTriangular => 'TPDF';

  @override
  String get trackConvertDitherTriangularHp => 'Triangular HP';

  @override
  String get trackConvertResamplerSwr => 'SWR';

  @override
  String get trackConvertResamplerSoxr => 'SoXr';

  @override
  String get updateSeeReleaseNotes => 'See release notes for details.';

  @override
  String get unknownTitle => 'Unknown title';

  @override
  String get trackPlayNext => 'Play next';

  @override
  String get trackAddToQueue => 'Add to queue';

  @override
  String snackbarExtensionInstalledEnable(String extensionName) {
    return '$extensionName installed. Enable it in Settings > Extensions';
  }

  @override
  String snackbarExtensionUpdatedVersion(String extensionName, String version) {
    return '$extensionName updated to v$version';
  }

  @override
  String snackbarFailedToInstallNamed(String extensionName) {
    return 'Failed to install $extensionName';
  }

  @override
  String snackbarFailedToUpdateNamed(String extensionName) {
    return 'Failed to update $extensionName';
  }

  @override
  String get releaseTypeEp => 'EP';

  @override
  String get releaseTypeSingle => 'Single';

  @override
  String get trackCoverOnline => 'Online cover';

  @override
  String get regionCountryUS => 'United States';

  @override
  String get regionCountryGB => 'United Kingdom';

  @override
  String get regionCountryFR => 'France';

  @override
  String get regionCountryDE => 'Germany';

  @override
  String get regionCountryJP => 'Japan';

  @override
  String get regionCountryKR => 'South Korea';

  @override
  String get regionCountryIN => 'India';

  @override
  String get regionCountryID => 'Indonesia';

  @override
  String get regionCountryBR => 'Brazil';

  @override
  String get regionCountryMX => 'Mexico';

  @override
  String get regionCountryAU => 'Australia';

  @override
  String get regionCountryCA => 'Canada';

  @override
  String get regionCountryXK => 'Kosovo';

  @override
  String get extensionVerificationBrowserTitle => 'Verification browser';

  @override
  String get extensionVerificationBrowserSubtitleExternal =>
      'Open challenges in the default browser first';

  @override
  String get extensionVerificationBrowserSubtitleInApp =>
      'Open challenges in the in-app browser first';

  @override
  String get extensionVerificationBrowserExternal => 'External';

  @override
  String get extensionVerificationBrowserInApp => 'In-app';

  @override
  String get extensionVerificationHelpTitleManual =>
      'Open verification manually';

  @override
  String get extensionVerificationHelpTitleWaiting =>
      'Verification still waiting';

  @override
  String get extensionVerificationHelpMessageManual =>
      'SpotiFLAC Mobile could not open the browser automatically. Open this link in your browser, or copy it manually.';

  @override
  String get extensionVerificationHelpMessageWaiting =>
      'If the browser did not open, or verification finished but did not return to SpotiFLAC Mobile, open this link again or copy it manually.';

  @override
  String get extensionVerificationClose => 'Close';

  @override
  String get extensionVerificationCopyLink => 'Copy link';

  @override
  String get extensionVerificationLinkCopied => 'Verification link copied';

  @override
  String get extensionVerificationOpenBrowser => 'Open browser';

  @override
  String get settingsSearchHint => 'Buscar en los ajustes';

  @override
  String settingsSearchNoResults(String query) {
    return 'Ningún ajuste coincide con \"$query\"';
  }

  @override
  String get settingsGroupInterface => 'Extensiones y apariencia';

  @override
  String get settingsGroupContent => 'Contenido y metadatos';

  @override
  String get settingsGroupDownloads => 'Descargas y archivos';

  @override
  String get settingsGroupSystem => 'Sistema';

  @override
  String get settingsGroupHelp => 'Información y soporte';
}

/// The translations for Spanish Castilian, as used in Spain (`es_ES`).
class AppLocalizationsEsEs extends AppLocalizationsEs {
  AppLocalizationsEsEs() : super('es_ES');

  @override
  String get appName => 'SpotiFLAC Móvil';

  @override
  String get navHome => 'Inicio';

  @override
  String get navLibrary => 'Biblioteca';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navStore => 'Repositorio';

  @override
  String get homeTitle => 'Inicio';

  @override
  String get homeSubtitle => 'Pega una URL compatible o busca por nombre';

  @override
  String get homeEmptyTitle => 'Aún no hay proveedores de búsqueda';

  @override
  String get homeEmptySubtitle => 'Instalar una extensión para continuar.';

  @override
  String get homeSupports =>
      'Compatible con: URL de pistas, álbumes, listas de reproducción y artistas';

  @override
  String get homeRecent => 'Recientes';

  @override
  String get historyFilterAll => 'Todo';

  @override
  String get historyFilterAlbums => 'Álbumes';

  @override
  String get historyFilterSingles => 'Pistas';

  @override
  String get historySearchHint => 'Buscar en historial...';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsDownload => 'Descargar';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsExtensions => 'Extensiones';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String get downloadTitle => 'Descargar';

  @override
  String get downloadAskQualitySubtitle =>
      'Mostrar selector de calidad para cada descarga';

  @override
  String get downloadFilenameFormat => 'Formato del nombre del archivo';

  @override
  String get downloadSingleFilenameFormat =>
      'Formato del nombre de archivo para pistas individuales';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Patrón de nombre de archivo para sencillos y EP. Utiliza las mismas etiquetas que el formato para álbumes.';

  @override
  String get downloadFolderOrganization => 'Organización de carpetas';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get appearanceThemeSystem => 'Sistema';

  @override
  String get appearanceThemeLight => 'Claro';

  @override
  String get appearanceThemeDark => 'Oscuro';

  @override
  String get appearanceDynamicColor => 'Color Dinámico';

  @override
  String get appearanceDynamicColorSubtitle =>
      'Usar colores de tu fondo de pantalla';

  @override
  String get appearanceHistoryView => 'Vista del Historial';

  @override
  String get appearanceHistoryViewList => 'Lista';

  @override
  String get appearanceHistoryViewGrid => 'Cuadrícula';

  @override
  String get optionsPrimaryProvider => 'Proveedor Principal';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Servicio utilizado para buscar por nombre de pista o álbum';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Usando la extensión: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Pestaña de búsqueda predeterminada';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Elige qué pestaña se abre primero al mostrar nuevos resultados de búsqueda.';

  @override
  String get optionsAutoFallback => 'Cambio automático';

  @override
  String get optionsAutoFallbackSubtitle =>
      'Probar otros servicios si la descarga falla';

  @override
  String get optionsEmbedLyrics => 'Incrustar letras';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Guarda las letras sincronizadas junto a las pistas descargadas';

  @override
  String get optionsMaxQualityCover => 'Máxima calidad de portada';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'Descargar la portada en la mayor resolución';

  @override
  String get optionsReplayGain => 'ReplayGain';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Analizar la sonoridad e incrustar etiquetas ReplayGain (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Desactivado: no hay etiquetas de normalización de sonoridad';

  @override
  String get trackReplayGain => 'Reescanear ReplayGain';

  @override
  String get trackReplayGainScanning => 'Analizando el nivel de volumen...';

  @override
  String get trackReplayGainSuccess => 'Etiquetas ReplayGain agregadas';

  @override
  String get trackReplayGainFailed =>
      'No se pudieron agregar las etiquetas ReplayGain';

  @override
  String selectionReplayGainCount(int count) {
    return 'ReplayGain ($count)';
  }

  @override
  String get replayGainBatchConfirmTitle => 'Agregar ReplayGain';

  @override
  String replayGainBatchConfirmMessage(int count) {
    return '¿Analizar el volumen y escribir las etiquetas ReplayGain en $count pista(s)?';
  }

  @override
  String get replayGainBatchAnalyzing => 'Analizando ReplayGain...';

  @override
  String replayGainBatchSuccess(int success, int total) {
    return 'Se agregaron las etiquetas ReplayGain a $success de $total pistas';
  }

  @override
  String get optionsArtistTagMode => 'Modo de etiqueta de artista';

  @override
  String get optionsArtistTagModeDescription =>
      'Elige cómo se escriben varios artistas en las etiquetas incrustadas.';

  @override
  String get optionsArtistTagModeJoined => 'Valor único combinado';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Escribir un solo valor de ARTISTA como «Artista A, Artista B» para máxima compatibilidad con reproductores.';

  @override
  String get optionsArtistTagModeSplitVorbis =>
      'Separar etiquetas para FLAC/Opus';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'Escribe una etiqueta de artista por cada artista en FLAC y Opus; MP3 y M4A se mantienen combinados.';

  @override
  String get optionsExtensionStore => 'Repositorio de extensiones';

  @override
  String get optionsExtensionStoreSubtitle =>
      'Mostrar la pestaña del repositorio en la navegación';

  @override
  String get optionsCheckUpdates => 'Buscar actualizaciones';

  @override
  String get optionsCheckUpdatesSubtitle =>
      'Notificar cuando una nueva versión esté disponible';

  @override
  String get optionsUpdateChannel => 'Tipo de actualizaciones';

  @override
  String get optionsUpdateChannelStable => 'Solo versiones estables';

  @override
  String get optionsUpdateChannelPreview => 'Obtener versiones preliminares';

  @override
  String get optionsUpdateChannelWarning =>
      'La versión preliminar puede contener errores o funciones incompletas';

  @override
  String get optionsClearHistory => 'Borrar historial de descargas';

  @override
  String get optionsClearHistorySubtitle =>
      'Eliminar todas las pistas descargadas del historial';

  @override
  String get optionsDetailedLogging => 'Registro detallado';

  @override
  String get optionsDetailedLoggingOn => 'Se están registrando logs detallados';

  @override
  String get optionsDetailedLoggingOff => 'Activar para informes de errores';

  @override
  String get extensionsTitle => 'Extensiones';

  @override
  String get extensionsDisabled => 'Desactivado';

  @override
  String extensionsVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get extensionsUninstall => 'Desinstalar';

  @override
  String get storeTitle => 'Repositorio de extensiones';

  @override
  String get storeSearch => 'Buscar extensiones...';

  @override
  String get storeInstall => 'Instalar';

  @override
  String get storeInstalled => 'Instalada';

  @override
  String get storeUpdate => 'Actualizar';

  @override
  String get aboutTitle => 'Acerca de';

  @override
  String get aboutContributors => 'Colaboradores';

  @override
  String get aboutMobileDeveloper => 'Desarrollador de versiones móviles';

  @override
  String get aboutOriginalCreator => 'Creador original de SpotiFLAC';

  @override
  String get aboutLogoArtist =>
      '¡El talentoso artista que creó el hermoso logo de nuestra app!';

  @override
  String get aboutTranslators => 'Traductores';

  @override
  String get aboutSpecialThanks => 'Agradecimientos especiales';

  @override
  String get aboutLinks => 'Enlaces';

  @override
  String get aboutMobileSource => 'Código fuente de la versión móvil';

  @override
  String get aboutPCSource => 'Código fuente de la versión para PC';

  @override
  String get aboutKeepAndroidOpen => 'Mantener Android activo';

  @override
  String get aboutReportIssue => 'Reportar un problema';

  @override
  String get aboutReportIssueSubtitle =>
      'Reporta cualquier problema que encuentres';

  @override
  String get aboutFeatureRequest => 'Sugerir una función';

  @override
  String get aboutFeatureRequestSubtitle =>
      'Sugerir nuevas funciones para la aplicación';

  @override
  String get aboutTelegramChannel => 'Canal de Telegram';

  @override
  String get aboutTelegramChannelSubtitle => 'Anuncios y actualizaciones';

  @override
  String get aboutTelegramChat => 'Comunidad de Telegram';

  @override
  String get aboutTelegramChatSubtitle => 'Chatear con otros usuarios';

  @override
  String get aboutSocial => 'Redes sociales';

  @override
  String get aboutApp => 'Aplicación';

  @override
  String get aboutVersion => 'Versión';

  @override
  String get aboutBinimumDesc =>
      'El creador de QQDL & HiFi API. Este proyecto ayudó a impulsar el soporte para descargas sin pérdida de calidad.';

  @override
  String get aboutSachinsenalDesc =>
      'El creador del proyecto HiFi original. Sentó las bases para la integración de fuentes de audio sin pérdida de calidad.';

  @override
  String get aboutSjdonadoDesc =>
      'Creador de I No tengo Spotify (IDHS). ¡La solución de enlace de reserva que salva el día!';

  @override
  String get aboutAppDescription =>
      'Busca información musical, gestiona extensiones y organiza tu biblioteca.';

  @override
  String get artistAlbums => 'Álbumes';

  @override
  String get artistSingles => 'Pistas y mini-álbumes';

  @override
  String get artistCompilations => 'Compilaciones';

  @override
  String get artistPopular => 'Populares';

  @override
  String artistMonthlyListeners(String count) {
    return '$count oyentes mensuales';
  }

  @override
  String get trackMetadataService => 'Servicio';

  @override
  String get trackMetadataPlay => 'Reproducir';

  @override
  String get trackMetadataShare => 'Compartir';

  @override
  String get trackMetadataDelete => 'Eliminar';

  @override
  String get setupGrantPermission => 'Conceder permiso';

  @override
  String get setupSkip => 'Omitir por ahora';

  @override
  String get setupStorageAccessRequired => 'Acceso al almacenamiento requerido';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Android 11+ requiere permiso \"Todos los archivos de acceso\" para guardar los archivos en la carpeta de descargas elegida.';

  @override
  String get setupOpenSettings => 'Abrir ajustes';

  @override
  String get setupPermissionDeniedMessage =>
      'Permiso denegado. Por favor, conceda todos los permisos para continuar.';

  @override
  String setupPermissionRequired(String permissionType) {
    return 'Permiso de $permissionType requerido';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return 'Se requiere un permiso $permissionType para la mejor experiencia. Puedes cambiar esto más tarde en ajustes.';
  }

  @override
  String get setupUseDefaultFolder => '¿Usar carpeta por defecto?';

  @override
  String get setupNoFolderSelected =>
      'No se ha seleccionado ninguna carpeta. ¿Desea utilizar la carpeta por defecto?';

  @override
  String get setupUseDefault => 'Usar por defecto';

  @override
  String get setupDownloadLocationTitle => 'Ubicación de descarga';

  @override
  String get setupDownloadLocationIosMessage =>
      'En iOS, las descargas se guardan en la carpeta de documentos de la aplicación. Puede acceder a ellas desde la aplicación Archivos.';

  @override
  String get setupAppDocumentsFolder => 'Carpeta de documentos de App';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Recomendado - accesible desde la aplicación Archivos';

  @override
  String get setupChooseFromFiles => 'Elegir de archivos';

  @override
  String get setupChooseFromFilesSubtitle =>
      'Seleccione iCloud u otra ubicación';

  @override
  String get setupIosEmptyFolderWarning =>
      'Limitación de iOS: No se pueden seleccionar carpetas vacías. Elige una carpeta con al menos un archivo.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive no es compatible. Utilice la carpeta Documentos de la aplicación.';

  @override
  String get setupDownloadInFlac => 'Descargar pistas de Spotify en FLAC';

  @override
  String get setupStorageGranted => '¡Permiso de almacenamiento concedido!';

  @override
  String get setupStorageRequired => 'Permiso de almacenamiento requerido';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC necesita permiso de almacenamiento para guardar sus archivos de música descargados.';

  @override
  String get setupNotificationGranted =>
      '¡Acceso a las notificaciones permitido!';

  @override
  String get setupNotificationEnable => 'Activar notificaciones';

  @override
  String get setupFolderChoose => 'Cambiar carpeta de descargas';

  @override
  String get setupFolderDescription =>
      'Seleccione una carpeta donde se guardará la música descargada.';

  @override
  String get setupSelectFolder => 'Seleccionar Carpeta';

  @override
  String get setupEnableNotifications => 'Activar notificaciones';

  @override
  String get setupNotificationBackgroundDescription =>
      'Recibe notificaciones sobre el progreso de la descarga y la finalización. Esto te ayuda a rastrear las descargas cuando la aplicación está en segundo plano.';

  @override
  String get setupSkipForNow => 'Omitir por ahora';

  @override
  String get setupNext => 'Siguiente';

  @override
  String get setupGetStarted => 'Empezar';

  @override
  String get setupAllowAccessToManageFiles =>
      'Por favor, activa \"Permitir el acceso para gestionar todos los archivos\" en la siguiente pantalla.';

  @override
  String get setupLanguageTitle => 'Elegir idioma';

  @override
  String get setupLanguageDescription =>
      'Selecciona tu idioma preferido para la aplicación. Puedes cambiar esto luego en Configuración.';

  @override
  String get setupLanguageSystemDefault => 'Idioma predeterminado';

  @override
  String get dialogCancel => 'Cancelar';

  @override
  String get dialogSave => 'Guardar';

  @override
  String get dialogDelete => 'Eliminar';

  @override
  String get dialogRetry => 'Volver a intentar';

  @override
  String get dialogClear => 'Borrar';

  @override
  String get dialogDone => 'Hecho';

  @override
  String get dialogImport => 'Importar';

  @override
  String get dialogDownload => 'Descargar';

  @override
  String get previewPlay => 'Reproducir vista previa';

  @override
  String get previewStop => 'Detener vista previa';

  @override
  String get previewUnavailable => 'Vista previa no disponible';

  @override
  String get dialogDiscard => 'Descartar';

  @override
  String get dialogRemove => 'Eliminar';

  @override
  String get dialogUninstall => 'Desinstalar';

  @override
  String get dialogDiscardChanges => '¿Descartar cambios?';

  @override
  String get dialogUnsavedChanges =>
      'Tienes cambios sin guardar. ¿Quieres descartarlos?';

  @override
  String get dialogClearAll => 'Eliminar todo';

  @override
  String get dialogRemoveExtension => 'Eliminar extensión';

  @override
  String get dialogRemoveExtensionMessage =>
      '¿Estás seguro de que quieres eliminar esta extensión? Esto no se puede deshacer.';

  @override
  String get dialogUninstallExtension => '¿Desinstalar extensión?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return '¿Estás seguro de que quieres eliminar $extensionName?';
  }

  @override
  String get dialogClearHistoryTitle => 'Borrar historial';

  @override
  String get dialogClearHistoryMessage =>
      '¿Estás seguro de que quieres borrar todo el historial de descargas? Esta acción no se puede deshacer.';

  @override
  String get dialogDeleteSelectedTitle => 'Borrar Seleccionados';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '¿Eliminar $count $_temp0 del historial?\n\nEsto también eliminará los archivos del almacenamiento.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Importar lista de reproducción';

  @override
  String dialogImportPlaylistMessage(int count) {
    return 'Se han encontrado pistas $count en CSV. ¿Añadirlas para descargar la cola?';
  }

  @override
  String csvImportTracks(int count) {
    return '$count pistas de CSV';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return 'Añadido \"$trackName\" a la cola';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return 'Añadidas pistas $count a la cola';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\"$trackName\" ya descargado';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '\"$trackName\" ya existe en tu biblioteca';
  }

  @override
  String get snackbarHistoryCleared => 'Historial borrado';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return 'Eliminado $count $_temp0';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'No se puede abrir el archivo: $error';
  }

  @override
  String get snackbarViewQueue => 'Ver cola';

  @override
  String snackbarUrlCopied(String platform) {
    return 'URL $platform copiada al portapapeles';
  }

  @override
  String get snackbarFileNotFound => 'Archivo no encontrado';

  @override
  String get snackbarSelectExtFile =>
      'Por favor, seleccione un archivo .spotiflac-ext';

  @override
  String get snackbarProviderPrioritySaved => 'Prioridad de proveedor guardada';

  @override
  String get snackbarMetadataProviderSaved =>
      'Prioridad de proveedor de información guardada';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '$extensionName instalado.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName actualizada.';
  }

  @override
  String get snackbarFailedToInstall => 'Fallo al instalar la extensión';

  @override
  String get snackbarFailedToUpdate => 'Error al actualizar la extensión';

  @override
  String get errorRateLimited => 'Límite excedido';

  @override
  String get errorRateLimitedMessage =>
      'Demasiadas solicitudes. Por favor, espere un momento antes de buscar de nuevo.';

  @override
  String get errorNoTracksFound => 'No se encontraron pistas';

  @override
  String get searchEmptyResultSubtitle => 'Prueba con otra palabra clave';

  @override
  String get errorUrlNotRecognized => 'Enlace no reconocido';

  @override
  String get errorUrlNotRecognizedMessage =>
      'Este enlace no es compatible. Asegúrate de que la URL sea correcta y de tener instalada una extensión compatible.';

  @override
  String get errorUrlFetchFailed =>
      'No se ha podido cargar el contenido de este enlace. Inténtalo de nuevo.';

  @override
  String errorMissingExtensionSource(String item) {
    return 'No se puede cargar $item: falta una fuente de extensión';
  }

  @override
  String get actionPause => 'Pausar';

  @override
  String get actionResume => 'Reanudar';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionSelectAll => 'Seleccionar Todo';

  @override
  String get actionDeselect => 'Deseleccionar';

  @override
  String selectionSelected(int count) {
    return '$count seleccionado';
  }

  @override
  String get selectionAllSelected => 'Todas las pistas seleccionadas';

  @override
  String get selectionSelectToDelete => 'Seleccionar pistas a eliminar';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Obteniendo información... $current/$total';
  }

  @override
  String get progressReadingCsv => 'Leyendo CSV...';

  @override
  String get searchSongs => 'Canciones';

  @override
  String get searchArtists => 'Artistas';

  @override
  String get searchAlbums => 'Álbumes';

  @override
  String get searchPlaylists => 'Listas de reproducción';

  @override
  String get searchSortTitle => 'Ordenar resultados';

  @override
  String get searchSortDefault => 'Por defecto';

  @override
  String get searchSortTitleAZ => 'Nombre (A-Z)';

  @override
  String get searchSortTitleZA => 'Nombre (Z-A)';

  @override
  String get searchSortArtistAZ => 'Artista (A-Z)';

  @override
  String get searchSortArtistZA => 'Artista (Z-A)';

  @override
  String get searchSortDurationShort => 'Duración (más corto)';

  @override
  String get searchSortDurationLong => 'Duración (más largo)';

  @override
  String get searchSortDateOldest => 'Fecha de lanzamiento (antiguo)';

  @override
  String get searchSortDateNewest => 'Fecha de lanzamiento (reciente)';

  @override
  String get tooltipPlay => 'Reproducir';

  @override
  String get filenameFormat => 'Formato del nombre del archivo';

  @override
  String get filenameShowAdvancedTags => 'Mostrar etiquetas avanzadas';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Habilitar etiquetas con formato para el relleno de pistas y los formatos de fecha';

  @override
  String get folderOrganizationNone => 'Ninguna organización';

  @override
  String get folderOrganizationByPlaylist => 'Por lista de reproducción';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Una carpeta independiente para cada lista de reproducción';

  @override
  String get folderOrganizationByArtist => 'Por Artista';

  @override
  String get folderOrganizationByAlbum => 'Por Álbum';

  @override
  String get folderOrganizationByArtistAlbum => 'Artista/Álbum';

  @override
  String get folderOrganizationDescription =>
      'Organizar los archivos descargados en carpetas';

  @override
  String get folderOrganizationNoneSubtitle =>
      'Todos los archivos de la carpeta de descargas';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Carpeta separada para cada artista';

  @override
  String get folderOrganizationByAlbumSubtitle =>
      'Carpeta separada para cada artista';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Carpetas organizadas por artista y álbum';

  @override
  String get updateAvailable => 'Actualización Disponible';

  @override
  String get updateLater => 'Más tarde';

  @override
  String get updateStartingDownload => 'Iniciando descarga...';

  @override
  String get updateDownloadFailed => 'Descarga fallida';

  @override
  String get updateFailedMessage => 'Error al descargar la actualización';

  @override
  String get updateNewVersionReady => 'Una nueva versión está lista';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String updateRequiredNotice(int count) {
    return 'This version is $count releases behind and is no longer supported. Update to keep using the app.';
  }

  @override
  String get updateCurrent => 'Actual';

  @override
  String get updateNew => 'Nuevo';

  @override
  String get updateDownloading => 'Descargando...';

  @override
  String get updateWhatsNew => 'Novedades';

  @override
  String get updateDownloadInstall => 'Descargar & Instalar';

  @override
  String get updateDontRemind => 'No recordar';

  @override
  String get providerPriorityTitle => 'Prioridad del proveedor';

  @override
  String get providerPriorityDescription =>
      'Arrastra para reordenar los proveedores de descarga. La aplicación intentará usar los proveedores de arriba hacia abajo al descargar las pistas.';

  @override
  String get providerPriorityInfo =>
      'Si una pista no está disponible en el primer proveedor, la aplicación intentará automáticamente el siguiente.';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Elija las extensiones de descarga que se usarán como respaldo automático.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Solo las extensiones activas con proveedor de descarga se listan aquí.';

  @override
  String get providerExtension => 'Extensión';

  @override
  String get metadataProviderPriorityTitle => 'Prioridad de la información';

  @override
  String get metadataProviderPriorityDescription =>
      'Arrastra para reordenar los proveedores de información. La aplicación probará los proveedores de arriba hacia abajo al buscar pistas y obtener la información.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer no tiene límites de tasa y se recomienda como principal. Spotify puede valorar el límite después de muchas solicitudes.';

  @override
  String get logTitle => 'Registros';

  @override
  String get logCopied => 'Registros copiados al portapapeles';

  @override
  String get logSearchHint => 'Buscar registros...';

  @override
  String get logFilterLevel => 'Nivel';

  @override
  String get logFilterSection => 'Filtrar';

  @override
  String get logShareLogs => 'Compartir registros';

  @override
  String get logClearLogs => 'Borrar registros';

  @override
  String get logClearLogsTitle => 'Limpiar registros';

  @override
  String get logClearLogsMessage =>
      '¿Estás seguro qué deseas limpiar todos los registros?';

  @override
  String get logFilterBySeverity => 'Filtrar los registros por gravedad';

  @override
  String get logNoLogsYet => 'No hay registros aún';

  @override
  String get logNoLogsYetSubtitle =>
      'Los registros aparecerán aquí mientras usas la aplicación';

  @override
  String logEntriesFiltered(int count) {
    return 'Entradas ($count filtradas)';
  }

  @override
  String logEntries(int count) {
    return 'Entradas ($count)';
  }

  @override
  String get channelStable => 'Estable';

  @override
  String get channelPreview => 'Vista previa';

  @override
  String get sectionSearchSource => 'Buscar Fuente';

  @override
  String get sectionDownload => 'Descargar';

  @override
  String get sectionPerformance => 'Alto rendimiento';

  @override
  String get sectionApp => 'Aplicación';

  @override
  String get sectionData => 'Datos';

  @override
  String get sectionDebug => 'Depuración';

  @override
  String get sectionService => 'Servicio';

  @override
  String get sectionAudioQuality => 'Calidad de Sonido';

  @override
  String get sectionFileSettings => 'Ajustes del archivo';

  @override
  String get sectionLyrics => 'Letras';

  @override
  String get lyricsMode => 'Modo Letras';

  @override
  String get lyricsModeDescription =>
      'Elige cómo se guardan las letras de tus descargas';

  @override
  String get lyricsModeEmbed => 'Insertar en archivo';

  @override
  String get lyricsModeEmbedSubtitle =>
      'Letras almacenadas en la información FLAC';

  @override
  String get lyricsModeExternal => 'Archivo .lrc externo';

  @override
  String get lyricsModeExternalSubtitle =>
      'Archivo .lrc separado para reproductores como Samsung Music';

  @override
  String get lyricsModeBoth => 'Ambos';

  @override
  String get lyricsModeBothSubtitle => 'Insertar y guardar archivo .lrc';

  @override
  String get sectionColor => 'Colores';

  @override
  String get sectionTheme => 'Tema';

  @override
  String get sectionLayout => 'Diseño';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get appearanceLanguage => 'Idioma de la aplicación';

  @override
  String get settingsAppearanceSubtitle => 'Tema, colores, pantalla';

  @override
  String get settingsDownloadSubtitle => 'Servicio, calidad, respaldo';

  @override
  String get settingsExtensionsSubtitle =>
      'Administrar proveedores de descarga';

  @override
  String get settingsLogsSubtitle =>
      'Ver registros de aplicaciones para depuración';

  @override
  String get loadingSharedLink => 'Cargando enlace compartido...';

  @override
  String get pressBackAgainToExit => 'Presione de nuevo para salir';

  @override
  String downloadAllCount(int count) {
    return 'Descargar todo ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistas',
      one: '1 pista',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Copiar ruta de archivo';

  @override
  String get trackRemoveFromDevice => 'Eliminar del dispositivo';

  @override
  String get trackLoadLyrics => 'Cargar letras';

  @override
  String get trackMetadata => 'Información';

  @override
  String get trackFileInfo => 'Información de archivo';

  @override
  String get trackLyrics => 'Letras';

  @override
  String get trackFileNotFound => 'Archivo no encontrado';

  @override
  String get trackOpenInDeezer => 'Abrir en Deezer';

  @override
  String get trackOpenInSpotify => 'Abrir en Spotify';

  @override
  String get trackTrackName => 'Nombre de pista';

  @override
  String get trackArtist => 'Artista';

  @override
  String get trackAlbumArtist => 'Artista del álbum';

  @override
  String get trackAlbum => 'Álbum';

  @override
  String get trackTrackNumber => 'Número de pista';

  @override
  String get trackDiscNumber => 'Número de disco';

  @override
  String get trackDuration => 'Duración';

  @override
  String get trackAudioQuality => 'Calidad del sonido';

  @override
  String get trackReleaseDate => 'Fecha de lanzamiento';

  @override
  String get trackGenre => 'Género';

  @override
  String get trackLabel => 'Etiqueta';

  @override
  String get trackCopyright => 'Derechos de autor';

  @override
  String get trackDownloaded => 'Descargado';

  @override
  String get trackCopyLyrics => 'Copiar letras';

  @override
  String trackLyricsSource(String source) {
    return 'Fuente: $source';
  }

  @override
  String get trackLyricsNotAvailable => 'Letras no disponibles para este tema';

  @override
  String get trackLyricsNotInFile => 'No se encontraron letras';

  @override
  String get trackFetchOnlineLyrics => 'Obtener en línea';

  @override
  String get trackLyricsTimeout =>
      'Tiempo de espera agotado. Inténtalo de nuevo más tarde.';

  @override
  String get trackLyricsLoadFailed => 'Error al cargar la letra';

  @override
  String get trackEmbedLyrics => 'Incrustar Letras';

  @override
  String get trackLyricsEmbedded => 'Letra incrustada con éxito';

  @override
  String get trackInstrumental => 'Pista instrumental';

  @override
  String get trackCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get trackDeleteConfirmTitle => '¿Eliminar del dispositivo?';

  @override
  String get trackDeleteConfirmMessage =>
      'Esto eliminará permanentemente el archivo descargado y lo eliminará de tu historial.';

  @override
  String get dateToday => 'Hoy';

  @override
  String get dateYesterday => 'Ayer';

  @override
  String dateDaysAgo(int count) {
    return 'Hace $count días';
  }

  @override
  String dateWeeksAgo(int count) {
    return '$count semanas antes';
  }

  @override
  String dateMonthsAgo(int count) {
    return '$count meses atrás';
  }

  @override
  String get storeFilterAll => 'Todo';

  @override
  String get storeFilterMetadata => 'Información';

  @override
  String get storeFilterDownload => 'Descargar';

  @override
  String get storeFilterUtility => 'Utilidad';

  @override
  String get storeFilterLyrics => 'Letras';

  @override
  String get storeFilterIntegration => 'Integración';

  @override
  String get storeClearFilters => 'Limpiar filtros';

  @override
  String get storeAddRepoTitle => 'Añadir repositorio de extensiones';

  @override
  String get storeAddRepoDescription =>
      'Introduzca una URL de repositorio de GitHub que contenga un archivo registry.json para navegar e instalar extensiones.';

  @override
  String get storeRepoUrlLabel => 'URL del repositorio';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeAddRepoButton => 'Añadir repositorio';

  @override
  String get storeChangeRepoTooltip => 'Cambiar repositorio';

  @override
  String get storeRepoDialogTitle => 'Repositorio de extensiones';

  @override
  String get storeRepoDialogCurrent => 'Repositorio actual:';

  @override
  String get storeNewRepoUrlLabel => 'Nueva URL del repositorio';

  @override
  String get storeLoadError => 'Falló al cargar repositorio';

  @override
  String get storeEmptyNoExtensions => 'No hay extensiones disponibles';

  @override
  String get storeEmptyNoResults => 'No se encontraron extensiones';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => 'Error';

  @override
  String get extensionCapabilities => 'Recursos';

  @override
  String get extensionMetadataProvider => 'Proveedor de información';

  @override
  String get extensionDownloadProvider => 'Proveedor de descargas';

  @override
  String get extensionLyricsProvider => 'Proveedor de letras';

  @override
  String get extensionUrlHandler => 'Gestor de URL';

  @override
  String get extensionQualityOptions => 'Opciones de calidad';

  @override
  String get extensionPostProcessingHooks => 'Post-procesamiento de hooks';

  @override
  String get extensionPermissions => 'Permisos';

  @override
  String get extensionSettings => 'Ajustes';

  @override
  String get extensionRemoveButton => 'Eliminar extensión';

  @override
  String get extensionUpdated => 'Actualizado';

  @override
  String get extensionMinAppVersion => 'Versión Mínima de la aplicación';

  @override
  String get extensionCustomTrackMatching =>
      'Coincidencia de pista personalizada';

  @override
  String get extensionPostProcessing => 'Post-Procesamiento';

  @override
  String extensionHooksAvailable(int count) {
    return '$count hook(s) disponibles';
  }

  @override
  String extensionPatternsCount(int count) {
    return 'Patrón(es) $count';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Estrategia: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => 'Prioridad del proveedor';

  @override
  String get extensionsInstalledSection => 'Extensiones instaladas';

  @override
  String get extensionsNoExtensions => 'No hay extensiones instaladas';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Instalar archivos .spotiflac-ext para añadir nuevos proveedores';

  @override
  String get extensionsInstallButton => 'Instalar extensión';

  @override
  String get extensionsInfoTip =>
      'Las extensiones pueden añadir nueva información y proveedores de descargas. Solo instalar extensiones desde fuentes confiables.';

  @override
  String get extensionsInstalledSuccess => 'Extensión instalada correctamente';

  @override
  String extensionsInstalledCount(int count) {
    return '$count Extensiones instaladas correctamente';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return '$installed Instalados de $attempted extensiones';
  }

  @override
  String get extensionsDownloadPriority => 'Prioridad de descarga';

  @override
  String get extensionsDownloadPrioritySubtitle =>
      'Establecer orden de servicio de descarga';

  @override
  String get extensionsFallbackTitle => 'Respaldo de extensiones';

  @override
  String get extensionsFallbackSubtitle =>
      'Elija que extensiones pueden usarse como reserva';

  @override
  String get extensionsNoDownloadProvider =>
      'No hay extensiones con proveedor de descargas';

  @override
  String get extensionsMetadataPriority => 'Prioridad de la información';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Establecer orden de búsqueda y información';

  @override
  String get extensionsNoMetadataProvider =>
      'No hay extensiones con el proveedor de información';

  @override
  String get extensionsSearchProvider => 'Proveedor de búsqueda';

  @override
  String get extensionsNoCustomSearch =>
      'No hay extensiones con búsqueda personalizada';

  @override
  String get extensionsSearchProviderDescription =>
      'Elegir qué servicio usar para buscar pistas';

  @override
  String get extensionsCustomSearch => 'Búsqueda personalizada';

  @override
  String get extensionsErrorLoading => 'Error al cargar la extensión';

  @override
  String get qualityFlacLossless => 'FLAC sin pérdida';

  @override
  String get qualityFlacLosslessSubtitle => '16-bit / 44,1 kHz';

  @override
  String get qualityHiResFlac => 'FLAC de alta resolución';

  @override
  String get qualityHiResFlacSubtitle => '24-bit / hasta 96 kHz';

  @override
  String get qualityHiResFlacMax => 'Hi-Res FLAC Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-bit / hasta 192 kHz';

  @override
  String get downloadLossy320 => 'Con pérdida, 320 kbps';

  @override
  String get downloadLossyFormat => 'Formato con pérdida';

  @override
  String get downloadLossy320Format => 'Formato con pérdida a 320 kbps';

  @override
  String get downloadLossy320FormatDesc =>
      'Elige el formato de salida para las descargas con pérdida de calidad a 320 kbps. Cuando sea necesario, el audio original se convertirá al formato seleccionado.';

  @override
  String get downloadLossyMp3 => 'MP3 (320 kbps)';

  @override
  String get downloadLossyMp3Subtitle =>
      'Mejor compatibilidad, ~10 MB por pista';

  @override
  String get downloadLossyAac => 'AAC/M4A (320 kbps)';

  @override
  String get downloadLossyAacSubtitle =>
      'La mejor compatibilidad con dispositivos móviles, formato M4A';

  @override
  String get downloadLossyOpus256 => 'OPUS (256 kbps)';

  @override
  String get downloadLossyOpus256Subtitle =>
      'Mejor calidad de OPUS, ~8 MB por pista';

  @override
  String get downloadLossyOpus128 => 'OPUS (128 kbps)';

  @override
  String get downloadLossyOpus128Subtitle => 'Tamaño mínimo: ~4 MB por pista';

  @override
  String get downloadAskBeforeDownload => 'Preguntar antes de descargar';

  @override
  String get downloadDirectory => 'Carpeta de descarga';

  @override
  String get downloadSeparateSinglesFolder => 'Carpeta separada para pistas';

  @override
  String get downloadAlbumFolderStructure => 'Estructura de carpeta del álbum';

  @override
  String get albumFolderStructureDescription =>
      'Elige cómo se estructuran las carpetas de los álbumes';

  @override
  String get downloadUseAlbumArtistForFolders =>
      'Usar álbum de artista cómo carpeta';

  @override
  String get downloadUsePrimaryArtistOnly =>
      'Artista principal solo para carpetas';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Se han eliminado los nombres de los artistas destacados del nombre de la carpeta (p. ej., Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Se utiliza el nombre completo del artista como nombre de la carpeta';

  @override
  String get downloadSelectQuality => 'Seleccionar Calidad';

  @override
  String get downloadFrom => 'Descargar Desde';

  @override
  String get appearanceAmoledDark => 'AMOLED Oscuro';

  @override
  String get appearanceAmoledDarkSubtitle => 'Fondo negro puro';

  @override
  String get appearanceHeroAnimations => 'Hero animations';

  @override
  String get appearanceHeroAnimationsSubtitle =>
      'Fly covers between screens, e.g. when opening the player';

  @override
  String get queueClearAll => 'Eliminar todo';

  @override
  String get queueClearAllMessage =>
      '¿Estás seguro de que quieres borrar todas las descargas?';

  @override
  String get settingsAutoExportFailed => 'Autoexportar descargas fallidas';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Guardar descargas fallidas en el archivo TXT automáticamente';

  @override
  String get settingsDownloadNetwork => 'Red de descarga';

  @override
  String get settingsDownloadNetworkAny => 'Wi-Fi + Datos móviles';

  @override
  String get settingsDownloadNetworkWifiOnly => 'Iniciar solo por Wi-Fi';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'Elegir qué red usar para descargas. Cuando se establece en Wi-Fi solamente, las descargas se detendrán en los datos móviles.';

  @override
  String get settingsConcurrentDownloads => 'Concurrent downloads';

  @override
  String get settingsConcurrentDownloadsSubtitle =>
      'Downloading several tracks at once is faster, but some providers may rate-limit parallel requests.';

  @override
  String get concurrentDownloadsOne => '1 track at a time';

  @override
  String concurrentDownloadsCount(int count) {
    return 'Up to $count tracks at once';
  }

  @override
  String get albumFolderArtistAlbum => 'Artista / Álbum';

  @override
  String get albumFolderArtistAlbumSubtitle =>
      'Álbumes/Nombre del Artista/Nombre del Álbum/';

  @override
  String get albumFolderArtistYearAlbum => 'Artista / [Año] Álbum';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Álbumes/Nombre del Artista /[2005] Nombre del Álbum/';

  @override
  String get albumFolderAlbumOnly => 'Sólo álbum';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Álbumes/Nombre del Álbum/';

  @override
  String get albumFolderYearAlbum => 'Álbum [Año]';

  @override
  String get albumFolderYearAlbumSubtitle => 'Álbumes/[2005] Nombre del Álbum/';

  @override
  String get albumFolderArtistAlbumSingles => 'Artista / Álbum + Pistas';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Artista/Álbum/ y Artista/pistas/';

  @override
  String get albumFolderArtistAlbumFlat => 'Artista / Álbum (sencillos planos)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Artista/Álbum/ y Artista/canción.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Borrar seleccionados';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '¿Eliminar $count $_temp0 del historial?\n\nEsto también eliminará los archivos del almacenamiento.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count seleccionado';
  }

  @override
  String get downloadedAlbumTapToSelect => 'Toca las pistas para seleccionar';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '¡Eliminar $count $_temp0';
  }

  @override
  String get downloadedAlbumSelectToDelete => 'Seleccionar pistas a eliminar';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Disco $discNumber';
  }

  @override
  String get recentTypeArtist => 'Artista';

  @override
  String get recentTypeAlbum => 'Álbum';

  @override
  String get recentTypeSong => 'Canción';

  @override
  String get recentTypePlaylist => 'Lista de reproducción';

  @override
  String get recentEmpty => 'Aún no hay entradas recientes';

  @override
  String get recentShowAllDownloads => 'Mostrar todas las descargas';

  @override
  String recentPlaylistInfo(String name) {
    return 'Lista de reproducción: $name';
  }

  @override
  String get discographyDownload => 'Descargar Discografía';

  @override
  String get discographyDownloadAll => 'Descargar Todo';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$count pistas de $albumCount lanzamientos';
  }

  @override
  String get discographyAlbumsOnly => 'Sólo álbumes';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$count pistas de $albumCount álbumes';
  }

  @override
  String get discographySinglesOnly => 'Solo sencillos & mini-álbum';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$count Pistas de $albumCount sencillos';
  }

  @override
  String get discographySelectAlbums => 'Seleccionar álbumes...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Elige álbumes o sencillos concretos';

  @override
  String get discographyFetchingTracks => 'Cargando canciones...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return 'Cargando $current de $total...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get discographyDownloadSelected => 'Descargar seleccionados';

  @override
  String discographyAddedToQueue(int count) {
    return 'Se agregaron $count canciones a la lista de espera';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added añadidas, $skipped ya fueron descargadas';
  }

  @override
  String get discographyNoAlbums => 'No hay álbumes disponibles';

  @override
  String get discographyFailedToFetch =>
      'Hubo un error para encontrar algunos álbumes';

  @override
  String get sectionStorageAccess => 'Permiso de almacenamiento';

  @override
  String get allFilesAccess => 'Acceso a todos los archivos';

  @override
  String get allFilesAccessEnabledSubtitle =>
      'Puede escribir en cualquier carpeta';

  @override
  String get allFilesAccessDisabledSubtitle => 'Limitado a carpetas de media';

  @override
  String get allFilesAccessDescription =>
      'Habilite esto si tiene problemas de escritura al guardar en carpetas personalizadas. Android 13+ restringe el acceso a ciertas carpetas por defecto.';

  @override
  String get allFilesAccessDeniedMessage =>
      'Permiso denegado. Por favor habilite \'Acceso a todos los archivos\' de manera manual en la configuración del sistema.';

  @override
  String get allFilesAccessDisabledMessage =>
      'Acceso a todos los archivos desactivado. La aplicación usará acceso limitado al almacenamiento.';

  @override
  String get settingsLocalLibrary => 'Librería local';

  @override
  String get settingsLocalLibrarySubtitle =>
      'Escanear música y detectar duplicados';

  @override
  String get settingsCache => 'Almacenamiento & caché';

  @override
  String get settingsCacheSubtitle => 'Ver tamaño y borrar datos en caché';

  @override
  String get libraryTitle => 'Librería local';

  @override
  String get libraryScanSettings => 'Configuración de escaneo';

  @override
  String get libraryEnableLocalLibrary => 'Habilitar librería local';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Escanea y rastrea tu música existente';

  @override
  String get libraryFolder => 'Carpeta de la librería';

  @override
  String get libraryFolderHint => 'Toque para seleccionar la carpeta';

  @override
  String get libraryShowDuplicateIndicator => 'Mostrar indicador de duplicados';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Mostrar al buscar canciones existentes';

  @override
  String get libraryAutoScan => 'Escaneo automático';

  @override
  String get libraryAutoScanSubtitle =>
      'Escanear automáticamente tu librería por nuevos archivos';

  @override
  String get libraryAutoScanOff => 'Apagado';

  @override
  String get libraryAutoScanOnOpen => 'Cada vez que la aplicación se abra';

  @override
  String get libraryAutoScanDaily => 'Diariamente';

  @override
  String get libraryAutoScanWeekly => 'Semanalmente';

  @override
  String get libraryActions => 'Acciones';

  @override
  String get libraryScan => 'Escanear librería';

  @override
  String get libraryScanSubtitle => 'Escanear archivos de audio';

  @override
  String get libraryScanSelectFolderFirst => 'Primero seleccione una carpeta';

  @override
  String get libraryCleanupMissingFiles => 'Limpiar archivos faltantes';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Remover entradas para archivos que ya no existen';

  @override
  String get libraryClear => 'Limpiar librería';

  @override
  String get libraryClearSubtitle => 'Remover todas las canciones escaneadas';

  @override
  String get libraryClearConfirmTitle => 'Limpiar librería';

  @override
  String get libraryClearConfirmMessage =>
      'Esto removerá todas las canciones escaneadas de tu librería. Los archivos de música no serán eliminados.';

  @override
  String get libraryAbout => 'Acerca de la librería local';

  @override
  String get libraryAboutDescription =>
      'Escanea tu colección de música para detectar duplicados al descargar. Permite formatos FLAC, M4A, MP3, Opus, y OGG. La meta data será leída de los archivos cuando sea posible.';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return 'Último escaneo: $time';
  }

  @override
  String get libraryLastScannedNever => 'Nunca';

  @override
  String get libraryScanning => 'Escaneando...';

  @override
  String get libraryScanFinalizing => 'Finalizando la biblioteca...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$progress% de $total archivos';
  }

  @override
  String get libraryInLibrary => 'En la biblioteca';

  @override
  String libraryRemovedMissingFiles(int count) {
    return 'Eliminados $count archivos faltantes de la biblioteca';
  }

  @override
  String get libraryCleared => 'Biblioteca vaciada';

  @override
  String get libraryStorageAccessRequired =>
      'Permiso de acceso al almacenamiento requerido';

  @override
  String get libraryStorageAccessMessage =>
      'SpotiFLAC necesita acceso al almacenamiento para escanear tu biblioteca musical. Por favor, concede el permiso en los ajustes.';

  @override
  String get libraryFolderNotExist => 'La carpeta seleccionada no existe';

  @override
  String get librarySourceDownloaded => 'Descargado';

  @override
  String get librarySourceLocal => 'En el dispositivo';

  @override
  String get libraryFilterAll => 'Todos';

  @override
  String get libraryFilterDownloaded => 'Descargado';

  @override
  String get libraryFilterLocal => 'En el dispositivo';

  @override
  String get libraryFilterTitle => 'Filtros';

  @override
  String get libraryFilterReset => 'Restablecer';

  @override
  String get libraryFilterApply => 'Aplicar';

  @override
  String get libraryFilterSource => 'Fuente';

  @override
  String get libraryFilterQuality => 'Calidad';

  @override
  String get libraryFilterQualityHiRes => 'Hi-Res (24-bit)';

  @override
  String get libraryFilterQualityCD => 'CD (16-bit)';

  @override
  String get libraryFilterQualityLossy => 'Con pérdida';

  @override
  String get libraryFilterFormat => 'Formato';

  @override
  String get libraryFilterMetadata => 'Información';

  @override
  String get libraryFilterMetadataComplete => 'Información completa';

  @override
  String get libraryFilterMetadataMissingAny => 'Falta información (meta-data)';

  @override
  String get libraryFilterMetadataMissingYear => 'Falta año';

  @override
  String get libraryFilterMetadataMissingGenre => 'Falta género';

  @override
  String get libraryFilterMetadataMissingAlbumArtist =>
      'Falta artiste de álbum';

  @override
  String get libraryFilterSort => 'Ordenar';

  @override
  String get libraryFilterSortLatest => 'Reciente';

  @override
  String get libraryFilterSortOldest => 'Más antiguo';

  @override
  String get libraryFilterSortAlbumAsc => 'Álbum (A-Z)';

  @override
  String get libraryFilterSortAlbumDesc => 'Álbum (Z-A)';

  @override
  String get libraryFilterSortGenreAsc => 'Género (A-Z)';

  @override
  String get libraryFilterSortGenreDesc => 'Género (Z-A)';

  @override
  String get timeJustNow => 'Hace un momento';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos atrás',
      one: 'hace 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count horas atrás',
      one: '1 hora atrás',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => '¡Bienvenido a SpotiFLAC!';

  @override
  String get tutorialWelcomeDesc =>
      'Aprende cómo descargar tu música favorita en excelente calidad. Este tutorial te mostrará lo básico.';

  @override
  String get tutorialWelcomeTip1 =>
      'Descarga música de Spotify, Deezer, o pega cualquier URL soportada';

  @override
  String get tutorialWelcomeTip2 =>
      'Obtén audio de calidad FLAC mediante las extensiones de descarga instaladas';

  @override
  String get tutorialWelcomeTip3 =>
      'Información automática, portadas y letras integradas';

  @override
  String get tutorialSearchTitle => 'Buscando música';

  @override
  String get tutorialSearchDesc =>
      'Hay dos maneras fáciles de encontrar la música que quieres descargar.';

  @override
  String get tutorialDownloadTitle => 'Descargando música';

  @override
  String get tutorialDownloadDesc =>
      'Descargar música es simple y rápido. Así es como funciona.';

  @override
  String get tutorialLibraryTitle => 'Tu biblioteca';

  @override
  String get tutorialLibraryDesc =>
      'Toda tu música descargada está organizada en la pestaña Biblioteca.';

  @override
  String get tutorialLibraryTip1 =>
      'Ver progreso de descarga y cola en la pestaña de biblioteca';

  @override
  String get tutorialLibraryTip2 =>
      'Pulsa cualquier pista para abrirla con tu reproductor multimedia';

  @override
  String get tutorialLibraryTip3 =>
      'Cambiar modo de vista entre modo lista y cuadrícula para mejorar navegación';

  @override
  String get tutorialExtensionsTitle => 'Extensiones';

  @override
  String get tutorialExtensionsDesc =>
      'Extiende las capacidades de la aplicación con extensiones creadas por la comunidad.';

  @override
  String get tutorialExtensionsTip1 =>
      'Navega por la pestaña de repo para descubrir extensiones';

  @override
  String get tutorialExtensionsTip2 =>
      'Añadir nuevos proveedores de descargas o fuentes de búsqueda';

  @override
  String get tutorialExtensionsTip3 =>
      'Obtén letras, información mejorada y más características';

  @override
  String get tutorialSettingsTitle => 'Personaliza tu experiencia';

  @override
  String get tutorialSettingsDesc =>
      'Personaliza la aplicación en Ajustes según tus preferencias.';

  @override
  String get tutorialSettingsTip1 =>
      'Cambia la ubicación de las descargas y la organización de las carpetas';

  @override
  String get tutorialSettingsTip2 =>
      'Configura la calidad de audio predeterminada y las preferencias de formato';

  @override
  String get tutorialSettingsTip3 =>
      'Personaliza el tema y el aspecto de la aplicación';

  @override
  String get tutorialReadyMessage =>
      '¡Todo preparado!, puedes descargar tu música favorita.';

  @override
  String get libraryForceFullScan => 'Forzar análisis completo';

  @override
  String get libraryForceFullScanSubtitle =>
      'Volver a escanear archivos, ignorando caché';

  @override
  String get cleanupOrphanedDownloads => 'Borrar descargar huérfanas';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      'Borrar historial de archivos que no existen';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return 'Se removieron $count entradas huérfanas del historial.';
  }

  @override
  String get cleanupOrphanedDownloadsNone =>
      'Sin entradas huérfanas encontradas';

  @override
  String get cacheTitle => 'Almacenamiento y caché';

  @override
  String get cacheSummaryTitle => 'Resumen de la caché';

  @override
  String get cacheSummarySubtitle =>
      'Limpiar la caché no eliminará los archivos de música descargados.';

  @override
  String cacheEstimatedTotal(String size) {
    return 'Uso estimado de caché: $size';
  }

  @override
  String get cacheSectionStorage => 'Datos almacenados en caché';

  @override
  String get cacheSectionMaintenance => 'Mantenimiento';

  @override
  String get cacheAppDirectory => 'Directorio de caché';

  @override
  String get cacheAppDirectoryDesc =>
      'Respuestas HTTP, datos WebView y otros datos temporales.';

  @override
  String get cacheTempDirectory => 'Directorio temporal';

  @override
  String get cacheTempDirectoryDesc =>
      'Archivos temporales de descargas y conversión de audio.';

  @override
  String get cacheCoverImage => 'Caché de imágenes de portada';

  @override
  String get cacheCoverImageDesc =>
      'Álbum descargado y portada de pista. Se volverá a descargar cuando se vea.';

  @override
  String get cacheLibraryCover => 'Caché de portada (biblioteca)';

  @override
  String get cacheLibraryCoverDesc =>
      'Portada extraída de archivos locales. Se extraerá de nuevo en el próximo escaneo.';

  @override
  String get libraryPlaybackNormalization => 'Volume normalization';

  @override
  String get libraryPlaybackNormalizationSubtitle =>
      'Even out loudness between tracks using their ReplayGain or R128 tags, when present';

  @override
  String get cacheAudioAnalysis => 'Audio analysis cache';

  @override
  String get cacheAudioAnalysisDesc =>
      'Saved spectrograms and analysis results. Will re-analyze on next open.';

  @override
  String get cacheExploreFeed => 'Explorar caché de inicio';

  @override
  String get cacheExploreFeedDesc =>
      'Explorar contenido de pestaña (nuevas versiones, tendencias). Se actualiza en cada visita.';

  @override
  String get cacheTrackLookup => 'Caché de búsqueda';

  @override
  String get cacheTrackLookupDesc =>
      'Búsqueda de ID de Spotify/Deezer. Limpiar podría ralentizar algunas búsquedas.';

  @override
  String get cacheCleanupUnusedDesc =>
      'Borre el historial de archivos huérfanos y las entradas en la biblioteca.';

  @override
  String get cacheNoData => 'No hay datos en caché';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$size en $count archivos';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count registros';
  }

  @override
  String cacheClearSuccess(String target) {
    return 'Limpiado: $target';
  }

  @override
  String get cacheClearConfirmTitle => '¿Limpiar caché?';

  @override
  String cacheClearConfirmMessage(String target) {
    return 'Esto borrará los datos en caché para $target. Los archivos descargados no se eliminan.';
  }

  @override
  String get cacheClearAllConfirmTitle => '¿Quieres limpiar todas las cachés?';

  @override
  String get cacheClearAllConfirmMessage =>
      'Esto borrará todo el caché de categorías en esta página. Los archivos descargados no se eliminan.';

  @override
  String get cacheClearAll => 'Borrar todo el caché';

  @override
  String get cacheCleanupUnused => 'Limpiar datos sin usar';

  @override
  String get cacheCleanupUnusedSubtitle =>
      'Borrar historial de descargas huérfanas y entradas  faltantes en biblioteca';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return 'Limpieza copletada: $downloadCount descargas huéranas, $libraryCount entradas faltantes de librería';
  }

  @override
  String get cacheRefreshStats => 'Actualizar estadisticas';

  @override
  String get trackSaveCoverArt => 'Guardar portada';

  @override
  String get trackSaveLyrics => 'Guardar letra (.lrc)';

  @override
  String get trackSaveLyricsProgress => 'Guardando letra...';

  @override
  String get trackReEnrich => 'Volver a enriquecer';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Buscar información en línea y incrustar al archivo';

  @override
  String get trackReEnrichFieldCover => 'Carátula';

  @override
  String get trackReEnrichFieldLyrics => 'Letra';

  @override
  String get trackReEnrichFieldBasicTags => 'Álbum, Artista del Álbum';

  @override
  String get trackReEnrichFieldTrackInfo => 'Número de pista(s) y disco(s).';

  @override
  String get trackReEnrichFieldReleaseInfo => 'Fecha e ISRC';

  @override
  String get trackReEnrichFieldExtra => 'Género, etiqueta, derechos de autor';

  @override
  String get trackReEnrichSelectAll => 'Seleccionar todos';

  @override
  String get trackEditMetadata => 'Editar información';

  @override
  String trackCoverSaved(String fileName) {
    return 'Carátula guardada en $fileName';
  }

  @override
  String get trackCoverNoSource => 'No hay fuente de portadas disponible';

  @override
  String trackLyricsSaved(String fileName) {
    return 'Letra guardada en $fileName';
  }

  @override
  String get trackReEnrichProgress => 'Obteniendo información...';

  @override
  String get trackReEnrichSearching => 'Buscando información en línea...';

  @override
  String get trackReEnrichSuccess => 'Información ';

  @override
  String get trackReEnrichFfmpegFailed =>
      'Información incrustada con FFmpeg falló';

  @override
  String get queueFlacAction => 'Encolar FLAC';

  @override
  String queueFlacConfirmMessage(int count) {
    return 'Buscar coincidencias en línea para las pistas seleccionadas y en cola de descargas\n\nArchivos existentes no serán afectados o borrados.\n\nSolo coincidencia de alta confianza serán puestas automáticamente.\n\n$count seleccionado';
  }

  @override
  String get queueFlacNoReliableMatches =>
      'Sin coincidencias en línea de confianza';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return 'Añadido $addedCount pistas a la cola, omitidas $skippedCount';
  }

  @override
  String trackSaveFailed(String error) {
    return 'Error: $error';
  }

  @override
  String get trackConvertFormat => 'Convertir formato';

  @override
  String get trackConvertTitle => 'Convertir audio';

  @override
  String get trackConvertTargetFormat => 'Formato de destino';

  @override
  String get trackConvertBitrate => 'Tasa de bits';

  @override
  String get trackConvertKeepOriginal => 'Keep original file';

  @override
  String get trackConvertKeepOriginalDescription =>
      'Add the converted file as a separate library entry';

  @override
  String get trackConvertConfirmTitle => 'Confirmar conversión';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return '¿Convertir desde $sourceFormat a $targetFormat a $bitrate?';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Convertir de $sourceFormat a $targetFormat? \n(Sin pérdidas)\n\nEl archivo original será eliminado después de la conversión.';
  }

  @override
  String trackConvertConfirmKeepOriginal(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Convert from $sourceFormat to $targetFormat?\n\nThe original file will be kept and the converted file will be added as a separate library entry.';
  }

  @override
  String get trackConvertLosslessHint =>
      'Conversión sin pérdidas — sin pérdida de calidad';

  @override
  String get trackConvertConverting => 'Convirtiendo Audio...';

  @override
  String trackConvertSuccess(String format) {
    return 'Convertido a $format con éxito';
  }

  @override
  String get trackConvertFailed => 'La conversión ha fallado';

  @override
  String get cueSplitTitle => 'Dividir hoja CUE';

  @override
  String cueSplitAlbum(String album) {
    return 'Álbum: $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return 'Artista: $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count pistas';
  }

  @override
  String get cueSplitConfirmTitle => 'Dividir álbum CUE';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return '¿Dividir \"$album\" en archivos FLAC individuales $count?\n\nLos archivos se guardarán en el mismo directorio.';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'Dividiendo hoja CUE... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return 'Se dividió correctamente en $count pistas';
  }

  @override
  String get cueSplitFailed => 'Fallo al dividir CUE';

  @override
  String get cueSplitNoAudioFile =>
      'No se encontró el archivo de audio para esta hoja CUE';

  @override
  String get cueSplitButton => 'Dividir en pistas';

  @override
  String get actionCreate => 'Crear';

  @override
  String get collectionFoldersTitle => 'Mis carpetas';

  @override
  String get collectionWishlist => 'Lista de deseos';

  @override
  String get collectionLoved => 'Me gusta';

  @override
  String get collectionFavoriteArtists => 'Artistas favoritos';

  @override
  String get collectionPlaylist => 'Lista de reproducción';

  @override
  String get collectionAddToPlaylist => 'Añadir a la lista';

  @override
  String get collectionCreatePlaylist => 'Crear lista de reproducción';

  @override
  String get collectionNoPlaylistsYet => 'Aún no hay listas de reproducción';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistas',
      one: '1 pista',
    );
    return '$_temp0';
  }

  @override
  String collectionArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artistas',
      one: '1 artista',
    );
    return '$_temp0';
  }

  @override
  String collectionAddedToPlaylist(String playlistName) {
    return 'Añadida a \"$playlistName\"';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return 'Ya está en \"$playlistName\"';
  }

  @override
  String get collectionPlaylistNameHint => 'Nombre de la lista de reproducción';

  @override
  String get collectionPlaylistNameRequired =>
      'El nombre de la lista de reproducción es obligatorio';

  @override
  String get collectionRenamePlaylist => 'Renombrar lista de reproducción';

  @override
  String get collectionDeletePlaylist => 'Eliminar lista de reproducción';

  @override
  String get collectionPlaylistRenamed => 'Lista de reproducción renombrada';

  @override
  String get collectionWishlistEmptyTitle => 'La lista de deseos está vacía';

  @override
  String get collectionWishlistEmptySubtitle =>
      'Toca el botón + en las pistas para guardar las que quieras descargar más tarde';

  @override
  String get collectionLovedEmptyTitle => 'La carpeta «Me gusta» está vacía';

  @override
  String get collectionLovedEmptySubtitle =>
      'Toca «Me gusta» en las pistas para guardar tus favoritas.';

  @override
  String get collectionFavoriteArtistsEmptyTitle =>
      'Aún no hay artistas favoritos';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      'Toca el corazón en la página del artista para guardarlo aquí';

  @override
  String get collectionPlaylistEmptyTitle =>
      'La lista de reproducción está vacía';

  @override
  String get collectionPlaylistEmptySubtitle =>
      'Mantén presionado el botón + en cualquier pista para añadirla aquí';

  @override
  String get collectionRemoveFromPlaylist =>
      'Quitar de la lista de reproducción';

  @override
  String get collectionRemoveFromFolder => 'Quitar de la carpeta';

  @override
  String collectionAddedToLoved(String trackName) {
    return '\"$trackName\" se agregó a «Me gusta»';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\"$trackName\" se eliminó de «Me gusta»';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '\"$trackName\" se agregó a la lista de deseos';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '\"$trackName\" se eliminó de la lista de deseos';
  }

  @override
  String collectionAddedToFavoriteArtists(String artistName) {
    return '\"$artistName\" se agregó a Artistas favoritos';
  }

  @override
  String collectionRemovedFromFavoriteArtists(String artistName) {
    return '\"$artistName\" se eliminó de Artistas favoritos';
  }

  @override
  String get trackOptionAddToLoved => 'Agregar a «Me gusta»';

  @override
  String get trackOptionRemoveFromLoved => 'Quitar de «Me gusta»';

  @override
  String get trackOptionAddToWishlist => 'Añadir a la lista de deseos';

  @override
  String get trackOptionRemoveFromWishlist => 'Quitar de la lista de deseos';

  @override
  String get artistOptionAddToFavorites => 'Añadir a artistas favoritos';

  @override
  String get artistOptionRemoveFromFavorites => 'Quitar de Artistas favoritos';

  @override
  String get collectionPlaylistChangeCover => 'Cambiar imagen de portada';

  @override
  String get collectionPlaylistRemoveCover => 'Eliminar imagen de portada';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return 'Compartir $count $_temp0';
  }

  @override
  String get selectionShareNoFiles =>
      'No se encontraron archivos para compartir';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return 'Convertir $count $_temp0';
  }

  @override
  String get selectionConvertNoConvertible =>
      'No se seleccionaron pistas que se puedan convertir';

  @override
  String get selectionBatchConvertConfirmTitle => 'Conversión por lotes';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '¿Convertir $count $_temp0 a $format con una tasa de bits de $bitrate?\n\nLos archivos originales se eliminarán después de la conversión.';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return '¿Convertir $count $_temp0 a $format? (Sin pérdida — no hay pérdida de calidad)\n\nLos archivos originales se eliminarán después de la conversión.';
  }

  @override
  String selectionBatchConvertConfirmKeepOriginal(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format?\n\nOriginal files will be kept and converted files will be added as separate library entries.';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return 'Se convirtieron $success de $total pistas a $format';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count descargado';
  }

  @override
  String get downloadUseAlbumArtistForFoldersAlbumSubtitle =>
      'Carpeta nombrada según la etiqueta Artista del álbum';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      'Carpeta nombrada según la etiqueta Artista de la pista';

  @override
  String get lyricsProvidersTitle => 'Prioridad de proveedores de letras';

  @override
  String get lyricsProvidersDescription =>
      'Activa, desactiva y reordena las fuentes de letras. Los proveedores se prueban de arriba hacia abajo hasta encontrar letras.';

  @override
  String get lyricsProvidersInfoText =>
      'Los proveedores de letras de extensiones se ejecutan antes que los proveedores integrados. Debe permanecer habilitado al menos un proveedor.';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return 'Activados ($count)';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return 'Desactivados ($count)';
  }

  @override
  String get lyricsProvidersAtLeastOne =>
      'Debe permanecer habilitado al menos un proveedor';

  @override
  String get lyricsProvidersSaved =>
      'Prioridad de proveedores de letras guardada';

  @override
  String get lyricsProvidersDiscardContent =>
      'Tienes cambios sin guardar que se perderán.';

  @override
  String get lyricsProviderLrclibDesc =>
      'Base de datos de letras sincronizadas de código abierto';

  @override
  String get lyricsProviderNeteaseDesc =>
      'NetEase Cloud Music (buena para canciones asiáticas)';

  @override
  String get lyricsProviderMusixmatchDesc =>
      'La base de datos de letras más grande (multilingüe)';

  @override
  String get lyricsProviderAppleMusicDesc =>
      'Letras sincronizadas palabra por palabra (a través de proxy)';

  @override
  String get lyricsProviderQqMusicDesc =>
      'QQ Music (buena para canciones chinas, a\ntravés de proxy)';

  @override
  String get lyricsProviderLyricsPlusDesc =>
      'Letras tipo karaoke palabra por palabra (Apple/ Musixmatch/Spotify/QQ, a través de proxy)';

  @override
  String get lyricsProviderExtensionDesc => 'Proveedor de extensiones';

  @override
  String get safMigrationTitle =>
      'Se requiere actualización del almacenamiento';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC ahora utiliza el Android Storage Access Framework (SAF) para las descargas. Esto soluciona los errores de «permiso denegado» en Android 10 y versiones posteriores.';

  @override
  String get safMigrationMessage2 =>
      'Por favor, vuelve a seleccionar la carpeta de descargas para cambiar al nuevo sistema de almacenamiento.';

  @override
  String get safMigrationSuccess =>
      'Carpeta de descargas actualizada al modo SAF';

  @override
  String get settingsDonate => 'Apoya el desarrollo';

  @override
  String get settingsDonateSubtitle => 'Compra un café al desarrollador';

  @override
  String get settingsBackup => 'Copia de seguridad y Restauración';

  @override
  String get settingsBackupSubtitle =>
      'Transfiere tu biblioteca, historial y configuración a un nuevo dispositivo';

  @override
  String get backupTitle => 'Copia de seguridad y Restauración';

  @override
  String get backupExportSectionTitle => 'Crear copia de seguridad';

  @override
  String get backupExportSectionDescription =>
      'Guarda tu configuración, historial de descargas, pistas con «Me gusta», lista de deseos, artistas favoritos y listas de reproducción en un solo archivo que puedes conservar o transferir a otro teléfono.';

  @override
  String get backupExportButton => 'Crear archivo de copia de seguridad';

  @override
  String get backupImportSectionTitle => 'Restaurar copia de seguridad';

  @override
  String get backupImportSectionDescription =>
      'Selecciona un archivo de copia de seguridad para restaurar tus datos. Esto reemplazará la configuración, el historial y la biblioteca actuales en este dispositivo.';

  @override
  String get backupImportButton => 'Elegir archivo de copia de seguridad';

  @override
  String get backupCreated => 'Copia de seguridad creada';

  @override
  String get backupCreateFailed => 'No se pudo crear la copia de seguridad';

  @override
  String get backupRestoreConfirmTitle => '¿Restaurar esta copia de seguridad?';

  @override
  String get backupRestoreConfirmMessage =>
      'Esto reemplazará tu configuración actual, historial de descargas, pistas con «Me gusta», lista de deseos y listas de reproducción con el contenido de la copia de seguridad. Esto no se puede deshacer.';

  @override
  String get backupRestoreConfirmButton => 'Restaurar';

  @override
  String get backupRestored => 'Copia de seguridad restaurada correctamente';

  @override
  String get backupRestoreFailed => 'Fallo al restaurar la copia de seguridad';

  @override
  String get backupInvalidFile =>
      'Este archivo no es una copia de seguridad válida de SpotiFLAC';

  @override
  String get backupRestoreRestartHint =>
      'Reinicie la aplicación para asegurarse de que cada cambio se aplique.';

  @override
  String get backupContentsTitle => 'Contenido de la copia de seguridad';

  @override
  String get backupContentsSettings => 'Configuración de la aplicación';

  @override
  String backupContentsHistory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$count historial $_temp0';
  }

  @override
  String backupContentsLiked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas con «Me gusta»',
      one: 'pista con «Me gusta»',
    );
    return '$count $_temp0';
  }

  @override
  String backupContentsWishlist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas en la lista de deseos',
      one: 'pista en la lista de deseos',
    );
    return '$count $_temp0';
  }

  @override
  String backupContentsPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas de reproducción',
      one: '1 lista de reproducción',
    );
    return '$_temp0';
  }

  @override
  String backupContentsArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artistas favoritos',
      one: '1 artista favorito',
    );
    return '$_temp0';
  }

  @override
  String backupContentsExtensions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count extensiones',
      one: '1 extensión',
    );
    return '$_temp0';
  }

  @override
  String get backupIncludeSecrets => 'Include extension credentials';

  @override
  String get backupIncludeSecretsDescription =>
      'Los tokens y las claves API de las extensiones se guardarán en el archivo de copia de seguridad. Mantenga el archivo privado. Cuando está desactivado, volverá a introducirlos después de restaurar.';

  @override
  String backupExtensionsRestoreFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'extensions',
      one: 'extension',
    );
    return '$count $_temp0 could not be reinstalled. Install them manually from the repo.';
  }

  @override
  String get tooltipLoveAll => 'Favoritos';

  @override
  String get tooltipAddToPlaylist => 'Añadir a la lista de reproducción';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return 'Eliminadas $count pistas de Favoritos';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return 'Agregadas $count pistas de Favoritos';
  }

  @override
  String get dialogDownloadAllTitle => 'Descargar todo';

  @override
  String dialogDownloadAllMessage(int count) {
    return '¿Descargar $count pistas?';
  }

  @override
  String get homeSkipAlreadyDownloaded => 'Omitir canciones ya descargadas';

  @override
  String get homeGoToAlbum => 'Ir al álbum';

  @override
  String get homeAlbumInfoUnavailable =>
      'La información del álbum no está disponible';

  @override
  String get snackbarLoadingCueSheet => 'Cargando hoja CUE...';

  @override
  String get snackbarMetadataSaved => 'Metadatos guardados correctamente';

  @override
  String get snackbarFailedToEmbedLyrics => 'Error al incrustar letras';

  @override
  String get snackbarFailedToWriteStorage =>
      'Error al escribir de vuelta al almacenamiento';

  @override
  String snackbarError(String error) {
    return 'Error: $error';
  }

  @override
  String get snackbarNoActionDefined =>
      'Ninguna acción definida para este botón';

  @override
  String get noTracksFoundForAlbum =>
      'No se encontraron pistas para este álbum';

  @override
  String get downloadLocationSubtitle =>
      'Elige dónde guardar tus pistas descargadas';

  @override
  String get storageModeAppFolder => 'Carpeta de la App (Recomendado)';

  @override
  String get storageModeAppFolderSubtitle =>
      'Guarda en Music/SpotiFLAC por defecto';

  @override
  String get storageModeSaf => 'Carpeta personalizada (SAF)';

  @override
  String get storageModeSafSubtitle =>
      'Escoge cualquier carpeta, incluyendo la tarjeta SD';

  @override
  String get downloadFolderAccessLostTitle => 'Download folder access lost';

  @override
  String get downloadFolderAccessLostSubtitle =>
      'Downloads will fail until you re-select the folder';

  @override
  String get downloadFolderReselect => 'Re-select folder';

  @override
  String get downloadErrorSafPermissionLost =>
      'SAF permission invalid or revoked. Please reconfigure download location in Settings.';

  @override
  String get downloadErrorFolderAccessLost =>
      'Download folder access lost. Please re-select your download folder in Settings.';

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
    return 'Usa $artist, $title, $album, $track, $year, $date, $disc como marcadores de posición.';
  }

  @override
  String get downloadFilenameInsertTag => 'Toca para insertar etiqueta:';

  @override
  String get downloadSeparateSinglesEnabled =>
      'Sencillos y EPs guardados en una carpeta separada';

  @override
  String get downloadSeparateSinglesDisabled =>
      'Sencillos y álbumes guardados en la misma carpeta';

  @override
  String get downloadArtistNameFilters => 'Filtros de Nombre del Artista';

  @override
  String get downloadCreatePlaylistSourceFolder => 'Playlist Source Folder';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      'A subfolder is created for each playlist';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      'All tracks saved directly to download folder';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant =>
      'Handled by folder organization setting';

  @override
  String get downloadSongLinkRegion => 'Región de SongLink';

  @override
  String get downloadNetworkCompatibilityMode =>
      'Modo de compatibilidad de red';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Using legacy TLS settings for older networks';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Utilizando ajustes de red estándar';

  @override
  String get downloadAllowLocalNetwork => 'Allow Local Network Access';

  @override
  String get downloadAllowLocalNetworkEnabled =>
      'Requests to local/private addresses are allowed (for local proxy or custom DNS)';

  @override
  String get downloadAllowLocalNetworkDisabled =>
      'Local/private addresses are blocked for security';

  @override
  String get downloadSelectServiceToEnable =>
      'Select a provider with quality options to enable this option';

  @override
  String get downloadEmbedLyricsDisabled => 'Enable metadata embedding first';

  @override
  String get downloadNeteaseIncludeTranslation =>
      'Netease: Include Translation';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Chinese translation lines included';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Solo letras originales';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease: Include Romanization';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled =>
      'Romanization lines included';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled => 'No romanization';

  @override
  String get downloadAppleQqMultiPerson => 'Apple / QQ: Multi-Person Lyrics';

  @override
  String get downloadAppleQqMultiPersonEnabled =>
      'Speaker labels included for duets and group tracks';

  @override
  String get downloadAppleQqMultiPersonDisabled =>
      'Standard lyrics without speaker labels';

  @override
  String get downloadAppleElrcWordSync => 'Apple Music eLRC Word Sync';

  @override
  String get downloadAppleElrcWordSyncEnabled =>
      'Raw word-by-word timestamps preserved';

  @override
  String get downloadAppleElrcWordSyncDisabled =>
      'Safer line-by-line Apple Music lyrics';

  @override
  String get downloadMusixmatchLanguage => 'Idioma de Musixmatch';

  @override
  String get downloadMusixmatchLanguageAuto => 'Auto (original language)';

  @override
  String get downloadFilterContributing => 'Filter Contributing Artists';

  @override
  String get downloadFilterContributingEnabled =>
      'Contributing artists removed from Album Artist folder name';

  @override
  String get downloadFilterContributingDisabled =>
      'Full Album Artist string used';

  @override
  String get downloadProvidersNoneEnabled => 'No hay proveedores activos';

  @override
  String get downloadMusixmatchLanguageCode => 'Código de idioma';

  @override
  String get downloadMusixmatchLanguageHint => 'e.g. en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Introduce un código de idioma BCP-47 (por ejemplo, en, de, ja) para solicitar letras traducidas desde Musixmatch.';

  @override
  String get downloadMusixmatchAuto => 'Automático';

  @override
  String get downloadNetworkAnySubtitle => 'Usar Wi-Fi o datos móviles';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Las descargas se pausan con datos móviles';

  @override
  String get downloadSongLinkRegionDesc =>
      'Región usada al resolver enlaces de pistas mediante SongLink. Elige el país donde estén disponibles tus servicios de streaming.';

  @override
  String get snackbarUnsupportedAudioFormat => 'Formato de audio no soportado';

  @override
  String get cacheRefresh => 'Actualizar';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    String _temp1 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: 'listas de reproducción',
      one: 'lista de reproducción',
    );
    return '¿Descargar $trackCount $_temp0 de $playlistCount $_temp1?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'listas de reproducción',
      one: 'lista de reproducción',
    );
    return 'Descargar $count $_temp0';
  }

  @override
  String get bulkDownloadSelectPlaylists =>
      'Selecciona listas de reproducción para descargar';

  @override
  String get snackbarSelectedPlaylistsEmpty =>
      'Las listas de reproducción seleccionadas no tienen pistas';

  @override
  String playlistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas de reproducción',
      one: '1 lista de reproducción',
    );
    return '$_temp0';
  }

  @override
  String get editMetadataAutoFill => 'Autocompletar desde internet';

  @override
  String get editMetadataAutoFillDesc =>
      'Selecciona los campos para rellenar automáticamente con metadatos en línea';

  @override
  String get editMetadataAutoFillFetch => 'Recuperar y llenar';

  @override
  String get editMetadataAutoFillSearching => 'Buscando en línea...';

  @override
  String get editMetadataAutoFillNoResults =>
      'No hay información coincidente en línea';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'campos',
      one: 'campo',
    );
    return 'Se completaron $count $_temp0 con metadatos en línea';
  }

  @override
  String get editMetadataAutoFillNoneSelected =>
      'Selecciona al menos un campo para autocompletar';

  @override
  String get editMetadataFieldTitle => 'Título';

  @override
  String get editMetadataFieldArtist => 'Artista';

  @override
  String get editMetadataFieldAlbum => 'Álbum';

  @override
  String get editMetadataFieldAlbumArtist => 'Artista del álbum';

  @override
  String get editMetadataFieldDate => 'Fecha';

  @override
  String get editMetadataFieldTrackNum => 'Pista #';

  @override
  String get editMetadataFieldDiscNum => 'Disco #';

  @override
  String get editMetadataFieldGenre => 'Género';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => 'Discográfica';

  @override
  String get editMetadataFieldCopyright => 'Derechos de autor';

  @override
  String get editMetadataFieldCover => 'Carátula';

  @override
  String get editMetadataSelectAll => 'Todos';

  @override
  String get editMetadataSelectEmpty => 'Solo vacíos';

  @override
  String queueDownloadingCount(int count) {
    return 'Descargando ($count)';
  }

  @override
  String get queueFilteringIndicator => 'Filtrando...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistas',
      one: '1 pista',
    );
    return '$_temp0';
  }

  @override
  String queueAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count álbumes',
      one: '1 álbum',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyAlbums => 'No se han descargado álbumes';

  @override
  String get queueEmptyAlbumsSubtitle =>
      'Descarga varias canciones de un álbum para verlas aquí';

  @override
  String get queueEmptySingles => 'No hay descargas';

  @override
  String get queueEmptySinglesSubtitle =>
      'Las descargas de pistas individuales aparecerán aquí';

  @override
  String get queueEmptyHistory => 'No hay historial de descargas';

  @override
  String get queueEmptyHistorySubtitle => 'Downloaded tracks will appear here';

  @override
  String get selectionAllPlaylistsSelected => 'Todas las listas seleccionadas';

  @override
  String get selectionTapPlaylistsToSelect =>
      'Pulsa listas de reproducción para seleccionar';

  @override
  String get selectionSelectPlaylistsToDelete => 'Select playlists to delete';

  @override
  String get audioAnalysisTitle => 'Audio Quality Analysis';

  @override
  String get audioAnalysisDescription =>
      'Verify lossless quality with spectrum analysis';

  @override
  String get audioAnalysisAnalyzing => 'Analizando audio...';

  @override
  String get audioAnalysisSampleRate => 'Frecuencia de muestreo';

  @override
  String get audioAnalysisCodec => 'Códec';

  @override
  String get audioAnalysisContainer => 'Contenedor';

  @override
  String get audioAnalysisDecodedFormat => 'Formato decodificado';

  @override
  String get audioAnalysisBitDepth => 'Profundidad de bits';

  @override
  String get audioAnalysisChannels => 'Canales';

  @override
  String get audioAnalysisDuration => 'Duración';

  @override
  String get audioAnalysisNyquist => 'Nyquist';

  @override
  String get audioAnalysisFileSize => 'Tamaño';

  @override
  String get audioAnalysisDynamicRange => 'Rango dinámico';

  @override
  String get audioAnalysisPeak => 'Peak';

  @override
  String get audioAnalysisRms => 'RMS';

  @override
  String get audioAnalysisLufs => 'LUFS';

  @override
  String get audioAnalysisTruePeak => 'True Peak';

  @override
  String get audioAnalysisClipping => 'Clipping';

  @override
  String get audioAnalysisNoClipping => 'No clipping';

  @override
  String get audioAnalysisSpectralCutoff => 'Spectral Cutoff';

  @override
  String get audioAnalysisChannelStats => 'Per-channel Stats';

  @override
  String get audioAnalysisSamples => 'Muestras';

  @override
  String get audioAnalysisRescan => 'Volver a analizar';

  @override
  String get audioAnalysisRescanning => 'Volviendo a analizar audio...';

  @override
  String get extensionsHomeFeedProvider => 'Home Feed Provider';

  @override
  String get extensionsHomeFeedDescription =>
      'Choose which extension provides the home feed on the main screen';

  @override
  String get extensionsHomeFeedAuto => 'Auto';

  @override
  String get extensionsHomeFeedAutoSubtitle =>
      'Seleccionar automáticamente la mejor disponible';

  @override
  String get extensionsHomeFeedOff => 'Desactivado';

  @override
  String get extensionsHomeFeedOffSubtitle =>
      'Do not show the home feed on the main screen';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return 'Use $extensionName home feed';
  }

  @override
  String get extensionsNoHomeFeedExtensions => 'No extensions with home feed';

  @override
  String get cancelDownloadTitle => '¿Cancelar descarga?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'This will cancel the active download for \"$trackName\".';
  }

  @override
  String get cancelDownloadKeep => 'Mantener';

  @override
  String get metadataSaveFailedFfmpeg => 'Failed to save metadata via FFmpeg';

  @override
  String get metadataSaveFailedStorage =>
      'Failed to write metadata back to storage';

  @override
  String snackbarFolderPickerFailed(String error) {
    return 'Failed to open folder picker: $error';
  }

  @override
  String notifDownloadingTrack(String trackName) {
    return 'Downloading $trackName';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return 'Finalizando $trackName';
  }

  @override
  String get notifEmbeddingMetadata => 'Insertando información...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return 'Already in Library ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => 'Already in Library';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return 'Download Complete ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => 'Descarga completa';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return 'Downloads Finished ($completed done, $failed failed)';
  }

  @override
  String get notifVerificationRequiredTitle => 'Verification required';

  @override
  String get notifVerificationRequiredBody =>
      'Open the app to complete verification and resume downloads';

  @override
  String get notifAllDownloadsComplete => 'Todas las descargas completadas';

  @override
  String notifTracksDownloadedSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks downloaded successfully',
      one: '1 track downloaded successfully',
    );
    return '$_temp0';
  }

  @override
  String notifDownloadsFinishedBody(int completed, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      completed,
      locale: localeName,
      other: '$completed tracks downloaded',
      one: '1 track downloaded',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed failed',
      one: '1 failed',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get notifDownloadsCanceledTitle => 'Descargas canceladas';

  @override
  String notifDownloadsCanceledBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count downloads canceled by user',
      one: '1 download canceled by user',
    );
    return '$_temp0';
  }

  @override
  String get notifScanningLibrary => 'Escaneando biblioteca local';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total files • $percentage%';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned files scanned • $percentage%';
  }

  @override
  String get notifLibraryScanComplete => 'Escaneo de biblioteca completado';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count tracks indexed';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count excluded';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count errores';
  }

  @override
  String get notifLibraryScanFailed => 'Library scan failed';

  @override
  String get notifLibraryScanCancelled => 'Library scan cancelled';

  @override
  String get notifLibraryScanStopped => 'Scan stopped before completion.';

  @override
  String notifDownloadingUpdate(String version) {
    return 'Downloading SpotiFLAC Mobile v$version';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total MB • $percentage%';
  }

  @override
  String get notifUpdateReady => 'Actualización preparada';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC Mobile v$version downloaded. Tap to install.';
  }

  @override
  String get notifUpdateFailed => 'Update Failed';

  @override
  String get notifUpdateFailedBody =>
      'Could not download update. Try again later.';

  @override
  String get searchTracks => 'Pistas';

  @override
  String get homeSearchHintDefault => 'Paste supported URL or search...';

  @override
  String homeSearchHintProvider(String providerName) {
    return 'Search with $providerName...';
  }

  @override
  String get homeImportCsvTooltip => 'Importar CSV';

  @override
  String get homeChangeSearchProviderTooltip => 'Change search provider';

  @override
  String get actionPaste => 'Pegar';

  @override
  String get tutorialSearchHint => 'Pegar o buscar...';

  @override
  String get tutorialDownloadCompletedSemantics => 'Descarga completada';

  @override
  String get tutorialDownloadInProgressSemantics => 'Descarga en curso';

  @override
  String get tutorialStartDownloadSemantics => 'Comenzar descarga';

  @override
  String get optionsEmbedMetadata => 'Incrustar información';

  @override
  String get optionsEmbedMetadataSubtitleOn =>
      'Escribir información, carátulas y letras incrustadas en archivos';

  @override
  String get optionsEmbedMetadataSubtitleOff =>
      'Disabled (advanced): skip all metadata embedding';

  @override
  String get trackCoverNoEmbeddedArt => 'No embedded album art found';

  @override
  String get trackCoverReplace => 'Reemplazar portada';

  @override
  String get trackCoverPick => 'Elegir portada';

  @override
  String get trackCoverClearSelected => 'Borrar portada seleccionada';

  @override
  String get trackCoverCurrent => 'Portada actual';

  @override
  String get trackCoverSelected => 'Carátula seleccionada';

  @override
  String get trackCoverReplaceNotice =>
      'La portada seleccionada sustituirá a la portada actual incrustada cuando pulses Guardar.';

  @override
  String get actionStop => 'Detener';

  @override
  String get queueFinalizingDownload => 'Finalizando descarga';

  @override
  String get queueDownloadedFileMissing => 'Downloaded file missing';

  @override
  String get queueDownloadCompleted => 'Descarga completada';

  @override
  String get queueRateLimitTitle => 'Service rate limited';

  @override
  String get queueRateLimitMessage =>
      'This track may still be available. Wait a few minutes, reduce parallel downloads, then retry.';

  @override
  String appearanceSelectAccentColor(String hex) {
    return 'Selecciona un color de contraste $hex';
  }

  @override
  String get logAutoScrollOn => 'Auto-scroll ON';

  @override
  String get logAutoScrollOff => 'Auto-scroll OFF';

  @override
  String get logCopyLogs => 'Copy logs';

  @override
  String get logClearSearch => 'Limpiar búsqueda';

  @override
  String get logIssueIspBlockingLabel => 'ISP BLOCKING DETECTED';

  @override
  String get logIssueIspBlockingDescription =>
      'Your ISP may be blocking access to download services';

  @override
  String get logIssueIspBlockingSuggestion =>
      'Try using a VPN or change DNS to 1.1.1.1 or 8.8.8.8';

  @override
  String get logIssueRateLimitedLabel => 'RATE LIMITED';

  @override
  String get logIssueRateLimitedDescription =>
      'Too many requests to the service';

  @override
  String get logIssueRateLimitedSuggestion =>
      'Wait a few minutes before trying again';

  @override
  String get logIssueNetworkErrorLabel => 'NETWORK ERROR';

  @override
  String get logIssueNetworkErrorDescription => 'Connection issues detected';

  @override
  String get logIssueNetworkErrorSuggestion => 'Check your internet connection';

  @override
  String get logIssueTrackNotFoundLabel => 'TRACK NOT FOUND';

  @override
  String get logIssueTrackNotFoundDescription =>
      'Some tracks could not be found on download services';

  @override
  String get logIssueTrackNotFoundSuggestion =>
      'The track may not be available in lossless quality';

  @override
  String get clickableLookingUpArtist => 'Looking up artist...';

  @override
  String clickableInformationUnavailable(String type) {
    return '$type information not available';
  }

  @override
  String get extensionDetailsTags => 'Etiquetas';

  @override
  String get extensionDetailsInformation => 'Información';

  @override
  String get extensionUtilityFunctions => 'Utility Functions';

  @override
  String get actionDismiss => 'Descartar';

  @override
  String get setupChangeFolderTooltip => 'Change folder';

  @override
  String a11yOpenTrackByArtist(String trackName, String artistName) {
    return 'Open track $trackName by $artistName';
  }

  @override
  String a11yOpenItem(String itemType, String name) {
    return 'Abrir $itemType $name';
  }

  @override
  String a11yOpenItemCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'objetos',
      one: 'objeto',
    );
    return 'Abrir $title, $count $_temp0';
  }

  @override
  String a11yOpenAlbumByArtistTrackCount(
    String albumName,
    String artistName,
    int trackCount,
  ) {
    return 'Abrir álbum $albumName de $artistName, $trackCount pistas';
  }

  @override
  String a11yTrackByArtist(String trackName, String artistName) {
    return '$trackName de $artistName';
  }

  @override
  String a11ySelectAlbum(String albumName) {
    return 'Seleccionar álbum $albumName';
  }

  @override
  String a11yOpenAlbum(String albumName) {
    return 'Abrir álbum $albumName';
  }

  @override
  String get settingsFiles => 'Archivos y carpetas';

  @override
  String get settingsFilesSubtitle =>
      'Directorio de descarga, nombre de archivo y estructura de carpetas';

  @override
  String get settingsMetadata => 'Información';

  @override
  String get settingsMetadataSubtitle =>
      'Carátula, etiquetas, ReplayGain, proveedores';

  @override
  String get settingsLyrics => 'Letra';

  @override
  String get settingsLyricsSubtitle =>
      'Insertar, modo, proveedores, opciones de idioma';

  @override
  String get settingsApp => 'Aplicación';

  @override
  String get settingsAppSubtitle =>
      'Actualizaciones, datos, extensiones repo, depuración';

  @override
  String get sectionMetadataProviders => 'Proveedores';

  @override
  String get sectionDuplicates => 'Duplicados';

  @override
  String get sectionLyricsProviderOptions => 'Opciones del proveedor';

  @override
  String get metadataProvidersTitle => 'Prioridad de proveedor de información';

  @override
  String get metadataProvidersSubtitle =>
      'Arrastre para establecer orden de búsqueda y origen de información';

  @override
  String get downloadDeduplication => 'Saltar descargas duplicadas';

  @override
  String get downloadDeduplicationEnabled =>
      'Las pistas previamente descargadas se omitirán';

  @override
  String get downloadDeduplicationWithQualityVariants =>
      'Existing files at the selected quality will be skipped';

  @override
  String get downloadDeduplicationDisabled =>
      'Todas las pistas se descargarán independientemente del historial';

  @override
  String get downloadQualityVariants => 'Allow different quality versions';

  @override
  String get downloadQualityVariantsDescription =>
      'Conservar cada versión de calidad; añadir la calidad medida al nombre solo cuando el nombre ya esté en uso';

  @override
  String get trackOptionDownloadQualityVariant => 'Download another quality';

  @override
  String get downloadFallbackExtensions => 'Reslpado de extensiones';

  @override
  String get downloadFallbackExtensionsSubtitle =>
      'Elige qué extensiones se pueden utilizar como alternativa';

  @override
  String get editMetadataFieldDateHint => 'AAA-MM-DD o AAAA';

  @override
  String get editMetadataFieldTrackTotal => 'Total de pistas';

  @override
  String get editMetadataFieldDiscTotal => 'Total de discos';

  @override
  String get editMetadataFieldComposer => 'Compositor';

  @override
  String get editMetadataFieldComment => 'Comentario';

  @override
  String get editMetadataAdvanced => 'Avanzado';

  @override
  String get libraryFilterMetadataMissingTrackNumber => 'Falta número de pista';

  @override
  String get libraryFilterMetadataMissingDiscNumber => 'Falta número de álbum';

  @override
  String get libraryFilterMetadataMissingArtist => 'Falta artista';

  @override
  String get libraryFilterMetadataIncorrectIsrcFormat =>
      'Formato de ISRC erróneo';

  @override
  String get libraryFilterMetadataMissingLabel => 'Falta etiqueta';

  @override
  String collectionDeletePlaylistsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'listas de reproducción',
      one: 'lista',
    );
    return '¿Eliminar $count $_temp0?';
  }

  @override
  String collectionPlaylistsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'listas de reproducción',
      one: 'lista',
    );
    return '$count $_temp0 eliminadas';
  }

  @override
  String collectionAddedTracksToPlaylist(int count, String playlistName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return 'Añadido $count $_temp0 a $playlistName';
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
      other: 'pistas',
      one: 'pista',
    );
    return 'Añadido $count $_temp0 a $playlistName ($alreadyCount ya en la lista de reproducción)';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'objetos',
      one: 'objeto',
    );
    return '$count $_temp0';
  }

  @override
  String trackReEnrichSuccessWithFailures(
    int successCount,
    int total,
    int failedCount,
  ) {
    return 'Información enriquecida nuevamente con éxito\n($successCount/$total) - Fallaron: $failedCount';
  }

  @override
  String selectionDeleteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistas',
      one: 'pista',
    );
    return 'Eliminar $count $_temp0';
  }

  @override
  String queueDownloadSpeedStatus(String speed) {
    return 'Descargando - $speed MB/s';
  }

  @override
  String get queueDownloadStarting => 'Comenzando...';

  @override
  String get queueCheckingDownloadSession => 'Checking download session...';

  @override
  String get queueResolvingDownloadMetadata => 'Resolving track metadata...';

  @override
  String get queueResolvingDownloadStream => 'Preparing audio stream...';

  @override
  String get queueWaitingForVerification => 'Waiting for verification...';

  @override
  String get queueResumingAfterVerification => 'Resuming after verification...';

  @override
  String get a11ySelectTrack => 'Seleccionar pista';

  @override
  String get a11yDeselectTrack => 'No seleccionar pista';

  @override
  String a11yPlayTrackByArtist(String trackName, String artistName) {
    return 'Reproducir $trackName de $artistName';
  }

  @override
  String storeExtensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'extensiones',
      one: 'extensión',
    );
    return '$count $_temp0';
  }

  @override
  String storeRequiresVersion(String version) {
    return 'Requiere v$version+';
  }

  @override
  String get actionGo => 'Ir';

  @override
  String get logIssueSummary => 'Resumen de incidencias';

  @override
  String logTotalErrors(int count) {
    return 'Total de errores: $count';
  }

  @override
  String logAffectedDomains(String domains) {
    return 'Afectados: $domains';
  }

  @override
  String get libraryScanCancelled => 'Escaneo cancelado';

  @override
  String get libraryScanCancelledSubtitle =>
      'Puedes volver a intentar el escaneo cuando esté listo.';

  @override
  String libraryDownloadsHistoryExcluded(int count) {
    return '$count del historial de descargas (excluidos de la lista)';
  }

  @override
  String get downloadNativeWorker => 'Trabajador de descarga nativo';

  @override
  String get downloadNativeWorkerSubtitle =>
      'Servicio de Android en segundo plano para descargas de extensiones';

  @override
  String get extensionServiceStatus => 'Estado del servicio';

  @override
  String get extensionServiceHealth => 'Estado de servicio';

  @override
  String extensionHealthChecksConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'chequeos',
      one: 'chequeo',
    );
    return '$count $_temp0 ';
  }

  @override
  String get extensionOauthConnectHint =>
      'Pulsa para conectar a Spotify y rellenar el campo.';

  @override
  String extensionLastChecked(String time) {
    return 'Última comprobación $time';
  }

  @override
  String get extensionRefreshStatus => 'Actualizar estado';

  @override
  String get extensionCustomUrlHandling => 'Gestión de URL personalizada';

  @override
  String get extensionCustomUrlHandlingSubtitle =>
      'Esta extensión puede manejar enlaces de estos sitios';

  @override
  String get extensionCustomUrlHandlingShareHint =>
      'Comparte enlaces de estos sitios a SpotiFLAC Mobile y esta extensión los manejará.';

  @override
  String extensionSettingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ajustes',
      one: 'ajuste',
    );
    return '$count $_temp0';
  }

  @override
  String get extensionHealthOnline => 'En línea';

  @override
  String get extensionHealthDegraded => 'Degradado';

  @override
  String get extensionHealthOffline => 'Sin conexión';

  @override
  String get extensionHealthNotConfigured => 'Sin configurar';

  @override
  String get extensionHealthUnknown => 'Desconocido';

  @override
  String get extensionHealthRequired => 'requerido';

  @override
  String get extensionSettingNotSet => 'Sin establecer';

  @override
  String get extensionActionFailed => 'Error de acción';

  @override
  String get extensionEnterValue => 'Ingrese un valor';

  @override
  String get extensionHealthServiceOnline => 'Servicio en línea';

  @override
  String get extensionHealthServiceDegraded => 'Servicio degradado';

  @override
  String get extensionHealthServiceOffline => 'Servicio fuera de línea';

  @override
  String get extensionHealthServiceUnknown => 'Estado de servicio desconocido';

  @override
  String get audioAnalysisStereo => 'Estéreo';

  @override
  String get audioAnalysisMono => 'Mono';

  @override
  String trackOpenInService(String serviceName) {
    return 'Abrir en $serviceName';
  }

  @override
  String get trackLyricsEmbeddedSource => 'Incrustado';

  @override
  String get unknownAlbum => 'Álbum desconocido';

  @override
  String get unknownArtist => 'Artista desconocido';

  @override
  String get permissionAudio => 'Audio';

  @override
  String get permissionStorage => 'Almacenamiento';

  @override
  String get permissionNotification => 'Notificación';

  @override
  String get errorInvalidFolderSelected => 'Directorio seleccionado inválido';

  @override
  String get storeAnyVersion => 'Cualquier';

  @override
  String get storeCategoryMetadata => 'Información';

  @override
  String get storeCategoryDownload => 'Descargar';

  @override
  String get storeCategoryUtility => 'Utilidad';

  @override
  String get storeCategoryLyrics => 'Letras';

  @override
  String get storeCategoryIntegration => 'Integración';

  @override
  String get artistReleases => 'Lanzamientos';

  @override
  String get editMetadataSelectNone => 'None';

  @override
  String queueRetryAllFailed(int count) {
    return 'Retry $count failed';
  }

  @override
  String get settingsSaveDownloadHistory => 'Save download history';

  @override
  String get settingsSaveDownloadHistorySubtitle =>
      'Keep completed downloads in history and library views';

  @override
  String get dialogDisableHistoryTitle => 'Turn off download history?';

  @override
  String get dialogDisableHistoryMessage =>
      'Existing history will be cleared. Downloaded files will not be deleted.';

  @override
  String get dialogDisableAndClear => 'Turn off and clear';

  @override
  String get openInOtherServices => 'Open in Other Services';

  @override
  String get shareSheetNoExtensions => 'No other compatible services';

  @override
  String get shareSheetNotFound => 'Not found';

  @override
  String get shareSheetCopyLink => 'Copy Link';

  @override
  String shareSheetLinkCopied(Object service) {
    return '$service link copied';
  }

  @override
  String get libraryPlayback => 'Playback';

  @override
  String get libraryExternalPlayer => 'External player';

  @override
  String get libraryExternalPlayerSubtitle =>
      'Recommended for listening, best quality, gapless playback, EQ, and wider format support';

  @override
  String get libraryBuiltInPreviewPlayer => 'Built-in preview player';

  @override
  String get libraryBuiltInPreviewPlayerSubtitle =>
      'Only for quick local previews inside SpotiFLAC Mobile, not recommended for regular listening';

  @override
  String get libraryBuiltInPlayerInfo =>
      'The built-in player is a preview tool for checking local tracks quickly. Use an external music player for actual listening.';

  @override
  String get nowPlayingTitle => 'Now Playing';

  @override
  String get nowPlayingNothingPlaying => 'Nothing is playing';

  @override
  String get nowPlayingMinimize => 'Minimize';

  @override
  String get nowPlayingUpNext => 'Up next';

  @override
  String get nowPlayingDetails => 'Details';

  @override
  String get nowPlayingOpenInExternalPlayer => 'Open in external player';

  @override
  String get nowPlayingTabPlayer => 'Player';

  @override
  String get nowPlayingTabLyrics => 'Lyrics';

  @override
  String get nowPlayingNoLyrics => 'No lyrics in this file';

  @override
  String get nowPlayingLibraryEmpty => 'Your library is empty';

  @override
  String nowPlayingShuffleLibraryFailed(String error) {
    return 'Could not shuffle library: $error';
  }

  @override
  String get nowPlayingShuffleOn => 'Shuffle on';

  @override
  String get nowPlayingPlayInOrder => 'Play in order';

  @override
  String get nowPlayingShuffleLibrary => 'Shuffle library';

  @override
  String get nowPlayingQueueEmpty => 'Queue is empty';

  @override
  String get nowPlayingNoMetadata => 'No metadata available';

  @override
  String get announcementUnableToOpenLink =>
      'Unable to open link. Please try again.';

  @override
  String trackConvertLosslessOutputWithCap(String quality) {
    return 'Lossless output with $quality cap';
  }

  @override
  String trackConvertConfirmMessageLosslessCapped(
    String sourceFormat,
    String targetFormat,
    String quality,
  ) {
    return 'Convert from $sourceFormat to $targetFormat ($quality)?\n\nThe output stays in a lossless codec, but bit depth/sample rate will be capped. Original file will be deleted after conversion.';
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
      other: 'tracks',
      one: 'track',
    );
    return 'Convert $count $_temp0 to $format ($quality)?\n\nThe output stays in a lossless codec, but bit depth/sample rate will be capped. Original files will be deleted after conversion.';
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
      'Lyrics proxy for Musixmatch, Netease, Apple Music, QQ Music, Spotify, Deezer, YouTube, Kugou, and Genius';

  @override
  String get snackbarPlayingNext => 'Playing next';

  @override
  String get snackbarAddedToQueueGeneric => 'Added to queue';

  @override
  String selectionDeletePlaylistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Delete $count $_temp0';
  }

  @override
  String get actionShuffle => 'Shuffle';

  @override
  String get downloadPrimaryArtistOnlyOn => 'Primary only: On';

  @override
  String get downloadPrimaryArtistOnlyOff => 'Primary only: Off';

  @override
  String get downloadAlbumArtistMetadataPrimaryOnly =>
      'Album Artist metadata: Primary only';

  @override
  String get downloadAlbumArtistMetadataFull => 'Album Artist metadata: Full';

  @override
  String get trackConvertOriginal => 'Original';

  @override
  String get trackConvertOriginalQuality => 'Original quality';

  @override
  String get trackConvertLosslessSuffix => 'Lossless';

  @override
  String get trackConvertDithering => 'Dithering';

  @override
  String get trackConvertResampler => 'Resampler';

  @override
  String get trackConvertDitherNone => 'None';

  @override
  String get trackConvertDitherTriangular => 'TPDF';

  @override
  String get trackConvertDitherTriangularHp => 'Triangular HP';

  @override
  String get trackConvertResamplerSwr => 'SWR';

  @override
  String get trackConvertResamplerSoxr => 'SoXr';

  @override
  String get updateSeeReleaseNotes => 'See release notes for details.';

  @override
  String get unknownTitle => 'Unknown title';

  @override
  String get trackPlayNext => 'Play next';

  @override
  String get trackAddToQueue => 'Add to queue';

  @override
  String snackbarExtensionInstalledEnable(String extensionName) {
    return '$extensionName installed. Enable it in Settings > Extensions';
  }

  @override
  String snackbarExtensionUpdatedVersion(String extensionName, String version) {
    return '$extensionName updated to v$version';
  }

  @override
  String snackbarFailedToInstallNamed(String extensionName) {
    return 'Failed to install $extensionName';
  }

  @override
  String snackbarFailedToUpdateNamed(String extensionName) {
    return 'Failed to update $extensionName';
  }

  @override
  String get releaseTypeEp => 'EP';

  @override
  String get releaseTypeSingle => 'Single';

  @override
  String get trackCoverOnline => 'Online cover';

  @override
  String get regionCountryUS => 'United States';

  @override
  String get regionCountryGB => 'United Kingdom';

  @override
  String get regionCountryFR => 'France';

  @override
  String get regionCountryDE => 'Germany';

  @override
  String get regionCountryJP => 'Japan';

  @override
  String get regionCountryKR => 'South Korea';

  @override
  String get regionCountryIN => 'India';

  @override
  String get regionCountryID => 'Indonesia';

  @override
  String get regionCountryBR => 'Brazil';

  @override
  String get regionCountryMX => 'Mexico';

  @override
  String get regionCountryAU => 'Australia';

  @override
  String get regionCountryCA => 'Canada';

  @override
  String get regionCountryXK => 'Kosovo';

  @override
  String get extensionVerificationBrowserTitle => 'Verification browser';

  @override
  String get extensionVerificationBrowserSubtitleExternal =>
      'Open challenges in the default browser first';

  @override
  String get extensionVerificationBrowserSubtitleInApp =>
      'Open challenges in the in-app browser first';

  @override
  String get extensionVerificationBrowserExternal => 'External';

  @override
  String get extensionVerificationBrowserInApp => 'In-app';

  @override
  String get extensionVerificationHelpTitleManual =>
      'Open verification manually';

  @override
  String get extensionVerificationHelpTitleWaiting =>
      'Verification still waiting';

  @override
  String get extensionVerificationHelpMessageManual =>
      'SpotiFLAC Mobile could not open the browser automatically. Open this link in your browser, or copy it manually.';

  @override
  String get extensionVerificationHelpMessageWaiting =>
      'If the browser did not open, or verification finished but did not return to SpotiFLAC Mobile, open this link again or copy it manually.';

  @override
  String get extensionVerificationClose => 'Close';

  @override
  String get extensionVerificationCopyLink => 'Copy link';

  @override
  String get extensionVerificationLinkCopied => 'Verification link copied';

  @override
  String get extensionVerificationOpenBrowser => 'Open browser';

  @override
  String get settingsSearchHint => 'Buscar en los ajustes';

  @override
  String settingsSearchNoResults(String query) {
    return 'Ningún ajuste coincide con \"$query\"';
  }

  @override
  String get settingsGroupInterface => 'Extensiones y apariencia';

  @override
  String get settingsGroupContent => 'Contenido y metadatos';

  @override
  String get settingsGroupDownloads => 'Descargas y archivos';

  @override
  String get settingsGroupSystem => 'Sistema';

  @override
  String get settingsGroupHelp => 'Información y soporte';
}
