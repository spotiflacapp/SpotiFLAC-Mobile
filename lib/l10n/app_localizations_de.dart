// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => 'Startseite';

  @override
  String get navLibrary => 'Bibliothek';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navStore => 'Repo';

  @override
  String get homeTitle => 'Startseite';

  @override
  String get homeSubtitle => 'Unterstützte URL einfügen oder nach Namen suchen';

  @override
  String get homeEmptyTitle => 'Noch keine Suchanbieter';

  @override
  String get homeEmptySubtitle =>
      'Installiere eine Erweiterung um fortzufahren.';

  @override
  String get homeSupports =>
      'Unterstützt: Titel, Album, Playlist, Künstler-URLs';

  @override
  String get homeRecent => 'Zuletzt';

  @override
  String get historyFilterAll => 'Alle';

  @override
  String get historyFilterAlbums => 'Alben';

  @override
  String get historyFilterSingles => 'Singles';

  @override
  String get historySearchHint => 'Suchverlauf...';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsDownload => 'Herunterladen';

  @override
  String get settingsAppearance => 'Erscheinungsbild';

  @override
  String get settingsOptions => 'Optionen';

  @override
  String get settingsExtensions => 'Erweiterungen';

  @override
  String get settingsAbout => 'Über';

  @override
  String get downloadTitle => 'Herunterladen';

  @override
  String get downloadAskQualitySubtitle =>
      'Qualitätsauswahl für jeden Download anzeigen';

  @override
  String get downloadFilenameFormat => 'Dateinamenformat';

  @override
  String get downloadSingleFilenameFormat => 'Einzelnes Dateinamenformat';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Dateinamenmuster für Singles und EPs. Verwendet die gleichen Tags wie das Albumformat.';

  @override
  String get downloadFolderOrganization => 'Ordnerstruktur';

  @override
  String get appearanceTitle => 'Erscheinungsbild';

  @override
  String get appearanceThemeSystem => 'System';

  @override
  String get appearanceThemeLight => 'Hell';

  @override
  String get appearanceThemeDark => 'Dunkel';

  @override
  String get appearanceDynamicColor => 'Dynamische Farben';

  @override
  String get appearanceDynamicColorSubtitle =>
      'Farben deines Hintergrundbilds verwenden';

  @override
  String get appearanceHistoryView => 'Verlaufsansicht';

  @override
  String get appearanceHistoryViewList => 'Liste';

  @override
  String get appearanceHistoryViewGrid => 'Raster';

  @override
  String get optionsTitle => 'Optionen';

  @override
  String get optionsPrimaryProvider => 'Primärer Anbieter';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Dienst zur Suche nach Titel oder Albumnamen';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Erweiterung verwenden: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Standard Such-Tab';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Wähle aus, welcher Tab zuerst für neue Suchergebnisse geöffnet wird.';

  @override
  String get optionsSwitchBack =>
      'Tippe auf Deezer oder Spotify, um von der Erweiterung zurückzuwechseln';

  @override
  String get optionsAutoFallback => 'Automatischer Fallback';

  @override
  String get optionsAutoFallbackSubtitle =>
      'Andere Dienste versuchen, wenn Download fehlschlägt';

  @override
  String get optionsUseExtensionProviders => 'Erweiterungsanbieter verwenden';

  @override
  String get optionsUseExtensionProvidersOn =>
      'Erweiterungen werden zuerst versucht';

  @override
  String get optionsUseExtensionProvidersOff =>
      'Nur integrierte Anbieter verwenden';

  @override
  String get optionsEmbedLyrics => 'Liedtexte einbetten';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Speichere synchronisierte Liedtexte zusammen mit heruntergeladenen Titeln';

  @override
  String get optionsMaxQualityCover => 'Maximale Cover-Qualität';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'Cover in höchster Auflösung herunterladen';

  @override
  String get optionsReplayGain => 'ReplayGain';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Scanne Lautstärke und füge ReplayGain-Tags ein (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Deaktiviert: keine Lautstärke-Normalisierungs-Tags';

  @override
  String get optionsArtistTagMode => 'Künstler Tag-Modus';

  @override
  String get optionsArtistTagModeDescription =>
      'Wähle aus, wie mehrere Künstler in eingebetteten Tags geschrieben sind.';

  @override
  String get optionsArtistTagModeJoined => 'Einzelne beigefügte Werte';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Einen Künstler wert wie \"Artist A, Artist B\" für maximale Spieler-Kompatibilität schreiben.';

  @override
  String get optionsArtistTagModeSplitVorbis => 'Tags für FLAC/Opus aufteilen';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'Schreibe einen Künstler Tag pro Künstler für FLAC und Opus; MP3 und M4A bleiben beigetreten.';

  @override
  String get optionsConcurrentDownloads => 'Parallele Downloads';

  @override
  String get optionsConcurrentSequential => 'Sequentiell (1 gleichzeitig)';

  @override
  String optionsConcurrentParallel(int count) {
    return '$count parallele Downloads';
  }

  @override
  String get optionsConcurrentWarning =>
      'Parallele Downloads können Ratenlimitierung auslösen';

  @override
  String get optionsExtensionStore => 'Erweiterungs-Repo';

  @override
  String get optionsExtensionStoreSubtitle =>
      'Repo-Tab in der Navigation anzeigen';

  @override
  String get optionsCheckUpdates => 'Nach Updates suchen';

  @override
  String get optionsCheckUpdatesSubtitle =>
      'Benachrichtigen, wenn neue Version verfügbar';

  @override
  String get optionsUpdateChannel => 'Update-Kanal';

  @override
  String get optionsUpdateChannelStable => 'Nur stabile Versionen';

  @override
  String get optionsUpdateChannelPreview => 'Vorschau-Versionen erhalten';

  @override
  String get optionsUpdateChannelWarning =>
      'Vorschau kann Fehler oder unvollständige Funktionen enthalten';

  @override
  String get optionsClearHistory => 'Download-Verlauf löschen';

  @override
  String get optionsClearHistorySubtitle =>
      'Alle heruntergeladenen Titel aus dem Verlauf entfernen';

  @override
  String get optionsDetailedLogging => 'Detaillierte Protokollierung';

  @override
  String get optionsDetailedLoggingOn =>
      'Detaillierte Logs werden aufgezeichnet';

  @override
  String get optionsDetailedLoggingOff => 'Für Fehlerberichte aktivieren';

  @override
  String get optionsSpotifyCredentials => 'Spotify-Anmeldedaten';

  @override
  String optionsSpotifyCredentialsConfigured(String clientId) {
    return 'Client-ID: $clientId...';
  }

  @override
  String get optionsSpotifyCredentialsRequired =>
      'Erforderlich - zum Konfigurieren tippen';

  @override
  String get optionsSpotifyWarning =>
      'Spotify erfordert eigene API-Anmeldedaten. Kostenlos erhältlich auf developer.spotify.com';

  @override
  String get optionsSpotifyDeprecationWarning =>
      'Spotify-Suche wird am 3. März 2026 aufgrund von Änderungen der Spotify-API entfernt. Bitte wechsel vorher zu Deezer.';

  @override
  String get extensionsTitle => 'Erweiterungen';

  @override
  String get extensionsDisabled => 'Deaktiviert';

  @override
  String extensionsVersion(String version) {
    return 'Version $version';
  }

  @override
  String extensionsAuthor(String author) {
    return 'von $author';
  }

  @override
  String get extensionsUninstall => 'Deinstallieren';

  @override
  String get storeTitle => 'Erweiterungs-Repo';

  @override
  String get storeSearch => 'Erweiterungen suchen...';

  @override
  String get storeInstall => 'Installieren';

  @override
  String get storeInstalled => 'Installiert';

  @override
  String get storeUpdate => 'Aktualisieren';

  @override
  String get aboutTitle => 'Über';

  @override
  String get aboutContributors => 'Mitwirkende';

  @override
  String get aboutMobileDeveloper => 'Mobile-Version Entwickler';

  @override
  String get aboutOriginalCreator => 'Schöpfer des ursprünglichen SpotiFLAC';

  @override
  String get aboutLogoArtist =>
      'Der talentierte Künstler, der unser wunderschönes App-Logo entworfen hat!';

  @override
  String get aboutTranslators => 'Übersetzer';

  @override
  String get aboutSpecialThanks => 'Besonderer Dank';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutMobileSource => 'Mobiler Quellcode';

  @override
  String get aboutPCSource => 'PC Quellcode';

  @override
  String get aboutKeepAndroidOpen => 'Keep Android Open';

  @override
  String get aboutReportIssue => 'Problem melden';

  @override
  String get aboutReportIssueSubtitle => 'Melde Probleme, die dir auffallen';

  @override
  String get aboutFeatureRequest => 'Feature vorschlagen';

  @override
  String get aboutFeatureRequestSubtitle =>
      'Schlage neue Funktionen für die App vor';

  @override
  String get aboutTelegramChannel => 'Telegram Kanal';

  @override
  String get aboutTelegramChannelSubtitle => 'Ankündigungen und Updates';

  @override
  String get aboutTelegramChat => 'Telegram Community';

  @override
  String get aboutTelegramChatSubtitle => 'Mit anderen Nutzern chatten';

  @override
  String get aboutSocial => 'Sozial';

  @override
  String get aboutApp => 'App';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBinimumDesc =>
      'Der Schöpfer der QQDL & HiFi API. Ohne diese API gäbe es keine Tidal-Downloads!';

  @override
  String get aboutSachinsenalDesc =>
      'Der ursprüngliche Entwickler des HiFi-Projekts. Die Grundlage der Tidal-Integration!';

  @override
  String get aboutSjdonadoDesc =>
      'Ersteller von I Don\'t Have Spotify (IDHS). Der Fallback-Link-Resolver, der den Tag rettet!';

  @override
  String get aboutAppDescription =>
      'Musik-Metadaten durchsuchen, Erweiterungen verwalten und deine Bibliothek organisieren.';

  @override
  String get artistAlbums => 'Alben';

  @override
  String get artistSingles => 'Singles & EPs';

  @override
  String get artistCompilations => 'Zusammenstellungen';

  @override
  String get artistPopular => 'Beliebt';

  @override
  String artistMonthlyListeners(String count) {
    return '$count monatliche Hörer';
  }

  @override
  String get trackMetadataService => 'Anbieter';

  @override
  String get trackMetadataPlay => 'Abspielen';

  @override
  String get trackMetadataShare => 'Teilen';

  @override
  String get trackMetadataDelete => 'Löschen';

  @override
  String get setupGrantPermission => 'Berechtigung erlauben';

  @override
  String get setupSkip => 'Vorerst überspringen';

  @override
  String get setupStorageAccessRequired => 'Speicherzugriff erforderlich';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Android 11+ benötigt die Berechtigung „Auf alle Dateien“, um Dateien im ausgewählten Download-Ordner zu speichern.';

  @override
  String get setupOpenSettings => 'Einstellungen öffnen';

  @override
  String get setupPermissionDeniedMessage =>
      'Berechtigung verweigert. Bitte erteile alle Berechtigungen um fortzufahren.';

  @override
  String setupPermissionRequired(String permissionType) {
    return '$permissionType-Berechtigung erforderlich';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return '$permissionType-Berechtigung ist erforderlich für\ndie beste Benutzererfahrung. Du kannst dies später in den Einstellungen ändern.';
  }

  @override
  String get setupUseDefaultFolder => 'Als Standardordner verwenden?';

  @override
  String get setupNoFolderSelected =>
      'Kein Ordner ausgewählt. Soll der Standard-Musikordner verwendet werden?';

  @override
  String get setupUseDefault => 'Standard verwenden';

  @override
  String get setupDownloadLocationTitle => 'Speicherort';

  @override
  String get setupDownloadLocationIosMessage =>
      'Auf iOS werden Downloads im Dokumentenordner der App gespeichert. Du kannst sie über die Datei-App aufrufen.';

  @override
  String get setupAppDocumentsFolder => 'App-Dokumentenordner';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Empfohlen - zugänglich über die Datei-App';

  @override
  String get setupChooseFromFiles => 'Aus Dateien auswählen';

  @override
  String get setupChooseFromFilesSubtitle =>
      'Wähle iCloud oder einen anderen Speicherort';

  @override
  String get setupIosEmptyFolderWarning =>
      'iOS-Einschränkung: Leere Ordner können nicht ausgewählt werden. Wähle einen Ordner mit mindestens einer Datei.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive wird nicht unterstützt. Bitte verwende den \"Dokumente\" Ordner.';

  @override
  String get setupDownloadInFlac => 'Spotify Titel in FLAC herunterladen';

  @override
  String get setupStorageGranted => 'Speicherberechtigung erlaubt!';

  @override
  String get setupStorageRequired => 'Speicherzugriff erforderlich';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC benötigt Speicherrechte, um die heruntergeladenen Musikdateien zu speichern.';

  @override
  String get setupNotificationGranted =>
      'Benachrichtigungs-Berechtigung erteilt';

  @override
  String get setupNotificationEnable => 'Benachrichtigungen aktivieren';

  @override
  String get setupFolderChoose => 'Speicherort auswählen';

  @override
  String get setupFolderDescription =>
      'Wähle einen Ordner, in dem die heruntergeladene Musik gespeichert wird.';

  @override
  String get setupSelectFolder => 'Ordner wählen';

  @override
  String get setupEnableNotifications => 'Benachrichtigungen aktivieren';

  @override
  String get setupNotificationBackgroundDescription =>
      'Erhalte Benachrichtigungen über den Fortschritt und die Fertigstellung deiner Downloads, selbst wenn die App im Hintergrund läuft.';

  @override
  String get setupSkipForNow => 'Vorerst überspringen';

  @override
  String get setupNext => 'Weiter';

  @override
  String get setupGetStarted => 'Los geht‘s';

  @override
  String get setupAllowAccessToManageFiles =>
      'Bitte aktiviere \"Zugriff auf alle Dateien erlauben\" auf dem nächsten Bildschirm.';

  @override
  String get setupLanguageTitle => 'Sprache auswählen';

  @override
  String get setupLanguageDescription =>
      'Wählen deine bevorzugte Sprache für die App. Dies kann später in den Einstellungen geändert werden.';

  @override
  String get setupLanguageSystemDefault => 'Systemstandard';

  @override
  String get dialogCancel => 'Abbrechen';

  @override
  String get dialogSave => 'Speichern';

  @override
  String get dialogDelete => 'Löschen';

  @override
  String get dialogRetry => 'Wiederholen';

  @override
  String get dialogClear => 'Leeren';

  @override
  String get dialogDone => 'Fertig';

  @override
  String get dialogImport => 'Importieren';

  @override
  String get dialogDownload => 'Herunterladen';

  @override
  String get dialogDiscard => 'Verwerfen';

  @override
  String get dialogRemove => 'Entfernen';

  @override
  String get dialogUninstall => 'Deinstallieren';

  @override
  String get dialogDiscardChanges => 'Änderungen verwerfen?';

  @override
  String get dialogUnsavedChanges =>
      'Du hast ungespeicherte Änderungen. Möchtest du sie verwerfen?';

  @override
  String get dialogClearAll => 'Alles löschen';

  @override
  String get dialogRemoveExtension => 'Erweiterung entfernen';

  @override
  String get dialogRemoveExtensionMessage =>
      'Bist du sicher, dass du diese Erweiterung entfernen möchtest? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get dialogUninstallExtension => 'Erweiterung deinstallieren?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return 'Bist du sicher, dass du $extensionName entfernen möchtest?';
  }

  @override
  String get dialogClearHistoryTitle => 'Verlauf löschen';

  @override
  String get dialogClearHistoryMessage =>
      'Bist du sicher, dass du den gesamten Downloadverlauf löschen möchtest? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get dialogDeleteSelectedTitle => 'Ausgewählte löschen';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tracks',
      one: 'Track',
    );
    return 'Lösche $count $_temp0 aus dem Verlauf?\n\nDies löscht auch die Dateien aus dem Speicher.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Playlist importieren';

  @override
  String dialogImportPlaylistMessage(int count) {
    return '$count Titel gefunden hinzufügen?';
  }

  @override
  String csvImportTracks(int count) {
    return '$count Titel aus CSV';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return '\"$trackName\" hinzugefügt';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return '$count Titel hinzugefügt';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\"$trackName\" bereits heruntergeladen';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '\"$trackName\" existiert bereits in deiner Bibliothek';
  }

  @override
  String get snackbarHistoryCleared => 'Verlauf gelöscht';

  @override
  String get snackbarCredentialsSaved => 'Anmeldedaten gespeichert';

  @override
  String get snackbarCredentialsCleared => 'Anmeldedaten gelöscht';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return '$count $_temp0';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'Datei kann nicht geöffnet werden: $error';
  }

  @override
  String get snackbarFillAllFields => 'Bitte fülle alle Felder aus';

  @override
  String get snackbarViewQueue => 'Warteschlange anzeigen';

  @override
  String snackbarUrlCopied(String platform) {
    return '$platform URL in die Zwischenablage kopiert';
  }

  @override
  String get snackbarFileNotFound => 'Datei nicht gefunden';

  @override
  String get snackbarSelectExtFile => 'Bitte wähle eine .spotiflac-ext Datei';

  @override
  String get snackbarProviderPrioritySaved => 'Anbieterpriorität gespeichert';

  @override
  String get snackbarMetadataProviderSaved =>
      'Priorität des Metadaten-Anbieters gespeichert';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '$extensionName installiert.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName aktualisiert.';
  }

  @override
  String get snackbarFailedToInstall =>
      'Erweiterung konnte nicht installiert werden';

  @override
  String get snackbarFailedToUpdate =>
      'Erweiterung konnte nicht aktualisiert werden';

  @override
  String get errorRateLimited => 'Anfragelimit überschritten';

  @override
  String get errorRateLimitedMessage =>
      'Zu viele Anfragen. Bitte warte einen Moment, bevor du es erneut suchst.';

  @override
  String get errorNoTracksFound => 'Keine Titel gefunden';

  @override
  String get searchEmptyResultSubtitle => 'Try another keyword';

  @override
  String get errorUrlNotRecognized => 'Link wurde nicht erkannt';

  @override
  String get errorUrlNotRecognizedMessage =>
      'Dieser Link ist inkompatibel. Prüfe die URL und stelle sicher, dass eine kompatible Erweiterung installiert ist.';

  @override
  String get errorUrlFetchFailed =>
      'Laden fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String errorMissingExtensionSource(String item) {
    return 'Kann $item nicht laden wegen fehlender Erweiterungsquelle';
  }

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Fortfahren';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionSelectAll => 'Alles Auswählen';

  @override
  String get actionDeselect => 'Alle abwählen';

  @override
  String get actionRemoveCredentials => 'Anmeldedaten entfernen';

  @override
  String get actionSaveCredentials => 'Anmeldedaten speichern';

  @override
  String selectionSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get selectionAllSelected => 'Alle Titel sind ausgewählt';

  @override
  String get selectionSelectToDelete => 'Titel zum Löschen wählen';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Lade Metadaten... $current/$total';
  }

  @override
  String get progressReadingCsv => 'CSV wird gelesen...';

  @override
  String get searchSongs => 'Titel';

  @override
  String get searchArtists => 'Künstler';

  @override
  String get searchAlbums => 'Alben';

  @override
  String get searchPlaylists => 'Playlists';

  @override
  String get searchSortTitle => 'Ergebnisse sortieren';

  @override
  String get searchSortDefault => 'Standard';

  @override
  String get searchSortTitleAZ => 'Titel (A-Z)';

  @override
  String get searchSortTitleZA => 'Titel (Z-A)';

  @override
  String get searchSortArtistAZ => 'Künstler (A-Z)';

  @override
  String get searchSortArtistZA => 'Künstler (Z-A)';

  @override
  String get searchSortDurationShort => 'Dauer (kürzeste)';

  @override
  String get searchSortDurationLong => 'Dauer (längste)';

  @override
  String get searchSortDateOldest => 'Veröffentlichungsdatum (älteste)';

  @override
  String get searchSortDateNewest => 'Veröffentlichungsdatum (Neueste)';

  @override
  String get tooltipPlay => 'Abspielen';

  @override
  String get filenameFormat => 'Dateinamenformat';

  @override
  String get filenameShowAdvancedTags => 'Erweiterte Tags anzeigen';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Formatierte Tags für Track-Padding und Datumsmuster aktivieren';

  @override
  String get folderOrganizationNone => 'Keine Organisation';

  @override
  String get folderOrganizationByPlaylist => 'Nach Playlist';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Ordner für jede Playlist trennen';

  @override
  String get folderOrganizationByArtist => 'Nach Künstler';

  @override
  String get folderOrganizationByAlbum => 'Nach Album';

  @override
  String get folderOrganizationByArtistAlbum => 'Künstler/Album';

  @override
  String get folderOrganizationDescription =>
      'Heruntergeladene Dateien in Ordner organisieren';

  @override
  String get folderOrganizationNoneSubtitle =>
      'Alle Dateien im Download-Ordner';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Trenne Ordner nach Künstler';

  @override
  String get folderOrganizationByAlbumSubtitle => 'Trenne Ordner nach Album';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Verschachtelte Ordner für Künstler und Album';

  @override
  String get updateAvailable => 'Update verfügbar';

  @override
  String get updateLater => 'Später';

  @override
  String get updateStartingDownload => 'Download wird gestartet...';

  @override
  String get updateDownloadFailed => 'Download fehlgeschlagen';

  @override
  String get updateFailedMessage =>
      'Das Update konnte nicht heruntergeladen werden';

  @override
  String get updateNewVersionReady => 'Eine neue Version ist verfügbar';

  @override
  String get updateCurrent => 'Aktuell';

  @override
  String get updateNew => 'Neu';

  @override
  String get updateDownloading => 'Wird heruntergeladen...';

  @override
  String get updateWhatsNew => 'Was ist neu';

  @override
  String get updateDownloadInstall => 'Herunterladen & Installieren';

  @override
  String get updateDontRemind => 'Nicht erinnern';

  @override
  String get providerPriorityTitle => 'Anbieterpriorität';

  @override
  String get providerPriorityDescription =>
      'Ziehen, um Download-Anbieter neu zu ordnen. Die App versucht Anbieter von oben nach unten, wenn Titel heruntergeladen werden.';

  @override
  String get providerPriorityInfo =>
      'Wenn kein Titel bei dem ersten Anbieter nicht verfügbar ist, wird die App automatisch den nächsten versuchen.';

  @override
  String get providerPriorityFallbackExtensionsTitle => 'Erweiterungs-Fallback';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Wähle aus, welche installierten Download-Erweiterungen beim automatischen Fallback verwendet werden sollen.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Hier werden nur aktivierte Erweiterungen mit Download-Provider-Funktion aufgelistet.';

  @override
  String get providerBuiltIn => 'Integriert';

  @override
  String get providerExtension => 'Erweiterung';

  @override
  String get metadataProviderPriorityTitle => 'Metadaten Priorität';

  @override
  String get metadataProviderPriorityDescription =>
      'Ziehe, um Metadatenanbieter neu zu ordnen. Die App versucht Anbieter von oben nach unten, wenn sie nach Tracks suchen und Metadaten abrufen.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer hat keine Limits und wird als primäre empfohlen. Spotify kann nach vielen Anfragen begrenzen.';

  @override
  String get metadataNoRateLimits => 'Keine Limitierungen';

  @override
  String get metadataMayRateLimit => 'Hat vielleicht Limitierungen';

  @override
  String get logTitle => 'Logs';

  @override
  String get logCopied => 'Logs in Zwischenablage kopiert';

  @override
  String get logSearchHint => 'Logs durchsuchen ...';

  @override
  String get logFilterLevel => 'Stufe';

  @override
  String get logFilterSection => 'Filter';

  @override
  String get logShareLogs => 'Logs teilen';

  @override
  String get logClearLogs => 'Logs löschen';

  @override
  String get logClearLogsTitle => 'Logs leeren';

  @override
  String get logClearLogsMessage =>
      'Bist du dir sicher, dass Sie alle Logs löschen möchtest?';

  @override
  String get logFilterBySeverity => 'Logs nach Schweregrad filtern';

  @override
  String get logNoLogsYet => 'Noch keine Logs';

  @override
  String get logNoLogsYetSubtitle =>
      'Logs werden hier angezeigt, während du die App benutzt';

  @override
  String logEntriesFiltered(int count) {
    return 'Einträge ($count gefiltert)';
  }

  @override
  String logEntries(int count) {
    return '$count Einträge';
  }

  @override
  String get credentialsTitle => 'Spotify-Anmeldedaten';

  @override
  String get credentialsDescription =>
      'Gebe deine Client-ID und Secret ein, um dein eigenes Spotify Anwendungs Limit zu haben.';

  @override
  String get credentialsClientId => 'Client ID';

  @override
  String get credentialsClientIdHint => 'Client ID einfügen';

  @override
  String get credentialsClientSecret => 'Client Secret';

  @override
  String get credentialsClientSecretHint => 'Client Secret einfügen';

  @override
  String get channelStable => 'Stabil';

  @override
  String get channelPreview => 'Vorschau';

  @override
  String get sectionSearchSource => 'Suchquelle';

  @override
  String get sectionDownload => 'Herunterladen';

  @override
  String get sectionPerformance => 'Performance';

  @override
  String get sectionApp => 'App';

  @override
  String get sectionData => 'Daten';

  @override
  String get sectionDebug => 'Debug';

  @override
  String get sectionService => 'Anbieter';

  @override
  String get sectionAudioQuality => 'Audioqualität';

  @override
  String get sectionFileSettings => 'Datei-Einstellungen';

  @override
  String get sectionLyrics => 'Lyrics';

  @override
  String get lyricsMode => 'Lyrics-Modus';

  @override
  String get lyricsModeDescription =>
      'Wähle wie Songtexte mit deinen Downloads gespeichert werden';

  @override
  String get lyricsModeEmbed => 'In Datei einbetten';

  @override
  String get lyricsModeEmbedSubtitle => 'Lyrics in FLAC Metadaten gespeichert';

  @override
  String get lyricsModeExternal => 'Externe .lrc Datei';

  @override
  String get lyricsModeExternalSubtitle =>
      'Separate .lrc Datei für Player wie Samsung Music';

  @override
  String get lyricsModeBoth => 'Beides';

  @override
  String get lyricsModeBothSubtitle =>
      'Lyrics einbetten und als .lrc speichern';

  @override
  String get sectionColor => 'Farbe';

  @override
  String get sectionTheme => 'Design';

  @override
  String get sectionLayout => 'Layout';

  @override
  String get sectionLanguage => 'Sprache';

  @override
  String get appearanceLanguage => 'App Sprache';

  @override
  String get settingsAppearanceSubtitle => 'Design, Farben, Anzeige';

  @override
  String get settingsDownloadSubtitle => 'Anbieter, Qualität, Rückfall';

  @override
  String get settingsOptionsSubtitle =>
      'Fallback, Metadaten, Lyrics, Cover-Art';

  @override
  String get settingsExtensionsSubtitle => 'Download-Anbieter verwalten';

  @override
  String get settingsLogsSubtitle => 'App-Logs zum Debuggen anzeigen';

  @override
  String get loadingSharedLink => 'Link wird geladen...';

  @override
  String get pressBackAgainToExit =>
      'Drücke wieder \"zurück\" um die App zu beenden';

  @override
  String downloadAllCount(int count) {
    return 'Alle $count Titel herunterladen';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel',
      one: '1 Titel',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Dateipfad kopieren';

  @override
  String get trackRemoveFromDevice => 'Vom Gerät entfernen';

  @override
  String get trackLoadLyrics => 'Lade Lyrics';

  @override
  String get trackMetadata => 'Metadaten';

  @override
  String get trackFileInfo => 'Datei-Info';

  @override
  String get trackLyrics => 'Lyrics';

  @override
  String get trackFileNotFound => 'Datei nicht gefunden';

  @override
  String get trackOpenInDeezer => 'In Deezer öffnen';

  @override
  String get trackOpenInSpotify => 'In Spotify öffnen';

  @override
  String get trackTrackName => 'Name des Titels';

  @override
  String get trackArtist => 'Künstler';

  @override
  String get trackAlbumArtist => 'Album Künstler';

  @override
  String get trackAlbum => 'Album';

  @override
  String get trackTrackNumber => 'Titelnummer';

  @override
  String get trackDiscNumber => 'CD-Nummer';

  @override
  String get trackDuration => 'Länge';

  @override
  String get trackAudioQuality => 'Audioqualität';

  @override
  String get trackReleaseDate => 'Erscheinungsdatum';

  @override
  String get trackGenre => 'Genre';

  @override
  String get trackLabel => 'Label';

  @override
  String get trackCopyright => 'Urheberrecht';

  @override
  String get trackDownloaded => 'Heruntergeladen';

  @override
  String get trackCopyLyrics => 'Lyrics kopieren';

  @override
  String trackLyricsSource(String source) {
    return 'Quelle: $source';
  }

  @override
  String get trackLyricsNotAvailable =>
      'Lyrics sind für diesen Titel nicht verfügbar';

  @override
  String get trackLyricsNotInFile => 'Keine Lyrics in dieser Datei gefunden';

  @override
  String get trackFetchOnlineLyrics => 'Online abrufen';

  @override
  String get trackLyricsTimeout =>
      'Anfrage Timeout. Versuche es später erneut.';

  @override
  String get trackLyricsLoadFailed => 'Fehler beim Laden der Lyrics';

  @override
  String get trackEmbedLyrics => 'Lyrics einbetten';

  @override
  String get trackLyricsEmbedded => 'Lyrics erfolgreich eingebettet';

  @override
  String get trackInstrumental => 'Instrumentalspur';

  @override
  String get trackCopiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get trackDeleteConfirmTitle => 'Vom Gerät entfernen?';

  @override
  String get trackDeleteConfirmMessage =>
      'Dies wird die heruntergeladene Datei dauerhaft löschen und sie aus deinem Verlauf entfernen.';

  @override
  String get dateToday => 'Heute';

  @override
  String get dateYesterday => 'Gestern';

  @override
  String dateDaysAgo(int count) {
    return 'Vor $count Tagen';
  }

  @override
  String dateWeeksAgo(int count) {
    return 'Vor $count Wochen';
  }

  @override
  String dateMonthsAgo(int count) {
    return 'Vor $count Monaten';
  }

  @override
  String get storeFilterAll => 'Alle';

  @override
  String get storeFilterMetadata => 'Metadaten';

  @override
  String get storeFilterDownload => 'Herunterladen';

  @override
  String get storeFilterUtility => 'Utility';

  @override
  String get storeFilterLyrics => 'Lyrics';

  @override
  String get storeFilterIntegration => 'Integration';

  @override
  String get storeClearFilters => 'Filter entfernen';

  @override
  String get storeAddRepoTitle => 'Erweiterungs-Repository hinzufügen';

  @override
  String get storeAddRepoDescription =>
      'Gib eine GitHub Repository-URL ein, die eine Registry.json Datei enthält, um Erweiterungen zu durchsuchen und zu installieren.';

  @override
  String get storeRepoUrlLabel => 'Repository-URL';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeRepoUrlHelper =>
      'z.B. https://github.com/user/extensions-repo';

  @override
  String get storeAddRepoButton => 'Repository hinzufügen';

  @override
  String get storeChangeRepoTooltip => 'Repository ändern';

  @override
  String get storeRepoDialogTitle => 'Erweiterungs-Repository';

  @override
  String get storeRepoDialogCurrent => 'Aktuelles Repository:';

  @override
  String get storeNewRepoUrlLabel => 'Neue Repository-URL';

  @override
  String get storeLoadError => 'Fehler beim Laden der Repository';

  @override
  String get storeEmptyNoExtensions => 'Keine Erweiterung verfügbar';

  @override
  String get storeEmptyNoResults => 'Keine Erweiterungen gefunden';

  @override
  String get extensionDefaultProvider => 'Standard (Deezer)';

  @override
  String get extensionDefaultProviderSubtitle => 'Eingebaute Suche verwenden';

  @override
  String get extensionAuthor => 'Entwickler';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => 'Fehler';

  @override
  String get extensionCapabilities => 'Eigenschaften';

  @override
  String get extensionMetadataProvider => 'Metadaten-Anbieter';

  @override
  String get extensionDownloadProvider => 'Download-Anbieter';

  @override
  String get extensionLyricsProvider => 'Lyrics-Anbieter';

  @override
  String get extensionUrlHandler => 'URL Handler';

  @override
  String get extensionQualityOptions => 'Qualitätsoptionen';

  @override
  String get extensionPostProcessingHooks => 'Post-Processing Hooks';

  @override
  String get extensionPermissions => 'Berechtigungen';

  @override
  String get extensionSettings => 'Einstellungen';

  @override
  String get extensionRemoveButton => 'Erweiterung entfernen';

  @override
  String get extensionUpdated => 'Aktualisiert';

  @override
  String get extensionMinAppVersion => 'Min App-Version';

  @override
  String get extensionCustomTrackMatching =>
      'Benutzerdefiniertes Track-Matching';

  @override
  String get extensionPostProcessing => 'Post-processing';

  @override
  String extensionHooksAvailable(int count) {
    return '$count Hook(s) verfügbar';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count Muster';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Strategie: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => 'Provider-Priorität';

  @override
  String get extensionsInstalledSection => 'Installierte Erweiterungen';

  @override
  String get extensionsNoExtensions => 'Keine Erweiterungen installiert';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Installiere .spotiflac-ext Dateien um neue Anbieter hinzuzufügen';

  @override
  String get extensionsInstallButton => 'Erweiterung installieren';

  @override
  String get extensionsInfoTip =>
      'Erweiterungen können neue Metadaten und Download-Anbieter hinzufügen. Installiere nur Erweiterungen von vertrauenswürdigen Quellen.';

  @override
  String get extensionsInstalledSuccess =>
      'Erweiterung erfolgreich installiert';

  @override
  String extensionsInstalledCount(int count) {
    return '$count Erweiterungen erfolgreich installiert';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return '$installed von $attempted Erweiterungen installiert';
  }

  @override
  String get extensionsDownloadPriority => 'Download-Priorität';

  @override
  String get extensionsDownloadPrioritySubtitle =>
      'Download-Service-Reihenfolge festlegen';

  @override
  String get extensionsFallbackTitle => 'Fallback-Erweiterungen';

  @override
  String get extensionsFallbackSubtitle =>
      'Wähle welche installierten Download-Erweiterungen als Fallback verwendet werden sollen';

  @override
  String get extensionsNoDownloadProvider =>
      'Keine Erweiterungen mit Download-Provider';

  @override
  String get extensionsMetadataPriority => 'Metadaten Priorität';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Reihenfolge der Such- und Metadaten quellen festlegen';

  @override
  String get extensionsNoMetadataProvider =>
      'Keine Erweiterungen mit Metadaten-Anbieter';

  @override
  String get extensionsSearchProvider => 'Such-Provider';

  @override
  String get extensionsNoCustomSearch =>
      'Keine Erweiterungen mit benutzerdefinierter Suche';

  @override
  String get extensionsSearchProviderDescription =>
      'Wähle den Dienst für die Suche von Titel';

  @override
  String get extensionsCustomSearch => 'Benutzerdefinierte Suche';

  @override
  String get extensionsErrorLoading => 'Fehler beim Laden der Erweiterung';

  @override
  String get qualityFlacLossless => 'FLAC Verlustfrei';

  @override
  String get qualityFlacLosslessSubtitle => '16-bit / 44,1kHz';

  @override
  String get qualityHiResFlac => 'Hi-Res FLAC';

  @override
  String get qualityHiResFlacSubtitle => '24-Bit / bis 96kHz';

  @override
  String get qualityHiResFlacMax => 'Hi-Res FLAC Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-Bit / bis 192kHz';

  @override
  String get downloadLossy320 => 'Verlustbehaftet 320kbps';

  @override
  String get downloadLossyFormat => 'Verlustbehaftetes Format';

  @override
  String get downloadLossy320Format => 'Verlustbehaftetes 320kbps-Format';

  @override
  String get downloadLossy320FormatDesc =>
      'Wähle das Ausgabeformat für Tidal 320kbps verlustbehaftete Downloads. Der ursprüngliche AAC Stream wird in das ausgewählte Format konvertiert.';

  @override
  String get downloadLossyMp3 => 'MP3 320kbps';

  @override
  String get downloadLossyMp3Subtitle =>
      'Beste Kompatibilität, ~10MB pro Titel';

  @override
  String get downloadLossyAac => 'AAC/M4A 320kbps';

  @override
  String get downloadLossyAacSubtitle =>
      'Beste mobile Kompatibilität, M4A Container';

  @override
  String get downloadLossyOpus256 => 'Opus 256kbps';

  @override
  String get downloadLossyOpus256Subtitle => 'Beste Qualität, ~8MB pro Titel';

  @override
  String get downloadLossyOpus128 => 'Opus 128kbps';

  @override
  String get downloadLossyOpus128Subtitle => 'Kleinste Größe, ~4MB pro Track';

  @override
  String get qualityNote =>
      'Die eigentliche Qualität hängt von der Verfügbarkeit des Dienstes ab';

  @override
  String get downloadAskBeforeDownload => 'Qualität vor Download fragen';

  @override
  String get downloadDirectory => 'Download-Ordner';

  @override
  String get downloadSeparateSinglesFolder => 'Singles Ordner trennen';

  @override
  String get downloadAlbumFolderStructure => 'Album-Ordnerstruktur';

  @override
  String get downloadUseAlbumArtistForFolders =>
      'Album-Künstler für Ordner verwenden';

  @override
  String get downloadUsePrimaryArtistOnly => 'Primärer Künstler nur für Ordner';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Vorgestellte Künstler aus dem Ordnernamen entfernt (z.B. Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Vollständiger Künstler für Ordnername';

  @override
  String get downloadSelectQuality => 'Qualität wählen';

  @override
  String get downloadFrom => 'Herunterladen von';

  @override
  String get appearanceAmoledDark => 'AMOLED Schwarz';

  @override
  String get appearanceAmoledDarkSubtitle => 'AMOLED Hintergrund';

  @override
  String get queueClearAll => 'Alles löschen';

  @override
  String get queueClearAllMessage =>
      'Bist du dir sicher, dass du alle Downloads löschen möchten?';

  @override
  String get settingsAutoExportFailed =>
      'Auto-Export fehlgeschlagener Downloads';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Fehlgeschlagene Downloads automatisch in eine TXT-Datei speichern';

  @override
  String get settingsDownloadNetwork => 'Download Netzwerk';

  @override
  String get settingsDownloadNetworkAny => 'WLAN + Mobile Daten';

  @override
  String get settingsDownloadNetworkWifiOnly => 'Nur WLAN';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'Wähle aus, welches Netzwerk für Downloads verwendet werden soll. Wenn nur WLAN aktiviert wird, werden Downloads auf mobilen Daten angehalten.';

  @override
  String get albumFolderArtistAlbum => 'Künstler/Album';

  @override
  String get albumFolderArtistAlbumSubtitle => 'Alben/Künster Name/Album Name/';

  @override
  String get albumFolderArtistYearAlbum => 'Künstler / [Year] Album';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Alben/Künster Name/[2005] Album Name/';

  @override
  String get albumFolderAlbumOnly => 'Nur Alben';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Alben/Album Name/';

  @override
  String get albumFolderYearAlbum => '[Year] Album';

  @override
  String get albumFolderYearAlbumSubtitle => 'Alben/[2005] Album Name/';

  @override
  String get albumFolderArtistAlbumSingles => 'Künstler / Album + Singles';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Künstler/Album/ und Künstler/Singles/';

  @override
  String get albumFolderArtistAlbumFlat => 'Künstler / Album (Singles flach)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Künstler/Album/ Und Künstler/Lied.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Ausgewählte löschen';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return '$count $_temp0 aus diesem Album löschen?\n\nDadurch werden auch die Dateien aus dem Speicher gelöscht.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get downloadedAlbumAllSelected => 'Alle Titel sind ausgewählt';

  @override
  String get downloadedAlbumTapToSelect => 'Tippe auf Titel zum Auswählen';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Lösche $count $_temp0';
  }

  @override
  String get downloadedAlbumSelectToDelete => 'Titel zum Löschen wählen';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Disc $discNumber';
  }

  @override
  String get recentTypeArtist => 'Künstler';

  @override
  String get recentTypeAlbum => 'Album';

  @override
  String get recentTypeSong => 'Titel';

  @override
  String get recentTypePlaylist => 'Playlist';

  @override
  String get recentEmpty => 'Noch keine aktuellen Einträge';

  @override
  String get recentShowAllDownloads => 'Alle Downloads anzeigen';

  @override
  String recentPlaylistInfo(String name) {
    return 'Playlist: $name';
  }

  @override
  String get discographyDownload => 'Diskographie herunterladen';

  @override
  String get discographyDownloadAll => 'Alle Herunterladen';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$count Titel von $albumCount Releases';
  }

  @override
  String get discographyAlbumsOnly => 'Nur Alben';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$count Titel aus $albumCount Alben';
  }

  @override
  String get discographySinglesOnly => 'Nur Singles & EPs';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$count Titel von $albumCount Singles';
  }

  @override
  String get discographySelectAlbums => 'Alben auswählen...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Wähle bestimmte Alben oder Singles';

  @override
  String get discographyFetchingTracks => 'Lade Titel...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return 'Lade $current von $total...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get discographyDownloadSelected => 'Auswahl herunterladen';

  @override
  String discographyAddedToQueue(int count) {
    return '$count Titel zur Warteschlange hinzugefügt';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added hinzugefügt, $skipped bereits heruntergeladen';
  }

  @override
  String get discographyNoAlbums => 'Es sind keine Alben verfügbar';

  @override
  String get discographyFailedToFetch => 'Fehler beim Abrufen einiger Alben';

  @override
  String get sectionStorageAccess => 'Speicherzugriff';

  @override
  String get allFilesAccess => 'Zugriff auf alle Dateien';

  @override
  String get allFilesAccessEnabledSubtitle => 'Darf in jeden Ordner schreiben';

  @override
  String get allFilesAccessDisabledSubtitle => 'Nur auf Medienordner begrenzt';

  @override
  String get allFilesAccessDescription =>
      'Option bei Schreibfehlern bitte aktivieren (erforderlich ab Android 13).';

  @override
  String get allFilesAccessDeniedMessage =>
      'Zugriff verweigert. Bitte aktiviere \"Zugriff auf alle Dateien\" manuell in den Systemeinstellungen.';

  @override
  String get allFilesAccessDisabledMessage =>
      'Zugriff auf alle Dateien ist deaktiviert. Die App verwendet nur begrenzten Zugriff auf den Speicher.';

  @override
  String get settingsLocalLibrary => 'Lokale Bibliothek';

  @override
  String get settingsLocalLibrarySubtitle =>
      'Musik scannen & Duplikate erkennen';

  @override
  String get settingsCache => 'Speicher & Cache';

  @override
  String get settingsCacheSubtitle =>
      'Größe anzeigen und Daten im Cache leeren';

  @override
  String get libraryTitle => 'Lokale Bibliothek';

  @override
  String get libraryScanSettings => 'Scan Einstellungen';

  @override
  String get libraryEnableLocalLibrary => 'Lokale Bibliothek aktivieren';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Scan und verfolge deine bestehende Musik';

  @override
  String get libraryFolder => 'Bibliotheksordner';

  @override
  String get libraryFolderHint => 'Tippe um Ordner auszuwählen';

  @override
  String get libraryShowDuplicateIndicator => 'Duplikat Indikator anzeigen';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Bei der Suche nach vorhandenen Titeln anzeigen';

  @override
  String get libraryAutoScan => 'Auto-Scan';

  @override
  String get libraryAutoScanSubtitle =>
      'Scanne die Bibliothek automatisch nach neuen Dateien';

  @override
  String get libraryAutoScanOff => 'Aus';

  @override
  String get libraryAutoScanOnOpen => 'Bei jeder App Öffnung';

  @override
  String get libraryAutoScanDaily => 'Täglich';

  @override
  String get libraryAutoScanWeekly => 'Wöchentlich';

  @override
  String get libraryActions => 'Aktionen';

  @override
  String get libraryScan => 'Bibliothek scannen';

  @override
  String get libraryScanSubtitle => 'Suche nach Audiodateien';

  @override
  String get libraryScanSelectFolderFirst => 'Wähle zuerst einen Ordner';

  @override
  String get libraryCleanupMissingFiles => 'Fehlende Dateien bereinigen';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Verlaufseinträge für Dateien löschen, die nicht mehr existieren';

  @override
  String get libraryClear => 'Bibliothek löschen';

  @override
  String get libraryClearSubtitle => 'Alle gescannten Titel entfernen';

  @override
  String get libraryClearConfirmTitle => 'Bibliothek löschen';

  @override
  String get libraryClearConfirmMessage =>
      'Dadurch werden alle gescannten Titel aus deiner Bibliothek entfernt. Deine eigentlichen Musikdateien werden nicht gelöscht.';

  @override
  String get libraryAbout => 'Über die lokale Bibliothek';

  @override
  String get libraryAboutDescription =>
      'Durchsucht deine bestehende Musiksammlung, um Duplikate beim Herunterladen zu erkennen. Unterstützt die Formate FLAC, M4A, MP3, Opus und OGG. Metadaten werden, sofern verfügbar, aus den Dateitags gelesen.';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel',
      one: '1 Titel',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Datein',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return 'Zuletzt gescannt: $time';
  }

  @override
  String get libraryLastScannedNever => 'Nie';

  @override
  String get libraryScanning => 'Scannen...';

  @override
  String get libraryScanFinalizing => 'Bibliothek wird aktualisiert...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$progress% von $total Dateien';
  }

  @override
  String get libraryInLibrary => 'In Bibliothek';

  @override
  String libraryRemovedMissingFiles(int count) {
    return 'Entfernte $count fehlende Dateien aus der Bibliothek';
  }

  @override
  String get libraryCleared => 'Bibliothek geleert';

  @override
  String get libraryStorageAccessRequired => 'Speicherzugriff erforderlich';

  @override
  String get libraryStorageAccessMessage =>
      'SpotiFLAC benötigt Speicherzugriff, um deine Musikbibliothek zu scannen. Bitte erteile die Berechtigung in den Einstellungen.';

  @override
  String get libraryFolderNotExist => 'Der ausgewählte Ordner existiert nicht';

  @override
  String get librarySourceDownloaded => 'Heruntergeladen';

  @override
  String get librarySourceLocal => 'Lokal';

  @override
  String get libraryFilterAll => 'Alle';

  @override
  String get libraryFilterDownloaded => 'Heruntergeladen';

  @override
  String get libraryFilterLocal => 'Lokal';

  @override
  String get libraryFilterTitle => 'Filter';

  @override
  String get libraryFilterReset => 'Zurücksetzen';

  @override
  String get libraryFilterApply => 'Anwenden';

  @override
  String get libraryFilterSource => 'Quelle';

  @override
  String get libraryFilterQuality => 'Qualität';

  @override
  String get libraryFilterQualityHiRes => 'Hi-Res (24bit)';

  @override
  String get libraryFilterQualityCD => 'CD (16bit)';

  @override
  String get libraryFilterQualityLossy => 'Verlustbehaftet';

  @override
  String get libraryFilterFormat => 'Format';

  @override
  String get libraryFilterMetadata => 'Metadaten';

  @override
  String get libraryFilterMetadataComplete => 'Komplette Metadaten';

  @override
  String get libraryFilterMetadataMissingAny => 'Metadaten fehlen';

  @override
  String get libraryFilterMetadataMissingYear => 'Jahr fehlt';

  @override
  String get libraryFilterMetadataMissingGenre => 'Genre fehlt';

  @override
  String get libraryFilterMetadataMissingAlbumArtist =>
      'Fehlender Album-Künstler';

  @override
  String get libraryFilterSort => 'Sortieren';

  @override
  String get libraryFilterSortLatest => 'Neuste';

  @override
  String get libraryFilterSortOldest => 'Älteste';

  @override
  String get libraryFilterSortAlbumAsc => 'Album (A-Z)';

  @override
  String get libraryFilterSortAlbumDesc => 'Album (Z-A)';

  @override
  String get libraryFilterSortGenreAsc => 'Genre (A-Z)';

  @override
  String get libraryFilterSortGenreDesc => 'Genre (Z-A)';

  @override
  String get timeJustNow => 'Gerade eben';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Minuten',
      one: 'vor 1 Minute',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor 1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => 'Willkommen bei SpotiFLAC!';

  @override
  String get tutorialWelcomeDesc =>
      'Lass uns lernen, wie du deine Lieblingsmusik in verlustfreier Qualität herunterlädst. Dieses schnelle Tutorial zeigt dir die Grundlagen.';

  @override
  String get tutorialWelcomeTip1 =>
      'Lade Musik von Spotify, Deezer herunter oder jeden unterstützten Link einfügen';

  @override
  String get tutorialWelcomeTip2 =>
      'Hole dir FLAC Audio von Tidal, Qobuz oder Deezer';

  @override
  String get tutorialWelcomeTip3 =>
      'Automatische Metadaten, Cover und Lyrics einbetten';

  @override
  String get tutorialSearchTitle => 'Suche Musik';

  @override
  String get tutorialSearchDesc =>
      'Es gibt zwei einfache Möglichkeiten, Musik zu finden, die du herunterladen möchtest.';

  @override
  String get tutorialDownloadTitle => 'Musik wird heruntergeladen';

  @override
  String get tutorialDownloadDesc =>
      'Das Herunterladen von Musik ist einfach und schnell. So funktioniert es.';

  @override
  String get tutorialLibraryTitle => 'Deine Bibliothek';

  @override
  String get tutorialLibraryDesc =>
      'Die gesamte heruntergeladene Musik ist in der Bibliothek organisiert.';

  @override
  String get tutorialLibraryTip1 =>
      'Fortschritt und Warteschlange im Bibliothek‑Tab anzeigen';

  @override
  String get tutorialLibraryTip2 =>
      'Tippe auf einen Titel, um ihn mit deinem Musikplayer abzuspielen';

  @override
  String get tutorialLibraryTip3 =>
      'Wechsle zwischen Listen- und Gitteransicht für ein besseres Surfen';

  @override
  String get tutorialExtensionsTitle => 'Erweiterungen';

  @override
  String get tutorialExtensionsDesc =>
      'Erweitere die Fähigkeiten der App mit Community-Erweiterungen.';

  @override
  String get tutorialExtensionsTip1 =>
      'Im Repo Tab findest du nützliche Erweiterungen';

  @override
  String get tutorialExtensionsTip2 =>
      'Neue Download- oder Suchanbieter hinzufügen';

  @override
  String get tutorialExtensionsTip3 =>
      'Lyrics, erweiterte Metadaten und mehr Funktionen erhalten';

  @override
  String get tutorialSettingsTitle => 'Passe deine Benutzererfahrung an';

  @override
  String get tutorialSettingsDesc =>
      'Personalisiere die App in den Einstellungen nach deiner Präferenz.';

  @override
  String get tutorialSettingsTip1 =>
      'Download-Ordner und Ordner-Organisation ändern';

  @override
  String get tutorialSettingsTip2 =>
      'Standard Audioqualität und Formateinstellungen festlegen';

  @override
  String get tutorialSettingsTip3 => 'App-Design und Aussehen anpassen';

  @override
  String get tutorialReadyMessage =>
      'Das ist alles! Lade jetzt deine Lieblingsmusik herunter.';

  @override
  String get libraryForceFullScan => 'Vollen Neu-Scan erzwingen';

  @override
  String get libraryForceFullScanSubtitle =>
      'Alle Dateien erneut scannen und Cache ignorieren';

  @override
  String get cleanupOrphanedDownloads => 'Verwaiste Downloads bereinigen';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      'Verlaufseinträge für Dateien löschen, die nicht mehr existieren';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return 'Entfernte $count verwaiste Einträge aus dem Verlauf';
  }

  @override
  String get cleanupOrphanedDownloadsNone =>
      'Keine verwaisten Einträge gefunden';

  @override
  String get cacheTitle => 'Speicher & Cache';

  @override
  String get cacheSummaryTitle => 'Cache-Übersicht';

  @override
  String get cacheSummarySubtitle =>
      'Das Leeren des Caches entfernt nicht heruntergeladene Musikdateien.';

  @override
  String cacheEstimatedTotal(String size) {
    return 'Geschätzte Cache-Größe: $size';
  }

  @override
  String get cacheSectionStorage => 'Zwischengespeicherte Daten';

  @override
  String get cacheSectionMaintenance => 'Wartung';

  @override
  String get cacheAppDirectory => 'App-Cache Ordner';

  @override
  String get cacheAppDirectoryDesc =>
      'HTTP-Antworten, WebView Daten und andere temporäre App-Daten.';

  @override
  String get cacheTempDirectory => 'Temporärer Ordner';

  @override
  String get cacheTempDirectoryDesc =>
      'Temporäre Dateien von Downloads und Audio-Konvertierung.';

  @override
  String get cacheCoverImage => 'Cover-Cache';

  @override
  String get cacheCoverImageDesc =>
      'Album- und Titelcover heruntergeladen. Werden erneut heruntergeladen.';

  @override
  String get cacheLibraryCover => 'Bibliotheks-Cover-Cache';

  @override
  String get cacheLibraryCoverDesc =>
      'Cover aus lokalen Musikdateien extrahiert. Wird beim nächsten Scannen neu extrahiert.';

  @override
  String get cacheExploreFeed => 'Feed-Cache entdecken';

  @override
  String get cacheExploreFeedDesc =>
      'Startseiten-Inhalt (neue Releases, Trends). Wird bei einem Neustart aktualisiert.';

  @override
  String get cacheTrackLookup => 'Titel Such-Cache';

  @override
  String get cacheTrackLookupDesc =>
      'Spotify/Deezer Track-ID-Lookups. Das Löschen kann die nächsten Suchergebnisse verlangsamen.';

  @override
  String get cacheCleanupUnusedDesc =>
      'Verwaisten Downloadverlauf und Bibliothekseinträge für fehlende Dateien entfernen.';

  @override
  String get cacheNoData => 'Keine gecachten Daten';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$size in $count Dateien';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count Einträge';
  }

  @override
  String cacheClearSuccess(String target) {
    return 'Entfernt: $target';
  }

  @override
  String get cacheClearConfirmTitle => 'Cache leeren?';

  @override
  String cacheClearConfirmMessage(String target) {
    return 'Dies löscht zwischengespeicherte Daten in $target. Die Musikdateien werden nicht gelöscht.';
  }

  @override
  String get cacheClearAllConfirmTitle => 'Gesamten Cache leeren?';

  @override
  String get cacheClearAllConfirmMessage =>
      'Dadurch werden alle Cache-Kategorien auf dieser Seite gelöscht. Heruntergeladene Musikdateien werden nicht gelöscht.';

  @override
  String get cacheClearAll => 'Gesamten Cache leeren';

  @override
  String get cacheCleanupUnused => 'Unbenutzte Daten bereinigen';

  @override
  String get cacheCleanupUnusedSubtitle =>
      'Verwaisten Downloadverlauf und fehlende Bibliothekseinträge löschen';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return 'Bereinigung: $downloadCount verwaiste Downloads, $libraryCount fehlende Bibliothekseinträge';
  }

  @override
  String get cacheRefreshStats => 'Statistik aktualisieren';

  @override
  String get trackSaveCoverArt => 'Cover speichern';

  @override
  String get trackSaveCoverArtSubtitle => 'Albumcover als .jpg Datei speichern';

  @override
  String get trackSaveLyrics => 'Lyrics als .lrc speichern';

  @override
  String get trackSaveLyricsSubtitle => 'Lade Lyrics als .lrc Datei';

  @override
  String get trackSaveLyricsProgress => 'Speichere Lyrics...';

  @override
  String get trackReEnrich => 'Neu-anreichern';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Metadaten online suchen und in Datei einbinden';

  @override
  String get trackReEnrichFieldsTitle => 'Felder zum Aktualisieren';

  @override
  String get trackReEnrichFieldCover => 'Cover-Art';

  @override
  String get trackReEnrichFieldLyrics => 'Lyrics';

  @override
  String get trackReEnrichFieldBasicTags => 'Album, Album-Künstler';

  @override
  String get trackReEnrichFieldTrackInfo => 'Track & Disc Nummer';

  @override
  String get trackReEnrichFieldReleaseInfo => 'Datum & ISRC';

  @override
  String get trackReEnrichFieldExtra => 'Genre, Label, Copyright';

  @override
  String get trackReEnrichSelectAll => 'Alles Auswählen';

  @override
  String get trackEditMetadata => 'Metadaten bearbeiten';

  @override
  String trackCoverSaved(String fileName) {
    return 'Cover in $fileName gespeichert';
  }

  @override
  String get trackCoverNoSource => 'Keine Cover Quelle vorhanden';

  @override
  String trackLyricsSaved(String fileName) {
    return 'Lyrics in $fileName gespeichert';
  }

  @override
  String get trackReEnrichProgress => 'Metadaten neu anreichern...';

  @override
  String get trackReEnrichSearching => 'Suche Metadaten online...';

  @override
  String get trackReEnrichSuccess => 'Metadaten erfolgreich neu angereichert';

  @override
  String get trackReEnrichFfmpegFailed =>
      'FFmpeg Metadaten-Einbettung fehlgeschlagen';

  @override
  String get queueFlacAction => 'Warteschlange FLAC';

  @override
  String queueFlacConfirmMessage(int count) {
    return 'Suche Online-Matches für ausgewählte Titel und Playlists für FLAC-Downloads.\n\nVorhandene Dateien werden weder geändert noch gelöscht.\n\nNur eindeutige Treffer werden automatisch zur Warteschlange hinzugefügt.\n\n$count ausgewählt';
  }

  @override
  String queueFlacFindingProgress(int current, int total) {
    return 'Suche nach FLAC-Übereinstimmungen... ($current/$total)';
  }

  @override
  String get queueFlacNoReliableMatches =>
      'Keine zuverlässigen Online-Übereinstimmungen für die Auswahl gefunden';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return '$addedCount Titel zur Warteschlange hinzugefügt, $skippedCount übersprungen';
  }

  @override
  String trackSaveFailed(String error) {
    return 'Fehler: $error';
  }

  @override
  String get trackConvertFormat => 'Format konvertieren';

  @override
  String get trackConvertFormatSubtitle =>
      'Zu AAC/M4A, MP3, Opus, ALAC oder FLAC konvertieren';

  @override
  String get trackConvertTitle => 'Audio konvertieren';

  @override
  String get trackConvertTargetFormat => 'Zielformat';

  @override
  String get trackConvertBitrate => 'Bitrate';

  @override
  String get trackConvertConfirmTitle => 'Konvertierung bestätigen';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return 'Konvertieren von $sourceFormat in $targetFormat bei $bitrate?\n\nDie Originaldatei wird nach der Konvertierung gelöscht.';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Konvertieren von $sourceFormat in $targetFormat? (kein Qualitätsverlust)\n\nDie Originaldatei wird nach der Konvertierung gelöscht.';
  }

  @override
  String get trackConvertLosslessHint =>
      'Verlustfreie Konvertierung kein Qualitätsverlust';

  @override
  String get trackConvertConverting => 'Konvertiere Audio...';

  @override
  String trackConvertSuccess(String format) {
    return 'Konvertiert in $format erfolgreich';
  }

  @override
  String get trackConvertFailed => 'Konvertierung fehlgeschlagen';

  @override
  String get cueSplitTitle => 'CUE-Sheet aufteilen';

  @override
  String get cueSplitSubtitle => 'CUE+FLAC in einzelne Titel aufteilen';

  @override
  String cueSplitAlbum(String album) {
    return 'Album: $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return 'Künstler: $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count Titel';
  }

  @override
  String get cueSplitConfirmTitle => 'CUE-Album aufteilen';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return 'Soll „$album“ in $count einzelne FLAC-Dateien aufgeteilt werden?\n\nDie Dateien werden im selben Ordner gespeichert.';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'CUE-Sheet wird geteilt... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return '$count Titel erfolgreich aufgeteilt';
  }

  @override
  String get cueSplitFailed => 'CUE-Aufteilung fehlgeschlagen';

  @override
  String get cueSplitNoAudioFile =>
      'Audiodatei für dieses CUE-Sheet nicht gefunden';

  @override
  String get cueSplitButton => 'In Titel aufteilen';

  @override
  String get actionCreate => 'Erstellen';

  @override
  String get collectionFoldersTitle => 'Meine Ordner';

  @override
  String get collectionWishlist => 'Wunschliste';

  @override
  String get collectionLoved => 'Lieblingssongs';

  @override
  String get collectionFavoriteArtists => 'Lieblingskünstler';

  @override
  String get collectionPlaylists => 'Playlists';

  @override
  String get collectionPlaylist => 'Playlist';

  @override
  String get collectionAddToPlaylist => 'Zur Playlist hinzufügen';

  @override
  String get collectionCreatePlaylist => 'Playlist erstellen';

  @override
  String get collectionNoPlaylistsYet => 'Noch keine Playlists';

  @override
  String get collectionNoPlaylistsSubtitle =>
      'Playlist erstellen, um Titel zu kategorisieren';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel',
      one: '1 Titel',
    );
    return '$_temp0';
  }

  @override
  String collectionArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Künstler',
      one: '1 Künstler',
    );
    return '$_temp0';
  }

  @override
  String collectionAddedToPlaylist(String playlistName) {
    return 'Zu \"$playlistName \" hinzugefügt';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return 'Bereits in \"$playlistName\"';
  }

  @override
  String get collectionPlaylistCreated => 'Playlist erstellt';

  @override
  String get collectionPlaylistNameHint => 'Playlist-Name';

  @override
  String get collectionPlaylistNameRequired => 'Playlist-Name ist erforderlich';

  @override
  String get collectionRenamePlaylist => 'Playlist umbenennen';

  @override
  String get collectionDeletePlaylist => 'Playlist löschen';

  @override
  String collectionDeletePlaylistMessage(String playlistName) {
    return 'Willst du \"$playlistName\" und alle darin enthaltenen Titel löschen?';
  }

  @override
  String get collectionPlaylistDeleted => 'Playlist gelöscht';

  @override
  String get collectionPlaylistRenamed => 'Playlist umbenannt';

  @override
  String get collectionWishlistEmptyTitle => 'Wunschliste ist leer';

  @override
  String get collectionWishlistEmptySubtitle =>
      'Tippe auf das + bei den Titeln, um sie zum späteren Herunterladen zu speichern';

  @override
  String get collectionLovedEmptyTitle => 'Lieblingssongs sind leer';

  @override
  String get collectionLovedEmptySubtitle =>
      'Tippe auf das Herz, um deine Favoriten zu behalten';

  @override
  String get collectionFavoriteArtistsEmptyTitle =>
      'Noch keine Lieblingskünstler';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      'Tippe auf das Herz auf einer Künstlerseite, um sie hier zu sehen';

  @override
  String get collectionPlaylistEmptyTitle => 'Die Playlist ist leer';

  @override
  String get collectionPlaylistEmptySubtitle =>
      'Drücke lange + auf einem beliebigen Titel, um ihn hier hinzuzufügen';

  @override
  String get collectionRemoveFromPlaylist => 'Von Playlist entfernen';

  @override
  String get collectionRemoveFromFolder => 'Aus Ordner entfernen';

  @override
  String collectionRemoved(String trackName) {
    return '\"$trackName\" entfernt';
  }

  @override
  String collectionAddedToLoved(String trackName) {
    return '\"$trackName\" zu Lieblingssongs hinzugefügt';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\"$trackName\" aus Lieblingssongs entfernt';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '\"$trackName\" zur Wunschliste hinzugefügt';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '\"$trackName\" aus der Wunschliste entfernt';
  }

  @override
  String collectionAddedToFavoriteArtists(String artistName) {
    return '\"$artistName\" zu Lieblingskünstlern hinzugefügt';
  }

  @override
  String collectionRemovedFromFavoriteArtists(String artistName) {
    return '\"$artistName\" entfernt aus Lieblingskünstlern';
  }

  @override
  String get trackOptionAddToLoved => 'Zu Lieblingssongs hinzufügen';

  @override
  String get trackOptionRemoveFromLoved => 'Aus Lieblingssongs entfernt';

  @override
  String get trackOptionAddToWishlist => 'Zur Wunschliste hinzufügen';

  @override
  String get trackOptionRemoveFromWishlist => 'Von der Wunschliste entfernen';

  @override
  String get artistOptionAddToFavorites => 'Zu Favoriten hinzufügen';

  @override
  String get artistOptionRemoveFromFavorites => 'Aus Favoriten entfernen';

  @override
  String get collectionPlaylistChangeCover => 'Coverbild ändern';

  @override
  String get collectionPlaylistRemoveCover => 'Cover entfernen';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Teile $count $_temp0';
  }

  @override
  String get selectionShareNoFiles => 'Keine teilbare Dateien gefunden';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Konvertiere $count $_temp0';
  }

  @override
  String get selectionConvertNoConvertible =>
      'Keine konvertierbare Titel ausgewählt';

  @override
  String get selectionBatchConvertConfirmTitle => 'Batch-Konvertierung';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Konvertiere $count $format $_temp0 zu $bitrate?\n\nOriginaldateien werden nach der Konvertierung gelöscht.';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Konvertiere $count $_temp0 in $format? (kein Qualitätsverlust)\n\nOriginaldateien werden nach der Konvertierung gelöscht.';
  }

  @override
  String selectionBatchConvertProgress(int current, int total) {
    return 'Konvertiere $current von $total...';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return '$success von $total Titeln in $format konvertiert';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count heruntergeladen';
  }

  @override
  String get downloadUseAlbumArtistForFoldersAlbumSubtitle =>
      'Ordner benannt nach dem Tag des Albumkünstlers';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      'Ordner benannt nach dem Tag des Künstlers';

  @override
  String get lyricsProvidersTitle => 'Priorität des Lyrics-Anbieters';

  @override
  String get lyricsProvidersDescription =>
      'Lyrics aktivieren, deaktivieren und neu ordnen. Anbieter werden von oben nach unten ausprobiert, bis Lyrics gefunden werden.';

  @override
  String get lyricsProvidersInfoText =>
      'Erweiterungsanbieter werden immer vor eingebauten ausgeführt. Mindestens ein Anbieter muss aktiviert bleiben.';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return '($count) aktiviert';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return '($count) deaktiviert';
  }

  @override
  String get lyricsProvidersAtLeastOne =>
      'Mindestens ein Anbieter muss aktiviert bleiben';

  @override
  String get lyricsProvidersSaved =>
      'Priorität des Lyrics-Anbieters gespeichert';

  @override
  String get lyricsProvidersDiscardContent =>
      'Ungespeicherte Änderungen die verloren gehen.';

  @override
  String get lyricsProviderLrclibDesc =>
      'Open-Source-Synchronisierte Lyrics-Datenbank';

  @override
  String get lyricsProviderNeteaseDesc =>
      'NetEase Cloud Music (gut für asiatische Lieder)';

  @override
  String get lyricsProviderMusixmatchDesc =>
      'Größte Lyrics-Datenbank (mehrsprachig)';

  @override
  String get lyricsProviderAppleMusicDesc =>
      'Wort-für-Wort-synchronisierte Lyrics (via Proxy)';

  @override
  String get lyricsProviderQqMusicDesc =>
      'QQ Music (gut für chinesische Lieder, via Proxy)';

  @override
  String get lyricsProviderExtensionDesc => 'Erweiterungsanbieter';

  @override
  String get safMigrationTitle => 'Speicheraktualisierung erforderlich';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC verwendet jetzt Android Storage Access Framework (SAF) beim Herunterladen. Dies behebt Fehler bei Android 10+.';

  @override
  String get safMigrationMessage2 =>
      'Bitte wähle dein Download-Ordner erneut aus, um zum neuen System zu wechseln.';

  @override
  String get safMigrationSuccess =>
      'Download-Ordner auf SAF-Modus aktualisiert';

  @override
  String get settingsDonate => 'Unterstütze die Entwicklung';

  @override
  String get settingsDonateSubtitle => 'Kaufe dem Entwickler einen Kaffee';

  @override
  String get tooltipLoveAll => 'Alle lieben';

  @override
  String get tooltipAddToPlaylist => 'Zur Wiedergabeliste hinzufügen';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return '$count Titel von geliebt entfernt';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return '$count titel zu geliebt hinzugefügt';
  }

  @override
  String get dialogDownloadAllTitle => 'Alle Herunterladen';

  @override
  String dialogDownloadAllMessage(int count) {
    return '$count titel herunterladen?';
  }

  @override
  String get homeSkipAlreadyDownloaded =>
      'Bereits heruntergeladene Titel überspringen';

  @override
  String get homeGoToAlbum => 'Zum Album gehen';

  @override
  String get homeAlbumInfoUnavailable => 'Albuminfo nicht verfügbar';

  @override
  String get snackbarLoadingCueSheet => 'CAE-Sheet wird geladen...';

  @override
  String get snackbarMetadataSaved => 'Metadaten erfolgreich gespeichert';

  @override
  String get snackbarFailedToEmbedLyrics => 'Fehler beim Einbinden der Lyrics';

  @override
  String get snackbarFailedToWriteStorage =>
      'Fehler beim Zurückschreiben in den Speicher';

  @override
  String snackbarError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get snackbarNoActionDefined => 'Keine Aktion für Taste definiert';

  @override
  String get noTracksFoundForAlbum => 'Keine Titel in diesem Album gefunden';

  @override
  String get downloadLocationSubtitle =>
      'Wählen Sie den Speicherort für Ihre heruntergeladenen Titel';

  @override
  String get storageModeAppFolder => 'App-Ordner (empfohlen)';

  @override
  String get storageModeAppFolderSubtitle =>
      'Standardmäßig in Music/SpotiFLAC speichern';

  @override
  String get storageModeSaf => 'Benutzerdefinierter Ordner (SAF)';

  @override
  String get storageModeSafSubtitle =>
      'Wähle einen beliebigen Ordner, inklusive SD-Karte';

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
    return 'Verwende $artist, $title, $album, $track, $year, $date, $disc als Platzhalter.';
  }

  @override
  String get downloadFilenameInsertTag => 'Tippe, um Tag einzufügen:';

  @override
  String get downloadSeparateSinglesEnabled =>
      'Singles und EPs werden in einem separaten Ordner gespeichert';

  @override
  String get downloadSeparateSinglesDisabled =>
      'Singles und Alben im selben Ordner gespeichert';

  @override
  String get downloadArtistNameFilters => 'Künstlernamen-Filter';

  @override
  String get downloadCreatePlaylistSourceFolder => 'Playlist-Quellordner';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      'Für jede Playlist wird ein Unterordner erstellt';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      'Alle Titel direkt im Download-Ordner gespeichert';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant =>
      'Wird durch die Ordnerorganisationseinstellung verarbeitet';

  @override
  String get downloadSongLinkRegion => 'SongLink-Region';

  @override
  String get downloadNetworkCompatibilityMode => 'Netzwerkkompatibilitätsmodus';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Verwendung der Legacy-TLS-Einstellungen für ältere Netzwerke';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Standard-Netzwerkeinstellungen verwenden';

  @override
  String get downloadSelectServiceToEnable =>
      'Wähle Tidal oder Qobuz, um diese Option zu aktivieren';

  @override
  String get downloadSelectTidalQobuz =>
      'Wähle Tidal oder Qobuz, um die Audioqualität auszuwählen';

  @override
  String get downloadEmbedLyricsDisabled =>
      'Metadaten-Einbettung zuerst aktivieren';

  @override
  String get downloadNeteaseIncludeTranslation =>
      'Netease: Übersetzung einschließen';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Chinesische Übersetzungszeilen enthalten';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Original Lyrics verwenden';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease: Romanisierung einschließen';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled =>
      'Romanisierungszeilen enthalten';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled =>
      'Keine Romanisierung';

  @override
  String get downloadAppleQqMultiPerson => 'Apple / QQ: Multi-Personen-Lyrics';

  @override
  String get downloadAppleQqMultiPersonEnabled =>
      'Sängerlabel für Duette und Gruppentitel enthalten';

  @override
  String get downloadAppleQqMultiPersonDisabled =>
      'Standardlyrics ohne Lautsprecher-Labels';

  @override
  String get downloadAppleElrcWordSync => 'Apple Music eLRC Word Sync';

  @override
  String get downloadAppleElrcWordSyncEnabled => 'Rohe Zeitstempel erhalten';

  @override
  String get downloadAppleElrcWordSyncDisabled =>
      'Sichere Line-by-line Apple Music Texte';

  @override
  String get downloadMusixmatchLanguage => 'Musixmatch Sprache';

  @override
  String get downloadMusixmatchLanguageAuto => 'Auto (Originalsprache)';

  @override
  String get downloadFilterContributing => 'Mitwirkende Künstler filtern';

  @override
  String get downloadFilterContributingEnabled =>
      'Mitwirkende Künstler vom Albumname des Künstlers entfernt';

  @override
  String get downloadFilterContributingDisabled =>
      'Volle Album Künstler String verwendet';

  @override
  String get downloadProvidersNoneEnabled => 'Keine Anbieter aktiviert';

  @override
  String get downloadMusixmatchLanguageCode => 'Sprach-Code';

  @override
  String get downloadMusixmatchLanguageHint => 'e.g. en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Gib einen BCP-47 Sprachcode ein (z.B. en, de, ja), um übersetzte Lyrics von Musixmatch anzufordern.';

  @override
  String get downloadMusixmatchAuto => 'Auto';

  @override
  String get downloadNetworkAnySubtitle => 'WLAN oder mobile Daten verwenden';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Downloads bei mobilen Daten pausieren';

  @override
  String get downloadSongLinkRegionDesc =>
      'Region, die beim Auflösen von Titellinks über SongLink verwendet wird. Wähle das Land, in dem der Streaming-Dienste verfügbar sind.';

  @override
  String get snackbarUnsupportedAudioFormat =>
      'Nicht unterstütztes Audioformat';

  @override
  String get cacheRefresh => 'Aktualisieren';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: 'Playlists',
      one: 'Playlist',
    );
    return 'Lade $trackCount $_temp0 von $playlistCount $_temp1?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Playlists',
      one: 'Playlist',
    );
    return 'Lade $count $_temp0 herunter';
  }

  @override
  String get bulkDownloadSelectPlaylists => 'Playlist zum Herunterladen wählen';

  @override
  String get snackbarSelectedPlaylistsEmpty =>
      'Ausgewählte Playlisten haben keine Titel';

  @override
  String playlistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Playlists',
      one: '1 Playlist',
    );
    return '$_temp0';
  }

  @override
  String get editMetadataAutoFill => 'Aus online ausfüllen';

  @override
  String get editMetadataAutoFillDesc =>
      'Wähle Felder aus, die automatisch aus Online-Metadaten ausgefüllt werden sollen';

  @override
  String get editMetadataAutoFillFetch => 'Abrufen & Ausfüllen';

  @override
  String get editMetadataAutoFillSearching => 'Online suchen...';

  @override
  String get editMetadataAutoFillNoResults =>
      'Keine passenden Metadaten online gefunden';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Felder',
      one: 'Feld',
    );
    return '$count $_temp0 aus Online-Metadaten gefüllt';
  }

  @override
  String get editMetadataAutoFillNoneSelected =>
      'Wähle mindestens ein Feld zum automatischen Ausfüllen aus';

  @override
  String get editMetadataFieldTitle => 'Titel';

  @override
  String get editMetadataFieldArtist => 'Künstler';

  @override
  String get editMetadataFieldAlbum => 'Album';

  @override
  String get editMetadataFieldAlbumArtist => 'Album Künstler';

  @override
  String get editMetadataFieldDate => 'Datum';

  @override
  String get editMetadataFieldTrackNum => 'Titel #';

  @override
  String get editMetadataFieldDiscNum => 'Disk #';

  @override
  String get editMetadataFieldGenre => 'Genre';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => 'Label';

  @override
  String get editMetadataFieldCopyright => 'Urheberrecht';

  @override
  String get editMetadataFieldCover => 'Cover-Art';

  @override
  String get editMetadataSelectAll => 'Alle';

  @override
  String get editMetadataSelectEmpty => 'Nur leer';

  @override
  String queueDownloadingCount(int count) {
    return '$count werden heruntergeladen';
  }

  @override
  String get queueDownloadedHeader => 'Heruntergeladen';

  @override
  String get queueFilteringIndicator => 'Filtere...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel',
      one: '1 Titel',
    );
    return '$_temp0';
  }

  @override
  String queueAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Alben',
      one: '1 Album',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyAlbums => 'Keine Album-Downloads';

  @override
  String get queueEmptyAlbumsSubtitle =>
      'Lade mehrere Titel eines Albums herunter, um sie hier zu sehen';

  @override
  String get queueEmptySingles => 'Kein Single Download';

  @override
  String get queueEmptySinglesSubtitle =>
      'Einzelne Titel-Downloads werden hier angezeigt';

  @override
  String get queueEmptyHistory => 'Kein Download-Verlauf';

  @override
  String get queueEmptyHistorySubtitle =>
      'Heruntergeladene Titel werden hier angezeigt';

  @override
  String get selectionAllPlaylistsSelected => 'Alle Playlists ausgewählt';

  @override
  String get selectionTapPlaylistsToSelect =>
      'Zum Auswählen auf Playlists tippen';

  @override
  String get selectionSelectPlaylistsToDelete => 'Playlist zum Löschen wählen';

  @override
  String get audioAnalysisTitle => 'Audio-Qualitätsanalyse';

  @override
  String get audioAnalysisDescription =>
      'Verlustfreie Qualität mit Spektrumanalyse überprüfen';

  @override
  String get audioAnalysisAnalyzing => 'Audio wird analysiert...';

  @override
  String get audioAnalysisSampleRate => 'Sample Rate';

  @override
  String get audioAnalysisCodec => 'Codec';

  @override
  String get audioAnalysisContainer => 'Container';

  @override
  String get audioAnalysisDecodedFormat => 'Dekodiertes Format';

  @override
  String get audioAnalysisBitDepth => 'Bit-Tiefe';

  @override
  String get audioAnalysisChannels => 'Kanäle';

  @override
  String get audioAnalysisDuration => 'Länge';

  @override
  String get audioAnalysisNyquist => 'Nyquist';

  @override
  String get audioAnalysisFileSize => 'Größe';

  @override
  String get audioAnalysisDynamicRange => 'Dynamischer Bereich';

  @override
  String get audioAnalysisPeak => 'Maximum';

  @override
  String get audioAnalysisRms => 'RMS';

  @override
  String get audioAnalysisLufs => 'LUFS';

  @override
  String get audioAnalysisTruePeak => 'True Peak';

  @override
  String get audioAnalysisClipping => 'Clipping';

  @override
  String get audioAnalysisNoClipping => 'Kein Clipping';

  @override
  String get audioAnalysisSpectralCutoff => 'Spektralschnitt';

  @override
  String get audioAnalysisChannelStats => 'Pro Kanal Statistik';

  @override
  String get audioAnalysisSamples => 'Proben';

  @override
  String get audioAnalysisRescan => 'Neu analysieren';

  @override
  String get audioAnalysisRescanning => 'Audio wird analysiert...';

  @override
  String extensionsSearchWith(String providerName) {
    return 'Mit $providerName suchen';
  }

  @override
  String get extensionsHomeFeedProvider => 'Home Feed Anbieter';

  @override
  String get extensionsHomeFeedDescription =>
      'Wählen Sie die Erweiterung aus, die den Start-Feed auf dem Hauptbildschirm anzeigt';

  @override
  String get extensionsHomeFeedAuto => 'Auto';

  @override
  String get extensionsHomeFeedAutoSubtitle =>
      'Automatisch die besten verfügbaren auswählen';

  @override
  String get extensionsHomeFeedOff => 'Aus';

  @override
  String get extensionsHomeFeedOffSubtitle =>
      'Start-Feed nicht auf dem Hauptbildschirm anzeigen';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return '$extensionName Home Feed verwenden';
  }

  @override
  String get extensionsNoHomeFeedExtensions =>
      'Keine Erweiterungen mit Home-Feed';

  @override
  String get sortAlphaAsc => 'A-Z';

  @override
  String get sortAlphaDesc => 'Z-A';

  @override
  String get cancelDownloadTitle => 'Download abbrechen?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'Dadurch wird der aktive Download für \"$trackName\" abgebrochen.';
  }

  @override
  String get cancelDownloadKeep => 'Behalten';

  @override
  String get metadataSaveFailedFfmpeg =>
      'Fehler beim Speichern der Metadaten über FFmpeg';

  @override
  String get metadataSaveFailedStorage =>
      'Metadaten konnten nicht zurück in den Speicher geschrieben werden';

  @override
  String snackbarFolderPickerFailed(String error) {
    return 'Fehler beim Öffnen des Ordners: $error';
  }

  @override
  String get errorLoadAlbum => 'Fehler beim Laden des Albums';

  @override
  String get errorLoadPlaylist => 'Fehler beim Laden der Playlist';

  @override
  String get errorLoadArtist => 'Fehler beim Laden des Interpreten';

  @override
  String get notifChannelDownloadName => 'Download Fortschritt';

  @override
  String get notifChannelDownloadDesc =>
      'Zeigt Download-Fortschritt für Titel an';

  @override
  String get notifChannelLibraryScanName => 'Bibliotheksscan';

  @override
  String get notifChannelLibraryScanDesc =>
      'Zeigt den Fortschritt des lokalen Bibliotheksscans an';

  @override
  String notifDownloadingTrack(String trackName) {
    return '$trackName wird heruntergeladen';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return '$trackName wird fertiggestellt';
  }

  @override
  String get notifEmbeddingMetadata => 'Bette Metadaten ein...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return 'Bereits in der Bibliothek ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => 'Bereits in der Bibliothek';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return 'Download abgeschlossen ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => 'Download abgeschlossen';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return 'Downloads abgeschlossen ($completed fertig, $failed fehlgeschlagen)';
  }

  @override
  String get notifAllDownloadsComplete => 'Alle Downloads abgeschlossen';

  @override
  String notifTracksDownloadedSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel erfolgreich heruntergeladen',
      one: '1 Titel erfolgreich heruntergeladen',
    );
    return '$_temp0';
  }

  @override
  String notifDownloadsFinishedBody(int completed, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      completed,
      locale: localeName,
      other: '$completed Titel heruntergeladen',
      one: '1 Titel heruntergeladen',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed fehlgeschlagen',
      one: '1 fehlgeschlagen',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get notifDownloadsCanceledTitle => 'Downloads abgebrochen';

  @override
  String notifDownloadsCanceledBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Downloads vom Nutzer abgebrochen',
      one: '1 Download vom Nutzer abgebrochen',
    );
    return '$_temp0';
  }

  @override
  String get notifScanningLibrary => 'Scanne lokale Bibliothek';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total Dateien • $percentage%';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned gescannte Dateien • $percentage%';
  }

  @override
  String get notifLibraryScanComplete => 'Bibliotheksscan abgeschlossen';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count titel indiziert';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count ausgeschlossen';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count Fehler';
  }

  @override
  String get notifLibraryScanFailed => 'Bibliotheksscan fehlgeschlagen';

  @override
  String get notifLibraryScanCancelled => 'Bibliotheksscan abgebrochen';

  @override
  String get notifLibraryScanStopped => 'Scan wurde vor Abschluss gestoppt.';

  @override
  String notifDownloadingUpdate(String version) {
    return 'SpotiFLAC Mobile v$version wird heruntergeladen';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total MB • $percentage%';
  }

  @override
  String get notifUpdateReady => 'Update bereit';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC Mobile v$version heruntergeladen. Zum Installieren tippen.';
  }

  @override
  String get notifUpdateFailed => 'Update fehlgeschlagen';

  @override
  String get notifUpdateFailedBody =>
      'Update konnte nicht heruntergeladen werden. Versuche es später erneut.';

  @override
  String get searchTracks => 'Titel';

  @override
  String get homeSearchHintDefault =>
      'Unterstützte URL einfügen oder suchen...';

  @override
  String homeSearchHintProvider(String providerName) {
    return 'Mit $providerName suchen...';
  }

  @override
  String get homeImportCsvTooltip => 'CSV-Datei importieren';

  @override
  String get homeChangeSearchProviderTooltip => 'Suchanbieter ändern';

  @override
  String get actionPaste => 'Einfügen';

  @override
  String get searchTracksHint => 'Titel suchen...';

  @override
  String get searchTracksEmptyPrompt => 'Nach Titel suchen';

  @override
  String get tutorialSearchHint => 'Einfügen oder suchen...';

  @override
  String get tutorialDownloadCompletedSemantics => 'Download abgeschlossen';

  @override
  String get tutorialDownloadInProgressSemantics => 'Download wird ausgeführt';

  @override
  String get tutorialStartDownloadSemantics => 'Download starten';

  @override
  String get optionsEmbedMetadata => 'Eingebettete Metadaten';

  @override
  String get optionsEmbedMetadataSubtitleOn =>
      'Schreibe Metadaten, Cover und eingebettete Songtexte in Dateien';

  @override
  String get optionsEmbedMetadataSubtitleOff =>
      'Deaktiviert (erweitert): Metadateneinbettung überspringen';

  @override
  String get optionsMaxQualityCoverSubtitleDisabled =>
      'Deaktiviert, wenn Metadateneinbettung aus ist';

  @override
  String downloadFilenameHintExample(Object artist, Object title) {
    return '$artist - $title';
  }

  @override
  String get trackCoverNoEmbeddedArt =>
      'Kein eingebettetes Albumcover gefunden';

  @override
  String get trackCoverReplace => 'Cover ersetzen';

  @override
  String get trackCoverPick => 'Cover auswählen';

  @override
  String get trackCoverClearSelected => 'Ausgewähltes Cover löschen';

  @override
  String get trackCoverCurrent => 'Aktuelles Cover';

  @override
  String get trackCoverSelected => 'Ausgewähltes Cover';

  @override
  String get trackCoverReplaceNotice =>
      'Das ausgewählte Cover ersetzt das aktuell eingebettete Cover, wenn auf speichern gedrückt wird.';

  @override
  String get actionStop => 'Stop';

  @override
  String get queueFinalizingDownload => 'Download wird abgeschlossen';

  @override
  String get queueDownloadedFileMissing => 'Heruntergeladene Datei fehlt';

  @override
  String get queueDownloadCompleted => 'Download abgeschlossen';

  @override
  String get queueRateLimitTitle => 'Service rate limited';

  @override
  String get queueRateLimitMessage =>
      'This track may still be available. Wait a few minutes, reduce parallel downloads, then retry.';

  @override
  String appearanceSelectAccentColor(String hex) {
    return 'Wähle Akzentfarbe $hex';
  }

  @override
  String get logAutoScrollOn => 'Auto-Scrollen AN';

  @override
  String get logAutoScrollOff => 'Auto-Scrollen AUS';

  @override
  String get logCopyLogs => 'Logs kopieren';

  @override
  String get logClearSearch => 'Suche löschen';

  @override
  String get logIssueIspBlockingLabel => 'ISP BLOCKIERUNG ERKANNT';

  @override
  String get logIssueIspBlockingDescription =>
      'Dein ISP blockiert möglicherweise den Zugriff auf den Download Dienst';

  @override
  String get logIssueIspBlockingSuggestion =>
      'Versuche es einem VPN oder ändere DNS auf 1.1.1.1 oder 8.8.8.8';

  @override
  String get logIssueRateLimitedLabel => 'LIMIT ERKANNT';

  @override
  String get logIssueRateLimitedDescription =>
      'Zu viele Anfragen an den Dienst';

  @override
  String get logIssueRateLimitedSuggestion =>
      'Warte ein paar Minuten, bevor du es erneut versuchst';

  @override
  String get logIssueNetworkErrorLabel => 'NETZWERKFEHLER';

  @override
  String get logIssueNetworkErrorDescription => 'Verbindungsprobleme erkannt';

  @override
  String get logIssueNetworkErrorSuggestion =>
      'Überprüfe deine Internetverbindung';

  @override
  String get logIssueTrackNotFoundLabel => 'TITEL NICHT GEFUNDEN';

  @override
  String get logIssueTrackNotFoundDescription =>
      'Einige Titel konnten auf Download-Diensten nicht gefunden werden';

  @override
  String get logIssueTrackNotFoundSuggestion =>
      'Der Titel ist möglicherweise nicht in verlustfreier Qualität verfügbar';

  @override
  String get clickableLookingUpArtist => 'Künstler wird gesucht...';

  @override
  String clickableInformationUnavailable(String type) {
    return '$type Informationen nicht verfügbar';
  }

  @override
  String get extensionDetailsTags => 'Tags';

  @override
  String get extensionDetailsInformation => 'Info';

  @override
  String get extensionUtilityFunctions => 'Hilfsfunktionen';

  @override
  String get actionDismiss => 'Schließen';

  @override
  String get setupChangeFolderTooltip => 'Ordner ändern';

  @override
  String a11yOpenTrackByArtist(String trackName, String artistName) {
    return 'Öffne Track $trackName von $artistName';
  }

  @override
  String a11yOpenItem(String itemType, String name) {
    return '$itemType $name öffnen';
  }

  @override
  String a11yOpenItemCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Items',
      one: 'Item',
    );
    return 'Öffne $title, $count $_temp0';
  }

  @override
  String a11yOpenAlbumByArtistTrackCount(
    String albumName,
    String artistName,
    int trackCount,
  ) {
    return 'Öffne Album $albumName von $artistName, $trackCount Titel';
  }

  @override
  String a11yTrackByArtist(String trackName, String artistName) {
    return '$trackName von $artistName';
  }

  @override
  String a11ySelectAlbum(String albumName) {
    return 'Wähle Album $albumName';
  }

  @override
  String a11yOpenAlbum(String albumName) {
    return 'Album öffnen $albumName';
  }

  @override
  String get optionsDefaultSearchTabAlbums => 'Alben';

  @override
  String get optionsDefaultSearchTabTracks => 'Titel';

  @override
  String get settingsFiles => 'Dateien & Ordner';

  @override
  String get settingsFilesSubtitle => 'Speicherort, Dateiname, Ordnerstruktur';

  @override
  String get settingsMetadata => 'Metadaten';

  @override
  String get settingsMetadataSubtitle =>
      'Cover Art, Tags, ReplayGain, Anbieter';

  @override
  String get settingsLyrics => 'Lyrics';

  @override
  String get settingsLyricsSubtitle =>
      'Einbetten, Modus, Anbieter, Sprachoptionen';

  @override
  String get settingsApp => 'App';

  @override
  String get settingsAppSubtitle => 'Updates, Daten, Erweiterungsrepo, Debug';

  @override
  String get sectionMetadataProviders => 'Anbieter';

  @override
  String get sectionDuplicates => 'Duplikate';

  @override
  String get sectionLyricsProviderOptions => 'Anbieter-Optionen';

  @override
  String get metadataProvidersTitle => 'Priorität des Metadaten-Anbieters';

  @override
  String get metadataProvidersSubtitle =>
      'Zieh, um Such- und Metadatenquellenreihenfolge zu setzen';

  @override
  String get downloadDeduplication => 'Doppelte Downloads überspringen';

  @override
  String get downloadDeduplicationEnabled =>
      'Bereits heruntergeladene Titel werden übersprungen';

  @override
  String get downloadDeduplicationDisabled =>
      'Alle Titel werden unabhängig vom Verlauf heruntergeladen';

  @override
  String get downloadFallbackExtensions => 'Fallback-Erweiterungen';

  @override
  String get downloadFallbackExtensionsSubtitle =>
      'Wähle, welche Erweiterungen als Fallback verwendet werden können';

  @override
  String get editMetadataFieldDateHint => 'JJJJ-MM-TT oder JJJJJ';

  @override
  String get editMetadataFieldTrackTotal => 'Titel insgesamt';

  @override
  String get editMetadataFieldDiscTotal => 'Disc gesamt';

  @override
  String get editMetadataFieldComposer => 'Komponist';

  @override
  String get editMetadataFieldComment => 'Kommentar';

  @override
  String get editMetadataAdvanced => 'Erweitert';

  @override
  String get libraryFilterMetadataMissingTrackNumber => 'Fehlende Tracknummer';

  @override
  String get libraryFilterMetadataMissingDiscNumber => 'Fehlende Disc-Nummer';

  @override
  String get libraryFilterMetadataMissingArtist => 'Fehlender Künstler';

  @override
  String get libraryFilterMetadataIncorrectIsrcFormat => 'Falsches ISRC-Format';

  @override
  String get libraryFilterMetadataMissingLabel => 'Label fehlt';

  @override
  String collectionDeletePlaylistsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Playlists',
      one: 'Playlist',
    );
    return 'Lösche $count $_temp0?';
  }

  @override
  String collectionPlaylistsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Playlists',
      one: 'Playlist',
    );
    return '$count $_temp0 gelöscht';
  }

  @override
  String collectionAddedTracksToPlaylist(int count, String playlistName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return '$count $_temp0 zu $playlistName hinzugefügt';
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
      other: 'Titel',
      one: 'Titel',
    );
    return '$count $_temp0 zu $playlistName ($alreadyCount bereits in der Playlist)';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sachen',
      one: 'Sache',
    );
    return '$count $_temp0';
  }

  @override
  String trackReEnrichSuccessWithFailures(
    int successCount,
    int total,
    int failedCount,
  ) {
    return 'Metadaten erfolgreich neu angereichert ($successCount/$total) - fehlgeschlagen: $failedCount';
  }

  @override
  String selectionDeleteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Titel',
      one: 'Titel',
    );
    return 'Lösche $count $_temp0';
  }

  @override
  String queueDownloadSpeedStatus(String speed) {
    return 'Herunterladen - $speed MB/s';
  }

  @override
  String get queueDownloadStarting => 'Starte...';

  @override
  String get a11ySelectTrack => 'Titel auswählen';

  @override
  String get a11yDeselectTrack => 'Titel abwählen';

  @override
  String a11yPlayTrackByArtist(String trackName, String artistName) {
    return 'Spiele $trackName von $artistName';
  }

  @override
  String storeExtensionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Erweiterungen',
      one: 'Erweiterung',
    );
    return '$count $_temp0';
  }

  @override
  String storeRequiresVersion(String version) {
    return 'Benötigt v$version+';
  }

  @override
  String get actionGo => 'Los';

  @override
  String get logIssueSummary => 'Problemübersicht';

  @override
  String logTotalErrors(int count) {
    return 'Gesamte Fehler: $count';
  }

  @override
  String logAffectedDomains(String domains) {
    return 'Betroffen: $domains';
  }

  @override
  String get libraryScanCancelled => 'Scan abgebrochen';

  @override
  String get libraryScanCancelledSubtitle =>
      'Du kannst erneut Scannen, wenn er fertig ist.';

  @override
  String libraryDownloadsHistoryExcluded(int count) {
    return '$count aus dem Download-Verlauf (von der Liste ausgeschlossen)';
  }

  @override
  String get downloadNativeWorker => 'Nativer Download Dienst';

  @override
  String get downloadNativeWorkerSubtitle =>
      'Beta Android Dienst für Downloads von Erweiterungen';

  @override
  String get badgeBeta => 'BETA';

  @override
  String get extensionServiceStatus => 'Dienststatus';

  @override
  String get extensionServiceHealth => 'Service-Gesundheit';

  @override
  String extensionHealthChecksConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Prüfungen',
      one: 'Prüfung',
    );
    return '$count $_temp0 konfiguriert';
  }

  @override
  String get extensionOauthConnectHint =>
      'Tippe auf \"Mit Spotify verbinden\" um dieses Feld auszufüllen.';

  @override
  String extensionLastChecked(String time) {
    return 'Zuletzt geprüft $time';
  }

  @override
  String get extensionRefreshStatus => 'Status aktualisieren';

  @override
  String get extensionCustomUrlHandling => 'Benutzerdefinierte URL-Handling';

  @override
  String get extensionCustomUrlHandlingSubtitle =>
      'Diese Erweiterung kann Links von diesen Seiten benutzen';

  @override
  String get extensionCustomUrlHandlingShareHint =>
      'Teile Links von diesen Seiten mit SpotiFLAC Mobile und diese Erweiterung wird sie verarbeiten.';

  @override
  String extensionSettingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Einstellungen',
      one: 'Einstellung',
    );
    return '$count $_temp0';
  }

  @override
  String get extensionHealthOnline => 'Online';

  @override
  String get extensionHealthDegraded => 'Eingeschränkt';

  @override
  String get extensionHealthOffline => 'Offline';

  @override
  String get extensionHealthNotConfigured => 'Nicht konfiguriert';

  @override
  String get extensionHealthUnknown => 'Unbekannt';

  @override
  String get extensionHealthRequired => 'benötigt';

  @override
  String get extensionSettingNotSet => 'Nicht eingestellt';

  @override
  String get extensionActionFailed => 'Aktion fehlgeschlagen';

  @override
  String get extensionEnterValue => 'Wert eingeben';

  @override
  String get extensionHealthServiceOnline => 'Dienste online';

  @override
  String get extensionHealthServiceDegraded => 'Dienst Eingeschränkt';

  @override
  String get extensionHealthServiceOffline => 'Dienst offline';

  @override
  String get extensionHealthServiceUnknown => 'Dienst-Status unbekannt';

  @override
  String get audioAnalysisStereo => 'Stereo';

  @override
  String get audioAnalysisMono => 'Mono';

  @override
  String trackOpenInService(String serviceName) {
    return 'Öffne in $serviceName';
  }

  @override
  String get trackLyricsEmbeddedSource => 'Eingebettet';

  @override
  String get unknownAlbum => 'Unbekanntes Album';

  @override
  String get unknownArtist => 'Unbekannter Künstler';

  @override
  String get permissionAudio => 'Audio';

  @override
  String get permissionStorage => 'Speicher';

  @override
  String get permissionNotification => 'Benachrichtigung';

  @override
  String get errorInvalidFolderSelected => 'Ungültiger Ordner ausgewählt';

  @override
  String get errorCouldNotKeepFolderAccess =>
      'Konnte nicht auf den ausgewählten Ordner zugreifen';

  @override
  String get storeAnyVersion => 'Alle';

  @override
  String get storeCategoryMetadata => 'Metadaten';

  @override
  String get storeCategoryDownload => 'Herunterladen';

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
}
