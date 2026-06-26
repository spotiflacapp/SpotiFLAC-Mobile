// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => 'Accueil';

  @override
  String get navLibrary => 'Bibliothèque';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get navStore => 'Dépôt';

  @override
  String get homeTitle => 'Accueil';

  @override
  String get homeSubtitle =>
      'Collez une URL prise en charge ou effectuez une recherche par nom';

  @override
  String get homeEmptyTitle => 'Aucun moteur de recherche pour le moment';

  @override
  String get homeEmptySubtitle => 'Installez une extension pour continuer.';

  @override
  String get homeSupports =>
      'Prise en charge : URL de titres, d’albums, de playlists et d’artistes';

  @override
  String get homeRecent => 'Récent';

  @override
  String get historyFilterAll => 'Tous';

  @override
  String get historyFilterAlbums => 'Albums';

  @override
  String get historyFilterSingles => 'Titres';

  @override
  String get historySearchHint => 'Historique de recherche...';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsDownload => 'Télécharger';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsOptions => 'Options';

  @override
  String get settingsExtensions => 'Extensions';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get downloadTitle => 'Télécharger';

  @override
  String get downloadAskQualitySubtitle =>
      'Afficher le sélecteur de qualité pour chaque téléchargement';

  @override
  String get downloadFilenameFormat => 'Nom du fichier';

  @override
  String get downloadSingleFilenameFormat => 'Format de nom de fichier unique';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Modèle de nom de fichier pour les singles et les EP. Utilise les mêmes balises que le format album.';

  @override
  String get downloadFolderOrganization => 'Organisation du dossier';

  @override
  String get appearanceTitle => 'Apparence';

  @override
  String get appearanceThemeSystem => 'Système';

  @override
  String get appearanceThemeLight => 'Clair';

  @override
  String get appearanceThemeDark => 'Sombre';

  @override
  String get appearanceDynamicColor => 'Couleur dynamique';

  @override
  String get appearanceDynamicColorSubtitle =>
      'Utilisez les couleurs de votre fond d\'écran';

  @override
  String get appearanceHistoryView => 'Historique';

  @override
  String get appearanceHistoryViewList => 'Liste';

  @override
  String get appearanceHistoryViewGrid => 'Grille';

  @override
  String get optionsTitle => 'Options';

  @override
  String get optionsPrimaryProvider => 'Fournisseur principal';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Service permettant d\'effectuer une recherche par titre de morceau ou d\'album';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Utilisation de l\'extension : $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Onglet de recherche par défaut';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Choisissez l\'onglet qui s\'ouvre en premier pour les nouveaux résultats de recherche.';

  @override
  String get optionsSwitchBack =>
      'Choose the default search provider to switch back from an extension';

  @override
  String get optionsAutoFallback => 'Récupération automatique';

  @override
  String get optionsAutoFallbackSubtitle =>
      'Essayez d\'autres services si le téléchargement échoue';

  @override
  String get optionsUseExtensionProviders =>
      'Utiliser des fournisseurs d\'extension';

  @override
  String get optionsUseExtensionProvidersOn =>
      'Extension providers are enabled';

  @override
  String get optionsUseExtensionProvidersOff =>
      'Extension providers are required';

  @override
  String get optionsEmbedLyrics => 'Intégrer les paroles';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Enregistrez les paroles synchronisées avec vos morceaux téléchargés';

  @override
  String get optionsMaxQualityCover => 'Pochette de qualité supérieure';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'Télécharger la pochette en haute résolution';

  @override
  String get optionsReplayGain => 'ReplayGain';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Analyser le niveau sonore et intégrer des balises ReplayGain (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Désactivé : aucune balise de normalisation du volume';

  @override
  String get trackReplayGain => 'Rescan ReplayGain';

  @override
  String get trackReplayGainSubtitle =>
      'Analyze loudness and write ReplayGain tags';

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
  String get optionsArtistTagMode => 'Mode « Artiste »';

  @override
  String get optionsArtistTagModeDescription =>
      'Choisissez comment les noms de plusieurs artistes doivent apparaître dans les balises intégrées.';

  @override
  String get optionsArtistTagModeJoined => 'Valeur unique combinée';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Indiquez une seule valeur ARTIST, par exemple « Artiste A, Artiste B », pour garantir une compatibilité maximale avec les lecteurs.';

  @override
  String get optionsArtistTagModeSplitVorbis =>
      'Diviser les balises pour FLAC/Opus';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'Créez une balise « artiste » par artiste pour les fichiers FLAC et Opus ; les fichiers MP3 et M4A restent regroupés.';

  @override
  String get optionsExtensionStore => 'Référentiel d\'extensions';

  @override
  String get optionsExtensionStoreSubtitle =>
      'Afficher l\'onglet « Dépôt » dans le menu de navigation';

  @override
  String get optionsCheckUpdates => 'Vérifier les mises à jour';

  @override
  String get optionsCheckUpdatesSubtitle =>
      'M\'avertir lorsqu\'une nouvelle version est disponible';

  @override
  String get optionsUpdateChannel => 'Chaîne de mise à jour';

  @override
  String get optionsUpdateChannelStable => 'Uniquement les versions stables';

  @override
  String get optionsUpdateChannelPreview =>
      'Accédez aux versions préliminaires';

  @override
  String get optionsUpdateChannelWarning =>
      'La version préliminaire peut contenir des bogues ou des fonctionnalités incomplètes';

  @override
  String get optionsClearHistory => 'Effacer l\'historique des téléchargements';

  @override
  String get optionsClearHistorySubtitle =>
      'Supprimez tous les morceaux téléchargés de l\'historique';

  @override
  String get optionsDetailedLogging => 'Journalisation détaillée';

  @override
  String get optionsDetailedLoggingOn =>
      'Des journaux détaillés sont enregistrés';

  @override
  String get optionsDetailedLoggingOff => 'Activer pour les rapports de bogues';

  @override
  String get optionsSpotifyCredentials => 'Identifiants Spotify';

  @override
  String optionsSpotifyCredentialsConfigured(String clientId) {
    return 'Identifiant client : $clientId...';
  }

  @override
  String get optionsSpotifyCredentialsRequired =>
      'Obligatoire - appuyez pour configurer';

  @override
  String get optionsSpotifyWarning =>
      'Spotify nécessite vos propres identifiants API. Vous pouvez les obtenir gratuitement sur developer.spotify.com';

  @override
  String get optionsSpotifyDeprecationWarning =>
      'La fonction de recherche Spotify sera supprimée le 3 mars 2026 en raison de modifications apportées à l\'API Spotify. Veuillez passer à Deezer.';

  @override
  String get extensionsTitle => 'Extensions';

  @override
  String get extensionsDisabled => 'Désactivée';

  @override
  String extensionsVersion(String version) {
    return 'Version $version';
  }

  @override
  String extensionsAuthor(String author) {
    return 'par $author';
  }

  @override
  String get extensionsUninstall => 'Désinstaller';

  @override
  String get storeTitle => 'Répertoire des extensions';

  @override
  String get storeSearch => 'Recherche d\'extensions...';

  @override
  String get storeInstall => 'Installer';

  @override
  String get storeInstalled => 'Installé';

  @override
  String get storeUpdate => 'Mettre à jour';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get aboutContributors => 'Contributeurs';

  @override
  String get aboutMobileDeveloper => 'Développeur de la version mobile';

  @override
  String get aboutOriginalCreator =>
      'Créateur de la version originale de SpotiFLAC';

  @override
  String get aboutLogoArtist =>
      'Le talentueux artiste qui a créé le magnifique logo de notre application !';

  @override
  String get aboutTranslators => 'Traducteurs';

  @override
  String get aboutSpecialThanks => 'Remerciements particuliers';

  @override
  String get aboutLinks => 'Liens';

  @override
  String get aboutMobileSource => 'Code source pour mobile';

  @override
  String get aboutPCSource => 'Code source pour PC';

  @override
  String get aboutKeepAndroidOpen => 'Garder Android ouvert';

  @override
  String get aboutReportIssue => 'Signaler un problème';

  @override
  String get aboutReportIssueSubtitle =>
      'Signalez tout problème que vous rencontrez';

  @override
  String get aboutFeatureRequest => 'Demande de fonctionnalité';

  @override
  String get aboutFeatureRequestSubtitle =>
      'Proposez de nouvelles fonctionnalités pour l\'application';

  @override
  String get aboutTelegramChannel => 'Chaîne Telegram';

  @override
  String get aboutTelegramChannelSubtitle => 'Annonces et mises à jour';

  @override
  String get aboutTelegramChat => 'Communauté Telegram';

  @override
  String get aboutTelegramChatSubtitle =>
      'Discutez avec d\'autres utilisateurs';

  @override
  String get aboutSocial => 'Réseaux sociaux';

  @override
  String get aboutApp => 'Application';

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
      'Créateur de « I Don\'t Have Spotify » (IDHS). Le résolveur de liens de secours qui sauve la mise !';

  @override
  String get aboutAppDescription =>
      'Recherchez des métadonnées musicales, gérez les extensions et organisez votre bibliothèque.';

  @override
  String get artistAlbums => 'Albums';

  @override
  String get artistSingles => 'Singles & EPs';

  @override
  String get artistCompilations => 'Compilations';

  @override
  String get artistPopular => 'Populaire';

  @override
  String artistMonthlyListeners(String count) {
    return '$count auditeurs mensuels';
  }

  @override
  String get trackMetadataService => 'Service';

  @override
  String get trackMetadataPlay => 'Lire';

  @override
  String get trackMetadataShare => 'Partager';

  @override
  String get trackMetadataDelete => 'Supprimer';

  @override
  String get setupGrantPermission => 'Accorder l\'autorisation';

  @override
  String get setupSkip => 'Ignorer pour le moment';

  @override
  String get setupStorageAccessRequired => 'Accès au stockage requis';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Depuis Android 11, l\'autorisation « Accès à tous les fichiers » est requise pour enregistrer des fichiers dans le dossier de téléchargement de votre choix.';

  @override
  String get setupOpenSettings => 'Ouvrir les paramètres';

  @override
  String get setupPermissionDeniedMessage =>
      'Autorisation refusée. Veuillez accorder toutes les autorisations pour continuer.';

  @override
  String setupPermissionRequired(String permissionType) {
    return 'Autorisation $permissionType requise';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return 'L\'autorisation $permissionType est requise pour profiter pleinement de l\'application. Vous pourrez modifier ce paramètre ultérieurement dans les Paramètres.';
  }

  @override
  String get setupUseDefaultFolder => 'Utiliser le dossier par défaut ?';

  @override
  String get setupNoFolderSelected =>
      'Aucun dossier n\'est sélectionné. Souhaitez-vous utiliser le dossier Musique par défaut ?';

  @override
  String get setupUseDefault => 'Utiliser les paramètres par défaut';

  @override
  String get setupDownloadLocationTitle => 'Emplacement de téléchargement';

  @override
  String get setupDownloadLocationIosMessage =>
      'Sous iOS, les fichiers téléchargés sont enregistrés dans le dossier « Documents » de l\'application. Vous pouvez y accéder via l\'application Fichiers.';

  @override
  String get setupAppDocumentsFolder =>
      'Dossier « Documents » de l\'application';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Recommandé - accessible via l\'application Fichiers';

  @override
  String get setupChooseFromFiles => 'Sélectionnez un fichier';

  @override
  String get setupChooseFromFilesSubtitle =>
      'Sélectionnez iCloud ou un autre emplacement';

  @override
  String get setupIosEmptyFolderWarning =>
      'Limitation iOS : les dossiers vides ne peuvent pas être sélectionnés. Choisissez un dossier contenant au moins un fichier.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive n\'est pas pris en charge. Veuillez utiliser le dossier « Documents » de l\'application.';

  @override
  String get setupDownloadInFlac =>
      'Télécharger des morceaux Spotify au format FLAC';

  @override
  String get setupStorageGranted => 'Autorisation de stockage accordée !';

  @override
  String get setupStorageRequired => 'Autorisation de stockage requise';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC a besoin d\'une autorisation d\'accès au stockage pour enregistrer vos fichiers musicaux téléchargés.';

  @override
  String get setupNotificationGranted =>
      'Autorisation de notification accordée !';

  @override
  String get setupNotificationEnable => 'Activer les notifications';

  @override
  String get setupFolderChoose => 'Choisissez le dossier de téléchargement';

  @override
  String get setupFolderDescription =>
      'Sélectionnez un dossier dans lequel votre musique téléchargée sera enregistrée.';

  @override
  String get setupSelectFolder => 'Sélectionner un dossier';

  @override
  String get setupEnableNotifications => 'Activer les notifications';

  @override
  String get setupNotificationBackgroundDescription =>
      'Recevez des notifications sur la progression et la fin du téléchargement. Cela vous permet de suivre les téléchargements lorsque l\'application est en arrière-plan.';

  @override
  String get setupSkipForNow => 'Ignorer pour le moment';

  @override
  String get setupNext => 'Suivant';

  @override
  String get setupGetStarted => 'Démarrer';

  @override
  String get setupAllowAccessToManageFiles =>
      'Veuillez cocher la case « Autoriser l\'accès pour gérer tous les fichiers » sur l\'écran suivant.';

  @override
  String get setupLanguageTitle => 'Choisir la langue';

  @override
  String get setupLanguageDescription =>
      'Sélectionnez la langue de votre choix pour l\'application. Vous pourrez la modifier ultérieurement dans les Paramètres.';

  @override
  String get setupLanguageSystemDefault => 'Paramètres par défaut du système';

  @override
  String get dialogCancel => 'Annuler';

  @override
  String get dialogSave => 'Sauvegarder';

  @override
  String get dialogDelete => 'Supprimer';

  @override
  String get dialogRetry => 'Réessayer';

  @override
  String get dialogClear => 'Effacer';

  @override
  String get dialogDone => 'C\'est fait';

  @override
  String get dialogImport => 'Importer';

  @override
  String get dialogDownload => 'Télécharger';

  @override
  String get dialogDiscard => 'Ignorer';

  @override
  String get dialogRemove => 'Supprimer';

  @override
  String get dialogUninstall => 'Désinstaller';

  @override
  String get dialogDiscardChanges => 'Ignorer les modifications ?';

  @override
  String get dialogUnsavedChanges =>
      'Vous avez des modifications non enregistrées. Voulez-vous les ignorer ?';

  @override
  String get dialogClearAll => 'Tout effacer';

  @override
  String get dialogRemoveExtension => 'Supprimer l\'extension';

  @override
  String get dialogRemoveExtensionMessage =>
      'Êtes-vous sûr de vouloir supprimer cette extension ? Cette action ne peut pas être annulée.';

  @override
  String get dialogUninstallExtension => 'Supprimer l\'extension ?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return 'Êtes-vous sûr de vouloir supprimer $extensionName ?';
  }

  @override
  String get dialogClearHistoryTitle => 'Effacer l\'historique';

  @override
  String get dialogClearHistoryMessage =>
      'Êtes-vous sûr de vouloir effacer tout l\'historique des téléchargements ? Cette action ne peut pas être annulée.';

  @override
  String get dialogDeleteSelectedTitle => 'Supprimer la sélection';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Supprimer $count $_temp0 de l\'historique ?\n\nCela supprimera également les fichiers du stockage.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Importer une playlist';

  @override
  String dialogImportPlaylistMessage(int count) {
    return '$count pistes ont été trouvées dans le fichier CSV. Voulez-vous les ajouter à la file d\'attente de téléchargement ?';
  }

  @override
  String csvImportTracks(int count) {
    return '$count pistes issues d\'un fichier CSV';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return 'Ajout de « $trackName » à la file d\'attente';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return '$count titres ont été ajoutés à la file d\'attente';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '« $trackName » a déjà été téléchargé';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '« $trackName » existe déjà dans votre bibliothèque';
  }

  @override
  String get snackbarHistoryCleared => 'Historique effacé';

  @override
  String get snackbarCredentialsSaved => 'Identifiants enregistrés';

  @override
  String get snackbarCredentialsCleared => 'Identifiants validés';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Supprimé $count $_temp0';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'Impossible d\'ouvrir le fichier : $error';
  }

  @override
  String get snackbarFillAllFields => 'Veuillez remplir tous les champs';

  @override
  String get snackbarViewQueue => 'Afficher la file d\'attente';

  @override
  String snackbarUrlCopied(String platform) {
    return 'L\'URL de $platform a été copiée dans le presse-papiers';
  }

  @override
  String get snackbarFileNotFound => 'Fichier introuvable';

  @override
  String get snackbarSelectExtFile =>
      'Veuillez sélectionner un fichier .spotiflac-ext';

  @override
  String get snackbarProviderPrioritySaved =>
      'Priorité du fournisseur enregistrée';

  @override
  String get snackbarMetadataProviderSaved =>
      'Priorité du fournisseur de métadonnées enregistrée';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '$extensionName est installée.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName a été mis à jour.';
  }

  @override
  String get snackbarFailedToInstall =>
      'Échec de l\'installation de l\'extension';

  @override
  String get snackbarFailedToUpdate =>
      'Échec de la mise à jour de l\'extension';

  @override
  String get errorRateLimited => 'Débit limité';

  @override
  String get errorRateLimitedMessage =>
      'Trop de requêtes. Veuillez patienter quelques instants avant de relancer la recherche.';

  @override
  String get errorNoTracksFound => 'Aucun titre trouvé';

  @override
  String get searchEmptyResultSubtitle => 'Essayez un autre mot-clé';

  @override
  String get errorUrlNotRecognized => 'Lien non reconnu';

  @override
  String get errorUrlNotRecognizedMessage =>
      'Ce lien n\'est pas pris en charge. Vérifiez que l\'URL est correcte et qu\'une extension compatible est installée.';

  @override
  String get errorUrlFetchFailed =>
      'Impossible de charger le contenu de ce lien. Veuillez réessayer.';

  @override
  String errorMissingExtensionSource(String item) {
    return 'Impossible de charger $item : source de l\'extension manquante';
  }

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resumer';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionSelectAll => 'Tout sélectionner';

  @override
  String get actionDeselect => 'Désélectionner';

  @override
  String get actionRemoveCredentials => 'Supprimer les identifiants';

  @override
  String get actionSaveCredentials => 'Enregistrer les identifiants';

  @override
  String selectionSelected(int count) {
    return '$count sélectionnés';
  }

  @override
  String get selectionAllSelected => 'Toutes les pistes sélectionnées';

  @override
  String get selectionSelectToDelete => 'Sélectionnez les titres à supprimer';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Récupération des métadonnées... $current/$total';
  }

  @override
  String get progressReadingCsv => 'Lecture du fichier CSV...';

  @override
  String get searchSongs => 'Titres';

  @override
  String get searchArtists => 'Artistes';

  @override
  String get searchAlbums => 'Albums';

  @override
  String get searchPlaylists => 'Playlists';

  @override
  String get searchSortTitle => 'Trier les résultats';

  @override
  String get searchSortDefault => 'Par défaut';

  @override
  String get searchSortTitleAZ => 'Titre (A-Z)';

  @override
  String get searchSortTitleZA => 'Titre (Z-A)';

  @override
  String get searchSortArtistAZ => 'Artiste (A-Z)';

  @override
  String get searchSortArtistZA => 'Artiste (Z-A)';

  @override
  String get searchSortDurationShort => 'Durée (la plus courte)';

  @override
  String get searchSortDurationLong => 'Durée (la plus longue)';

  @override
  String get searchSortDateOldest => 'Date de sortie (la plus ancienne)';

  @override
  String get searchSortDateNewest => 'Date de sortie (la plus récente)';

  @override
  String get tooltipPlay => 'Lecture';

  @override
  String get filenameFormat => 'Format des noms de fichiers';

  @override
  String get filenameShowAdvancedTags => 'Afficher les balises avancées';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Activer les balises de formatage pour le remplissage des pistes et les formats de date';

  @override
  String get folderOrganizationNone => 'Aucune organisation';

  @override
  String get folderOrganizationByPlaylist => 'Par playlist';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Un dossier distinct pour chaque playlist';

  @override
  String get folderOrganizationByArtist => 'Par artiste';

  @override
  String get folderOrganizationByAlbum => 'Par album';

  @override
  String get folderOrganizationByArtistAlbum => 'Artiste/Album';

  @override
  String get folderOrganizationDescription =>
      'Classer les fichiers téléchargés dans des dossiers';

  @override
  String get folderOrganizationNoneSubtitle =>
      'Tous les fichiers du dossier « Téléchargements »';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Un dossier distinct pour chaque artiste';

  @override
  String get folderOrganizationByAlbumSubtitle =>
      'Un dossier distinct pour chaque album';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Dossiers imbriqués pour les artistes et les albums';

  @override
  String get updateAvailable => 'Mise à jour disponible';

  @override
  String get updateLater => 'Plus tard';

  @override
  String get updateStartingDownload => 'Début du téléchargement...';

  @override
  String get updateDownloadFailed => 'Échec du téléchargement';

  @override
  String get updateFailedMessage => 'Échec du téléchargement de la mise à jour';

  @override
  String get updateNewVersionReady => 'Une nouvelle version est disponible';

  @override
  String get updateCurrent => 'Actuel';

  @override
  String get updateNew => 'Nouveau';

  @override
  String get updateDownloading => 'Téléchargement en cours...';

  @override
  String get updateWhatsNew => 'Quoi de neuf ?';

  @override
  String get updateDownloadInstall => 'Télécharger & Installer';

  @override
  String get updateDontRemind => 'Ne plus me le rappeler';

  @override
  String get providerPriorityTitle => 'Priorité accordée aux prestataires';

  @override
  String get providerPriorityDescription =>
      'Faites glisser pour réorganiser les fournisseurs de téléchargement. L\'application testera les fournisseurs dans l\'ordre indiqué, de haut en bas, lors du téléchargement des morceaux.';

  @override
  String get providerPriorityInfo =>
      'Si un morceau n\'est pas disponible chez le premier fournisseur, l\'application essaiera automatiquement le suivant.';

  @override
  String get providerPriorityFallbackExtensionsTitle =>
      'Solution de secours pour les extensions';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Sélectionnez les extensions de téléchargement installées qui peuvent être utilisées lors du basculement automatique.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Seules les extensions activées disposant de la fonctionnalité « fournisseur de téléchargement » sont répertoriées ici.';

  @override
  String get providerBuiltIn => 'Legacy';

  @override
  String get providerExtension => 'Extension';

  @override
  String get metadataProviderPriorityTitle => 'Priorité des métadonnées';

  @override
  String get metadataProviderPriorityDescription =>
      'Faites glisser pour réorganiser les fournisseurs de métadonnées. L\'application testera les fournisseurs dans l\'ordre de haut en bas lors de la recherche de morceaux et de la récupération des métadonnées.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer n\'impose aucune limite de débit et est recommandé comme service principal. Spotify peut limiter le débit après un certain nombre de requêtes.';

  @override
  String get metadataNoRateLimits => 'Pas de limite de débit';

  @override
  String get metadataMayRateLimit => 'Limite de taux de métadonnées';

  @override
  String get logTitle => 'Journaux';

  @override
  String get logCopied => 'Journaux copiés dans le presse-papiers';

  @override
  String get logSearchHint => 'Recherche dans les journaux...';

  @override
  String get logFilterLevel => 'Niveau';

  @override
  String get logFilterSection => 'Filtre';

  @override
  String get logShareLogs => 'Partager les journaux';

  @override
  String get logClearLogs => 'Effacer les journaux';

  @override
  String get logClearLogsTitle => 'Effacer les journaux';

  @override
  String get logClearLogsMessage =>
      'Êtes-vous sûr de vouloir effacer tous les journaux ?';

  @override
  String get logFilterBySeverity =>
      'Filtrer les journaux par niveau de gravité';

  @override
  String get logNoLogsYet => 'Pas encore de journal';

  @override
  String get logNoLogsYetSubtitle =>
      'Les journaux s\'afficheront ici au fur et à mesure que vous utiliserez l\'application';

  @override
  String logEntriesFiltered(int count) {
    return 'Entrées ($count résultats filtrés)';
  }

  @override
  String logEntries(int count) {
    return 'Entrées ($count)';
  }

  @override
  String get credentialsTitle => 'Identifiants Spotify';

  @override
  String get credentialsDescription =>
      'Saisissez votre identifiant client et votre clé secrète pour utiliser votre propre quota d\'application Spotify.';

  @override
  String get credentialsClientId => 'Identifiant client';

  @override
  String get credentialsClientIdHint => 'Coller l\'identifiant client';

  @override
  String get credentialsClientSecret => 'Clé secrète du client';

  @override
  String get credentialsClientSecretHint => 'Coller la clé secrète du client';

  @override
  String get channelStable => 'Stable';

  @override
  String get channelPreview => 'Aperçu';

  @override
  String get sectionSearchSource => 'Rechercher dans la source';

  @override
  String get sectionDownload => 'Télécharger';

  @override
  String get sectionPerformance => 'Performances';

  @override
  String get sectionApp => 'Application';

  @override
  String get sectionData => 'Données';

  @override
  String get sectionDebug => 'Débogage';

  @override
  String get sectionService => 'Service';

  @override
  String get sectionAudioQuality => 'Qualité audio';

  @override
  String get sectionFileSettings => 'Paramètres du fichier';

  @override
  String get sectionLyrics => 'Paroles';

  @override
  String get lyricsMode => 'Mode Paroles';

  @override
  String get lyricsModeDescription =>
      'Choisissez comment les paroles sont enregistrées avec vos téléchargements';

  @override
  String get lyricsModeEmbed => 'Intégrer dans un fichier';

  @override
  String get lyricsModeEmbedSubtitle =>
      'Paroles enregistrées dans les métadonnées FLAC';

  @override
  String get lyricsModeExternal => 'Fichier .lrc externe';

  @override
  String get lyricsModeExternalSubtitle =>
      'Fichier .lrc distinct pour les lecteurs tels que Samsung Music';

  @override
  String get lyricsModeBoth => 'Les deux';

  @override
  String get lyricsModeBothSubtitle =>
      'Intégrer et enregistrer le fichier .lrc';

  @override
  String get sectionColor => 'Couleur';

  @override
  String get sectionTheme => 'Thème';

  @override
  String get sectionLayout => 'Mise en page';

  @override
  String get sectionLanguage => 'Langue';

  @override
  String get appearanceLanguage => 'Langue de l\'application';

  @override
  String get settingsAppearanceSubtitle => 'Thème, couleurs, affichage';

  @override
  String get settingsDownloadSubtitle =>
      'Service, qualité, solution de secours';

  @override
  String get settingsOptionsSubtitle =>
      'Fichier de secours, métadonnées, paroles, pochette';

  @override
  String get settingsExtensionsSubtitle =>
      'Gérez les fournisseurs de téléchargement';

  @override
  String get settingsLogsSubtitle =>
      'Consulter les journaux de l\'application pour le débogage';

  @override
  String get loadingSharedLink => 'Chargement du lien partagé...';

  @override
  String get pressBackAgainToExit =>
      'Appuyez de nouveau sur retour pour quitter';

  @override
  String downloadAllCount(int count) {
    return 'Tout télécharger ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '1 titre',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Copier le chemin d\'accès au fichier';

  @override
  String get trackRemoveFromDevice => 'Supprimer de l\'appareil';

  @override
  String get trackLoadLyrics => 'Charger les paroles';

  @override
  String get trackMetadata => 'Métadonnées';

  @override
  String get trackFileInfo => 'Informations sur le fichier';

  @override
  String get trackLyrics => 'Paroles';

  @override
  String get trackFileNotFound => 'Fichier introuvable';

  @override
  String get trackOpenInDeezer => 'Ouvrir dans Deezer';

  @override
  String get trackOpenInSpotify => 'Ouvrir dans Spotify';

  @override
  String get trackTrackName => 'Nom de la piste';

  @override
  String get trackArtist => 'Artiste';

  @override
  String get trackAlbumArtist => 'Artiste de l\'album';

  @override
  String get trackAlbum => 'Album';

  @override
  String get trackTrackNumber => 'Numéro de piste';

  @override
  String get trackDiscNumber => 'Numéro de disque';

  @override
  String get trackDuration => 'Durée';

  @override
  String get trackAudioQuality => 'Qualité audio';

  @override
  String get trackReleaseDate => 'Date de sortie';

  @override
  String get trackGenre => 'Genre';

  @override
  String get trackLabel => 'Label';

  @override
  String get trackCopyright => 'Droits d\'auteur';

  @override
  String get trackDownloaded => 'Téléchargé';

  @override
  String get trackCopyLyrics => 'Copier les paroles';

  @override
  String trackLyricsSource(String source) {
    return 'Source : $source';
  }

  @override
  String get trackLyricsNotAvailable =>
      'Les paroles de ce morceau ne sont pas disponibles';

  @override
  String get trackLyricsNotInFile =>
      'Aucune parole n\'a été trouvée dans ce fichier';

  @override
  String get trackFetchOnlineLyrics => 'Télécharger depuis Internet';

  @override
  String get trackLyricsTimeout =>
      'La requête a expiré. Veuillez réessayer plus tard.';

  @override
  String get trackLyricsLoadFailed => 'Impossible de charger les paroles';

  @override
  String get trackEmbedLyrics => 'Intégrer les paroles';

  @override
  String get trackLyricsEmbedded => 'Les paroles ont été intégrées avec succès';

  @override
  String get trackInstrumental => 'Morceau instrumental';

  @override
  String get trackCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get trackDeleteConfirmTitle => 'Supprimer de l\'appareil ?';

  @override
  String get trackDeleteConfirmMessage =>
      'Cela supprimera définitivement le fichier téléchargé et l\'effacera de votre historique.';

  @override
  String get dateToday => 'Aujourd\'hui';

  @override
  String get dateYesterday => 'Hier';

  @override
  String dateDaysAgo(int count) {
    return 'Il y a $count jours';
  }

  @override
  String dateWeeksAgo(int count) {
    return 'Il y a $count semaines';
  }

  @override
  String dateMonthsAgo(int count) {
    return 'Il y a $count mois';
  }

  @override
  String get storeFilterAll => 'Tout';

  @override
  String get storeFilterMetadata => 'Métadonnées';

  @override
  String get storeFilterDownload => 'Télécharger';

  @override
  String get storeFilterUtility => 'Utilitaire';

  @override
  String get storeFilterLyrics => 'Paroles';

  @override
  String get storeFilterIntegration => 'Intégration';

  @override
  String get storeClearFilters => 'Effacer les filtres';

  @override
  String get storeAddRepoTitle => 'Ajouter un dépôt d\'extensions';

  @override
  String get storeAddRepoDescription =>
      'Saisissez l\'URL d\'un dépôt GitHub contenant un fichier registry.json pour parcourir et installer des extensions.';

  @override
  String get storeRepoUrlLabel => 'URL du dépôt';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeRepoUrlHelper =>
      'par exemple : https://github.com/user/extensions-repo';

  @override
  String get storeAddRepoButton => 'Ajouter un dépôt';

  @override
  String get storeChangeRepoTooltip => 'Changer de dépôt';

  @override
  String get storeRepoDialogTitle => 'Répertoire des extensions';

  @override
  String get storeRepoDialogCurrent => 'Dépôt actuel :';

  @override
  String get storeNewRepoUrlLabel => 'Nouvelle URL du dépôt';

  @override
  String get storeLoadError => 'Échec du chargement du dépôt';

  @override
  String get storeEmptyNoExtensions => 'Aucune extension disponible';

  @override
  String get storeEmptyNoResults => 'Aucune extension trouvée';

  @override
  String get extensionDefaultProvider => 'Default Search';

  @override
  String get extensionDefaultProviderSubtitle =>
      'Use the default metadata search';

  @override
  String get extensionAuthor => 'Auteur';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => 'Erreur';

  @override
  String get extensionCapabilities => 'Fonctionnalités';

  @override
  String get extensionMetadataProvider => 'Fournisseur de métadonnées';

  @override
  String get extensionDownloadProvider => 'Fournisseur de téléchargement';

  @override
  String get extensionLyricsProvider => 'Fournisseur de paroles';

  @override
  String get extensionUrlHandler => 'Gestionnaire d\'URL';

  @override
  String get extensionQualityOptions => 'Options de qualité';

  @override
  String get extensionPostProcessingHooks => 'Crochets de post-traitement';

  @override
  String get extensionPermissions => 'Autorisations';

  @override
  String get extensionSettings => 'Paramètres';

  @override
  String get extensionRemoveButton => 'Supprimer l\'extension';

  @override
  String get extensionUpdated => 'Mis à jour';

  @override
  String get extensionMinAppVersion => 'Version minimale de l\'application';

  @override
  String get extensionCustomTrackMatching =>
      'Correspondance personnalisée des pistes';

  @override
  String get extensionPostProcessing => 'Post-traitement';

  @override
  String extensionHooksAvailable(int count) {
    return '$count crochet(s) disponibles';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count motif(s)';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Stratégie : $strategy';
  }

  @override
  String get extensionsProviderPrioritySection =>
      'Priorité accordée aux prestataires';

  @override
  String get extensionsInstalledSection => 'Extensions installées';

  @override
  String get extensionsNoExtensions => 'Aucune extension installée';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Installez les fichiers .spotiflac-ext pour ajouter de nouveaux fournisseurs';

  @override
  String get extensionsInstallButton => 'Installer l\'extension';

  @override
  String get extensionsInfoTip =>
      'Les extensions permettent d\'ajouter de nouvelles métadonnées et de nouveaux fournisseurs de téléchargement. N\'installez que des extensions provenant de sources fiables.';

  @override
  String get extensionsInstalledSuccess =>
      'L\'extension a été installée avec succès';

  @override
  String extensionsInstalledCount(int count) {
    return '$count extensions ont été installées avec succès';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return '$installed extensions sur $attempted';
  }

  @override
  String get extensionsDownloadPriority => 'Priorité de téléchargement';

  @override
  String get extensionsDownloadPrioritySubtitle =>
      'Définissez l\'ordre des services de téléchargement';

  @override
  String get extensionsFallbackTitle => 'Extensions de secours';

  @override
  String get extensionsFallbackSubtitle =>
      'Choisissez les extensions de téléchargement installées qui peuvent servir de solution de secours';

  @override
  String get extensionsNoDownloadProvider =>
      'Aucune extension avec le fournisseur de téléchargement';

  @override
  String get extensionsMetadataPriority => 'Priorité des métadonnées';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Définissez l\'ordre des sources de recherche et de métadonnées';

  @override
  String get extensionsNoMetadataProvider =>
      'Aucune extension avec fournisseur de métadonnées';

  @override
  String get extensionsSearchProvider => 'Moteur de recherche';

  @override
  String get extensionsNoCustomSearch =>
      'Aucune extension avec recherche personnalisée';

  @override
  String get extensionsSearchProviderDescription =>
      'Choisissez le service que vous souhaitez utiliser pour rechercher des morceaux';

  @override
  String get extensionsCustomSearch => 'Recherche personnalisée';

  @override
  String get extensionsErrorLoading =>
      'Erreur lors du chargement de l\'extension';

  @override
  String get qualityFlacLossless => 'FLAC sans perte';

  @override
  String get qualityFlacLosslessSubtitle => '16 bits / 44,1 kHz';

  @override
  String get qualityHiResFlac => 'FLAC haute résolution';

  @override
  String get qualityHiResFlacSubtitle => '24 bits / jusqu\'à 96 kHz';

  @override
  String get qualityHiResFlacMax => 'FLAC haute résolution Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24 bits / jusqu\'à 192 kHz';

  @override
  String get downloadLossy320 => 'Compression avec perte à 320 kbps';

  @override
  String get downloadLossyFormat => 'Format avec perte';

  @override
  String get downloadLossy320Format => 'Format avec perte à 320 kbps';

  @override
  String get downloadLossy320FormatDesc =>
      'Choose the output format for 320kbps lossy downloads. The original stream will be converted to your selected format when needed.';

  @override
  String get downloadLossyMp3 => 'MP3 320 kbps';

  @override
  String get downloadLossyMp3Subtitle =>
      'Compatibilité optimale, environ 10 Mo par piste';

  @override
  String get downloadLossyAac => 'AAC/M4A 320 kbps';

  @override
  String get downloadLossyAacSubtitle =>
      'Compatibilité optimale avec les appareils mobiles, format M4A';

  @override
  String get downloadLossyOpus256 => 'Opus 256 kbps';

  @override
  String get downloadLossyOpus256Subtitle =>
      'Opus en qualité optimale, environ 8 Mo par piste';

  @override
  String get downloadLossyOpus128 => 'Opus 128 kbps';

  @override
  String get downloadLossyOpus128Subtitle =>
      'Taille minimale : environ 4 Mo par piste';

  @override
  String get qualityNote =>
      'La qualité réelle dépend de la disponibilité des pistes sur le service';

  @override
  String get downloadAskBeforeDownload => 'Demander avant de télécharger';

  @override
  String get downloadDirectory => 'Répertoire de téléchargement';

  @override
  String get downloadSeparateSinglesFolder =>
      'Dossier dédié aux titres individuels';

  @override
  String get downloadAlbumFolderStructure => 'Structure du dossier de l\'album';

  @override
  String get downloadUseAlbumArtistForFolders =>
      'Utilisez l\'artiste de l\'album pour les dossiers';

  @override
  String get downloadUsePrimaryArtistOnly =>
      'Artiste principal uniquement pour les dossiers';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Les noms des artistes mis en avant ont été supprimés du nom du dossier (par exemple : Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Nom complet de l\'artiste utilisé pour le nom du dossier';

  @override
  String get downloadSelectQuality => 'Sélectionner la qualité';

  @override
  String get downloadFrom => 'Télécharger depuis';

  @override
  String get appearanceAmoledDark => 'Noir Amoled';

  @override
  String get appearanceAmoledDarkSubtitle => 'Fond noir pur';

  @override
  String get queueClearAll => 'Tout effacer';

  @override
  String get queueClearAllMessage =>
      'Êtes-vous sûr de vouloir supprimer tous les fichiers téléchargés ?';

  @override
  String get settingsAutoExportFailed =>
      'Échec de l\'exportation automatique des téléchargements';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Enregistrez automatiquement les téléchargements ayant échoué dans un fichier TXT';

  @override
  String get settingsDownloadNetwork => 'Réseau de téléchargement';

  @override
  String get settingsDownloadNetworkAny => 'Wi-Fi + données mobiles';

  @override
  String get settingsDownloadNetworkWifiOnly => 'Wi-Fi uniquement';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'Choisissez le réseau à utiliser pour les téléchargements. Si vous sélectionnez « Wi-Fi uniquement », les téléchargements seront interrompus lorsque vous utilisez les données mobiles.';

  @override
  String get albumFolderArtistAlbum => 'Artiste / Album';

  @override
  String get albumFolderArtistAlbumSubtitle =>
      'Albums/Nom de l\'artiste/Titre de l\'album/';

  @override
  String get albumFolderArtistYearAlbum => 'Artiste / [Année] Album';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Albums/Nom de l\'artiste/[2005] Nom de l\'album/';

  @override
  String get albumFolderAlbumOnly => 'Album uniquement';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Albums/Nom de l\'album/';

  @override
  String get albumFolderYearAlbum => '[Année] Album';

  @override
  String get albumFolderYearAlbumSubtitle => 'Albums/[2005] Titre de l\'album/';

  @override
  String get albumFolderArtistAlbumSingles => 'Artiste / Album + Singles';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Artiste/Album/ et Artiste/Singles/';

  @override
  String get albumFolderArtistAlbumFlat => 'Artiste / Album (singles)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Artiste/Album/ et Artiste/titre.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Supprimer la sélection';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistes',
      one: 'piste',
    );
    return 'Souhaitez-vous supprimer $count $_temp0 de cet album ?\n\nCela supprimera également les fichiers de l\'espace de stockage.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count sélectionnés';
  }

  @override
  String get downloadedAlbumAllSelected => 'Tous les titres sélectionnés';

  @override
  String get downloadedAlbumTapToSelect =>
      'Appuyez sur les titres pour les sélectionner';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistes',
      one: 'piste',
    );
    return 'Supprimer $count $_temp0';
  }

  @override
  String get downloadedAlbumSelectToDelete =>
      'Sélectionnez les pistes à supprimer';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Disque $discNumber';
  }

  @override
  String get recentTypeArtist => 'Artiste';

  @override
  String get recentTypeAlbum => 'Album';

  @override
  String get recentTypeSong => 'Titre';

  @override
  String get recentTypePlaylist => 'Playlist';

  @override
  String get recentEmpty => 'Aucun élément récent pour le moment';

  @override
  String get recentShowAllDownloads => 'Afficher tous les téléchargements';

  @override
  String recentPlaylistInfo(String name) {
    return 'Playlist : $name';
  }

  @override
  String get discographyDownload => 'Télécharger la discographie';

  @override
  String get discographyDownloadAll => 'Tout télécharger';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$count titres issus de $albumCount albums';
  }

  @override
  String get discographyAlbumsOnly => 'Albums uniquement';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$count titres issus de $albumCount albums';
  }

  @override
  String get discographySinglesOnly => 'Uniquement les singles et les EP';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$count titres issus de $albumCount singles';
  }

  @override
  String get discographySelectAlbums => 'Sélectionner des albums...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Choisissez des albums ou des titres spécifiques';

  @override
  String get discographyFetchingTracks => 'Chargement des pistes...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return 'Récupération de $current sur $total...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count sélectionnés';
  }

  @override
  String get discographyDownloadSelected => 'Télécharger la sélection';

  @override
  String discographyAddedToQueue(int count) {
    return '$count titres ont été ajoutés à la file d\'attente';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added ajouté, $skipped déjà téléchargé';
  }

  @override
  String get discographyNoAlbums => 'Aucun album disponible';

  @override
  String get discographyFailedToFetch =>
      'Impossible de récupérer certains albums';

  @override
  String get sectionStorageAccess => 'Accès au stockage';

  @override
  String get allFilesAccess => 'Accès à tous les fichiers';

  @override
  String get allFilesAccessEnabledSubtitle =>
      'Peut écrire dans n\'importe quel dossier';

  @override
  String get allFilesAccessDisabledSubtitle =>
      'Réservé aux dossiers multimédias uniquement';

  @override
  String get allFilesAccessDescription =>
      'Activez cette option si vous rencontrez des erreurs d\'écriture lors de l\'enregistrement dans des dossiers personnalisés. À partir d\'Android 13, l\'accès à certains répertoires est restreint par défaut.';

  @override
  String get allFilesAccessDeniedMessage =>
      'L\'autorisation a été refusée. Veuillez activer manuellement l\'option « Accès à tous les fichiers » dans les paramètres système.';

  @override
  String get allFilesAccessDisabledMessage =>
      'L\'accès à tous les fichiers est désactivé. L\'application disposera d\'un accès limité au stockage.';

  @override
  String get settingsLocalLibrary => 'Bibliothèque locale';

  @override
  String get settingsLocalLibrarySubtitle =>
      'Analysez la musique et détectez les doublons';

  @override
  String get settingsCache => 'Stockage & Cache';

  @override
  String get settingsCacheSubtitle => 'Afficher la taille et vider le cache';

  @override
  String get libraryTitle => 'Bibliothèque locale';

  @override
  String get libraryScanSettings => 'Paramètres de numérisation';

  @override
  String get libraryEnableLocalLibrary => 'Activer la bibliothèque locale';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Analysez et gérez votre bibliothèque musicale';

  @override
  String get libraryFolder => 'Dossier de bibliothèque';

  @override
  String get libraryFolderHint => 'Appuyez pour sélectionner un dossier';

  @override
  String get libraryShowDuplicateIndicator =>
      'Afficher l\'indicateur de doublons';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Afficher lors de la recherche de pistes existantes';

  @override
  String get libraryAutoScan => 'Analyse automatique';

  @override
  String get libraryAutoScanSubtitle =>
      'Analysez automatiquement votre bibliothèque à la recherche de nouveaux fichiers';

  @override
  String get libraryAutoScanOff => 'Désactivée';

  @override
  String get libraryAutoScanOnOpen => 'À chaque ouverture de l\'application';

  @override
  String get libraryAutoScanDaily => 'Tous les jours';

  @override
  String get libraryAutoScanWeekly => 'Hebdomadaire';

  @override
  String get libraryActions => 'Actions';

  @override
  String get libraryScan => 'Analyse de la bibliothèque';

  @override
  String get libraryScanSubtitle => 'Recherchez des fichiers audio';

  @override
  String get libraryScanSelectFolderFirst => 'Sélectionnez d\'abord un dossier';

  @override
  String get libraryCleanupMissingFiles => 'Nettoyage des fichiers manquants';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Supprimez les entrées correspondant aux fichiers qui n\'existent plus';

  @override
  String get libraryClear => 'Vider la bibliothèque';

  @override
  String get libraryClearSubtitle => 'Supprimez tous les titres numérisés';

  @override
  String get libraryClearConfirmTitle => 'Vider la bibliothèque';

  @override
  String get libraryClearConfirmMessage =>
      'Cette opération supprimera toutes les pistes numérisées de votre bibliothèque. Vos fichiers musicaux ne seront pas supprimés.';

  @override
  String get libraryAbout => 'À propos de la bibliothèque locale';

  @override
  String get libraryAboutDescription =>
      'Analyse votre bibliothèque musicale existante pour détecter les doublons lors du téléchargement. Prend en charge les formats FLAC, M4A, MP3, Opus et OGG. Les métadonnées sont extraites des balises des fichiers lorsqu\'elles sont disponibles.';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pistes',
      one: 'piste',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return 'Dernière analyse : $time';
  }

  @override
  String get libraryLastScannedNever => 'Jamais';

  @override
  String get libraryScanning => 'En cours d\'analyse...';

  @override
  String get libraryScanFinalizing => 'Finalisation de la bibliothèque...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$progress % des $total fichiers';
  }

  @override
  String get libraryInLibrary => 'Dans la bibliothèque';

  @override
  String libraryRemovedMissingFiles(int count) {
    return '$count fichiers manquants ont été supprimés de la bibliothèque';
  }

  @override
  String get libraryCleared => 'Bibliothèque vidée';

  @override
  String get libraryStorageAccessRequired => 'Accès au stockage requis';

  @override
  String get libraryStorageAccessMessage =>
      'SpotiFLAC a besoin d\'un accès au stockage pour analyser votre bibliothèque musicale. Veuillez lui accorder l\'autorisation dans les paramètres.';

  @override
  String get libraryFolderNotExist => 'Le dossier sélectionné n\'existe pas';

  @override
  String get librarySourceDownloaded => 'Téléchargé';

  @override
  String get librarySourceLocal => 'Locale';

  @override
  String get libraryFilterAll => 'Tout';

  @override
  String get libraryFilterDownloaded => 'Téléchargé';

  @override
  String get libraryFilterLocal => 'Locale';

  @override
  String get libraryFilterTitle => 'Filtres';

  @override
  String get libraryFilterReset => 'Réinitialiser';

  @override
  String get libraryFilterApply => 'Appliquer';

  @override
  String get libraryFilterSource => 'Source';

  @override
  String get libraryFilterQuality => 'Qualité';

  @override
  String get libraryFilterQualityHiRes => 'Haute résolution (24 bits)';

  @override
  String get libraryFilterQualityCD => 'CD (16 bits)';

  @override
  String get libraryFilterQualityLossy => 'Avec perte';

  @override
  String get libraryFilterFormat => 'Format';

  @override
  String get libraryFilterMetadata => 'Métadonnées';

  @override
  String get libraryFilterMetadataComplete => 'Métadonnées complètes';

  @override
  String get libraryFilterMetadataMissingAny => 'Métadonnées manquantes';

  @override
  String get libraryFilterMetadataMissingYear => 'Année manquante';

  @override
  String get libraryFilterMetadataMissingGenre => 'Genre manquant';

  @override
  String get libraryFilterMetadataMissingAlbumArtist =>
      'Artiste d\'album manquant';

  @override
  String get libraryFilterSort => 'Trier';

  @override
  String get libraryFilterSortLatest => 'Le plus récent';

  @override
  String get libraryFilterSortOldest => 'Le plus ancien';

  @override
  String get libraryFilterSortAlbumAsc => 'Album (A-Z)';

  @override
  String get libraryFilterSortAlbumDesc => 'Album (Z-A)';

  @override
  String get libraryFilterSortGenreAsc => 'Genre (A-Z)';

  @override
  String get libraryFilterSortGenreDesc => 'Genre (Z-A)';

  @override
  String get timeJustNow => 'Il y a quelques instants';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count minutes',
      one: 'il y a 1 minute',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => 'Bienvenue sur SpotiFLAC !';

  @override
  String get tutorialWelcomeDesc =>
      'Apprenons comment télécharger votre musique préférée en qualité sans perte. Ce petit tutoriel vous présentera les bases.';

  @override
  String get tutorialWelcomeTip1 =>
      'Téléchargez de la musique depuis Spotify ou Deezer, ou collez n\'importe quelle URL prise en charge';

  @override
  String get tutorialWelcomeTip2 =>
      'Get FLAC quality audio from installed download extensions';

  @override
  String get tutorialWelcomeTip3 =>
      'Intégration automatique des métadonnées, des pochettes d\'album et des paroles';

  @override
  String get tutorialSearchTitle => 'Trouver de la musique';

  @override
  String get tutorialSearchDesc =>
      'Il existe deux façons simples de trouver la musique que vous souhaitez télécharger.';

  @override
  String get tutorialDownloadTitle => 'Télécharger de la musique';

  @override
  String get tutorialDownloadDesc =>
      'Télécharger de la musique, c\'est simple et rapide. Voici comment ça marche.';

  @override
  String get tutorialLibraryTitle => 'Votre bibliothèque';

  @override
  String get tutorialLibraryDesc =>
      'Toute votre musique téléchargée est classée dans l\'onglet « Bibliothèque ».';

  @override
  String get tutorialLibraryTip1 =>
      'Afficher la progression du téléchargement et la file d\'attente dans l\'onglet « Bibliothèque »';

  @override
  String get tutorialLibraryTip2 =>
      'Appuyez sur n\'importe quel morceau pour l\'écouter avec votre lecteur de musique';

  @override
  String get tutorialLibraryTip3 =>
      'Passez de l\'affichage sous forme de liste à celui sous forme de grille pour faciliter la navigation';

  @override
  String get tutorialExtensionsTitle => 'Extensions';

  @override
  String get tutorialExtensionsDesc =>
      'Élargissez les fonctionnalités de l\'application grâce aux extensions de la communauté.';

  @override
  String get tutorialExtensionsTip1 =>
      'Consultez l\'onglet « Dépôt » pour découvrir des extensions utiles';

  @override
  String get tutorialExtensionsTip2 =>
      'Ajouter de nouveaux fournisseurs de téléchargement ou de nouvelles sources de recherche';

  @override
  String get tutorialExtensionsTip3 =>
      'Accédez aux paroles, à des métadonnées enrichies et à bien d\'autres fonctionnalités';

  @override
  String get tutorialSettingsTitle => 'Personnalisez votre expérience';

  @override
  String get tutorialSettingsDesc =>
      'Personnalisez l\'application dans les Paramètres en fonction de vos préférences.';

  @override
  String get tutorialSettingsTip1 =>
      'Modifier l\'emplacement de téléchargement et l\'organisation des dossiers';

  @override
  String get tutorialSettingsTip2 =>
      'Définir les préférences par défaut en matière de qualité et de format audio';

  @override
  String get tutorialSettingsTip3 =>
      'Personnaliser le thème et l\'apparence de l\'application';

  @override
  String get tutorialReadyMessage =>
      'C\'est parti ! Commencez dès maintenant à télécharger votre musique préférée.';

  @override
  String get libraryForceFullScan => 'Lancer une analyse complète';

  @override
  String get libraryForceFullScanSubtitle =>
      'Réanalysez tous les fichiers en ignorant le cache';

  @override
  String get cleanupOrphanedDownloads =>
      'Nettoyage des téléchargements orphelins';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      'Supprimez les entrées de l\'historique correspondant aux fichiers qui n\'existent plus';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return '$count entrées orphelines ont été supprimées de l\'historique';
  }

  @override
  String get cleanupOrphanedDownloadsNone =>
      'Aucune entrée orpheline n\'a été trouvée';

  @override
  String get cacheTitle => 'Stockage & Cache';

  @override
  String get cacheSummaryTitle => 'Présentation du cache';

  @override
  String get cacheSummarySubtitle =>
      'La suppression du cache n\'entraînera pas la suppression des fichiers musicaux téléchargés.';

  @override
  String cacheEstimatedTotal(String size) {
    return 'Utilisation estimée du cache : $size';
  }

  @override
  String get cacheSectionStorage => 'Données mises en cache';

  @override
  String get cacheSectionMaintenance => 'Entretien';

  @override
  String get cacheAppDirectory => 'Répertoire de cache de l\'application';

  @override
  String get cacheAppDirectoryDesc =>
      'Réponses HTTP, données WebView et autres données temporaires de l\'application.';

  @override
  String get cacheTempDirectory => 'Répertoire temporaire';

  @override
  String get cacheTempDirectoryDesc =>
      'Fichiers temporaires liés aux téléchargements et à la conversion audio.';

  @override
  String get cacheCoverImage => 'Cache des images de couverture';

  @override
  String get cacheCoverImageDesc =>
      'J\'ai téléchargé les pochettes de l\'album et des titres. Je les téléchargerai à nouveau lors de leur consultation.';

  @override
  String get cacheLibraryCover => 'Cache de couverture de bibliothèque';

  @override
  String get cacheLibraryCoverDesc =>
      'Pochettes extraites des fichiers musicaux locaux. Elles seront extraites à nouveau lors de la prochaine analyse.';

  @override
  String get cacheExploreFeed => 'Explorer le cache des flux';

  @override
  String get cacheExploreFeedDesc =>
      'Contenu de l\'onglet « Explorer » (nouvelles sorties, tendances). Se mettra à jour lors de votre prochaine visite.';

  @override
  String get cacheTrackLookup => 'Cache de recherche de piste';

  @override
  String get cacheTrackLookupDesc =>
      'Recherche d\'identifiant de titre sur Spotify/Deezer. La suppression des données peut ralentir les prochaines recherches.';

  @override
  String get cacheCleanupUnusedDesc =>
      'Supprimer les entrées orphelines de l\'historique des téléchargements et de la bibliothèque pour les fichiers manquants.';

  @override
  String get cacheNoData => 'Aucune donnée mise en cache';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$size dans $count fichiers';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count entrées';
  }

  @override
  String cacheClearSuccess(String target) {
    return 'Effacé : $target';
  }

  @override
  String get cacheClearConfirmTitle => 'Vider le cache ?';

  @override
  String cacheClearConfirmMessage(String target) {
    return 'Cette opération effacera les données mises en cache pour $target. Les fichiers musicaux téléchargés ne seront pas supprimés.';
  }

  @override
  String get cacheClearAllConfirmTitle => 'Vider tout le cache ?';

  @override
  String get cacheClearAllConfirmMessage =>
      'Cette opération effacera toutes les catégories mises en cache sur cette page. Les fichiers musicaux téléchargés ne seront pas supprimés.';

  @override
  String get cacheClearAll => 'Vider tout le cache';

  @override
  String get cacheCleanupUnused => 'Nettoyer les données inutilisées';

  @override
  String get cacheCleanupUnusedSubtitle =>
      'Supprimer l\'historique des téléchargements orphelins et les entrées manquantes dans la bibliothèque';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return 'Nettoyage terminé : $downloadCount téléchargements orphelins, $libraryCount entrées de bibliothèque manquantes';
  }

  @override
  String get cacheRefreshStats => 'Actualiser les statistiques';

  @override
  String get trackSaveCoverArt => 'Enregistrer la pochette';

  @override
  String get trackSaveCoverArtSubtitle =>
      'Enregistrez la pochette de l\'album au format .jpg';

  @override
  String get trackSaveLyrics => 'Enregistrer les paroles (.lrc)';

  @override
  String get trackSaveLyricsSubtitle =>
      'Récupérez et enregistrez les paroles sous forme de fichier .lrc';

  @override
  String get trackSaveLyricsProgress => 'Enregistrement des paroles...';

  @override
  String get trackReEnrich => 'Réenrichir';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Rechercher des métadonnées en ligne et les intégrer dans un fichier';

  @override
  String get trackReEnrichFieldsTitle => 'Champs à mettre à jour';

  @override
  String get trackReEnrichFieldCover => 'Illustration de couverture';

  @override
  String get trackReEnrichFieldLyrics => 'Paroles';

  @override
  String get trackReEnrichFieldBasicTags => 'Album, Album Artiste';

  @override
  String get trackReEnrichFieldTrackInfo => 'Numéro de piste & de disque';

  @override
  String get trackReEnrichFieldReleaseInfo => 'Date & ISRC';

  @override
  String get trackReEnrichFieldExtra => 'Genre, Label, Droits d\'auteur';

  @override
  String get trackReEnrichSelectAll => 'Tout sélectionner';

  @override
  String get trackEditMetadata => 'Modifier les métadonnées';

  @override
  String trackCoverSaved(String fileName) {
    return 'La pochette a été enregistrée sous le nom $fileName';
  }

  @override
  String get trackCoverNoSource =>
      'Aucune source d\'illustration de couverture disponible';

  @override
  String trackLyricsSaved(String fileName) {
    return 'Paroles enregistrées dans $fileName';
  }

  @override
  String get trackReEnrichProgress => 'Réenrichissement des métadonnées...';

  @override
  String get trackReEnrichSearching => 'Recherche de métadonnées en ligne...';

  @override
  String get trackReEnrichSuccess => 'Métadonnées réenrichies avec succès';

  @override
  String get trackReEnrichFfmpegFailed =>
      'Échec de l\'intégration des métadonnées FFmpeg';

  @override
  String get queueFlacAction => 'File d\'attente FLAC';

  @override
  String queueFlacConfirmMessage(int count) {
    return 'Recherchez en ligne les correspondances pour les morceaux sélectionnés et ajoutez les téléchargements FLAC à la file d\'attente.\n\nLes fichiers existants ne seront ni modifiés ni supprimés.\n\nSeules les correspondances hautement fiables sont automatiquement ajoutées à la file d\'attente.\n\n$count sélectionnés';
  }

  @override
  String queueFlacFindingProgress(int current, int total) {
    return 'Recherche de fichiers FLAC... ($current/$total)';
  }

  @override
  String get queueFlacNoReliableMatches =>
      'Aucun résultat pertinent n\'a été trouvé en ligne pour cette sélection';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return '$addedCount titres ajoutés à la file d\'attente, $skippedCount titres ignorés';
  }

  @override
  String trackSaveFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String get trackConvertFormat => 'Convertir le format';

  @override
  String get trackConvertFormatSubtitle =>
      'Convertir au format AAC/M4A, MP3, Opus, ALAC ou FLAC';

  @override
  String get trackConvertTitle => 'Convertir un fichier audio';

  @override
  String get trackConvertTargetFormat => 'Format cible';

  @override
  String get trackConvertBitrate => 'Débit binaire';

  @override
  String get trackConvertConfirmTitle => 'Confirmer la conversion';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return 'Convertir du format $sourceFormat au format $targetFormat avec un débit binaire de $bitrate ?\n\nLe fichier d\'origine sera supprimé après la conversion.';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Convertir de $sourceFormat vers $targetFormat ? (Sans perte — aucune perte de qualité)\n\nLe fichier d\'origine sera supprimé après la conversion.';
  }

  @override
  String get trackConvertLosslessHint =>
      'Conversion sans perte — aucune perte de qualité';

  @override
  String get trackConvertConverting => 'Conversion audio en cours...';

  @override
  String trackConvertSuccess(String format) {
    return 'Conversion vers $format réussie';
  }

  @override
  String get trackConvertFailed => 'Échec de la conversion';

  @override
  String get cueSplitTitle => 'Fiche CUE fractionnée';

  @override
  String get cueSplitSubtitle =>
      'Diviser un fichier CUE+FLAC en pistes individuelles';

  @override
  String cueSplitAlbum(String album) {
    return 'Album : $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return 'Artiste : $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count titres';
  }

  @override
  String get cueSplitConfirmTitle => 'Album CUE fractionné';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return 'Diviser « $album » en $count fichiers FLAC individuels ?\n\nLes fichiers seront enregistrés dans le même répertoire.';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'Fractionnement de la liste CUE... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return 'Le fichier a été divisé en $count pistes avec succès';
  }

  @override
  String get cueSplitFailed => 'Échec de la division CUE';

  @override
  String get cueSplitNoAudioFile =>
      'Fichier audio introuvable pour cette liste CUE';

  @override
  String get cueSplitButton => 'Diviser en pistes';

  @override
  String get actionCreate => 'Créer';

  @override
  String get collectionFoldersTitle => 'Mes dossiers';

  @override
  String get collectionWishlist => 'Liste de souhaits';

  @override
  String get collectionLoved => 'Favoris';

  @override
  String get collectionFavoriteArtists => 'Artistes Favoris';

  @override
  String get collectionPlaylists => 'Playlists';

  @override
  String get collectionPlaylist => 'Playlist';

  @override
  String get collectionAddToPlaylist => 'Ajouter à la playlist';

  @override
  String get collectionCreatePlaylist => 'Créer une playlist';

  @override
  String get collectionNoPlaylistsYet => 'Aucune playlist pour le moment';

  @override
  String get collectionNoPlaylistsSubtitle =>
      'Créez une playlist pour commencer à classer vos morceaux';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '1 titre',
    );
    return '$_temp0';
  }

  @override
  String collectionArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artistes',
      one: '1 artiste',
    );
    return '$_temp0';
  }

  @override
  String collectionAddedToPlaylist(String playlistName) {
    return 'Ajouté à « $playlistName »';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return 'Déjà présent dans « $playlistName »';
  }

  @override
  String get collectionPlaylistCreated => 'Playlist créée';

  @override
  String get collectionPlaylistNameHint => 'Nom de la playlist';

  @override
  String get collectionPlaylistNameRequired =>
      'Le nom de la playlist est requis';

  @override
  String get collectionRenamePlaylist => 'Renommer la playlist';

  @override
  String get collectionDeletePlaylist => 'Supprimer la playlist';

  @override
  String collectionDeletePlaylistMessage(String playlistName) {
    return 'Supprimer « $playlistName » et tous les morceaux qu\'elle contient ?';
  }

  @override
  String get collectionPlaylistDeleted => 'Playlist supprimée';

  @override
  String get collectionPlaylistRenamed => 'Playlist renommée';

  @override
  String get collectionWishlistEmptyTitle => 'La liste de souhaits est vide';

  @override
  String get collectionWishlistEmptySubtitle =>
      'Appuyez sur le signe « + » à côté des morceaux pour enregistrer ceux que vous souhaitez télécharger plus tard';

  @override
  String get collectionLovedEmptyTitle => 'Le dossier « Favoris » est vide';

  @override
  String get collectionLovedEmptySubtitle =>
      'Appuyez sur les morceaux que vous aimez pour les ajouter à vos favoris';

  @override
  String get collectionFavoriteArtistsEmptyTitle =>
      'Pas encore d\'artistes préférés';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      'Appuyez sur le cœur sur la page d\'un artiste pour le garder ici';

  @override
  String get collectionPlaylistEmptyTitle => 'La playlist est vide';

  @override
  String get collectionPlaylistEmptySubtitle =>
      'Appuyez longuement sur le bouton « + » sur n\'importe quel morceau pour l\'ajouter ici';

  @override
  String get collectionRemoveFromPlaylist => 'Supprimer de la playlist';

  @override
  String get collectionRemoveFromFolder => 'Supprimer du dossier';

  @override
  String collectionRemoved(String trackName) {
    return '« $trackName » supprimé';
  }

  @override
  String collectionAddedToLoved(String trackName) {
    return '\"$trackName\" ajouté aux Favoris';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\"$trackName\" supprimé des Favoris';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '« $trackName » a été ajouté à la liste de souhaits';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '« $trackName » a été supprimé de la liste de souhaits';
  }

  @override
  String collectionAddedToFavoriteArtists(String artistName) {
    return '« $artistName » a été ajouté à vos artistes préférés';
  }

  @override
  String collectionRemovedFromFavoriteArtists(String artistName) {
    return '« $artistName » a été supprimé de vos artistes favoris';
  }

  @override
  String get trackOptionAddToLoved => 'Ajouter aux Favoris';

  @override
  String get trackOptionRemoveFromLoved => 'Supprimer des Favoris';

  @override
  String get trackOptionAddToWishlist => 'Ajouter à la liste de souhaits';

  @override
  String get trackOptionRemoveFromWishlist =>
      'Supprimer de la liste de souhaits';

  @override
  String get artistOptionAddToFavorites => 'Ajouter aux Artistes Favoris';

  @override
  String get artistOptionRemoveFromFavorites =>
      'Supprimer des Artistes Favoris';

  @override
  String get collectionPlaylistChangeCover => 'Changer l\'image de couverture';

  @override
  String get collectionPlaylistRemoveCover =>
      'Supprimer l\'image de couverture';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Partager $count $_temp0';
  }

  @override
  String get selectionShareNoFiles =>
      'Aucun fichier partageable n\'a été trouvé';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Convertir $count $_temp0';
  }

  @override
  String get selectionConvertNoConvertible =>
      'Aucune piste convertible sélectionnée';

  @override
  String get selectionBatchConvertConfirmTitle => 'Conversion par lots';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Convertir $count $_temp0 au format $format avec un débit binaire de $bitrate ?\n\nLes fichiers d\'origine seront supprimés après la conversion.';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Convertir $count $_temp0 au format $format ? (Sans perte — aucune perte de qualité)\n\nLes fichiers d\'origine seront supprimés après la conversion.';
  }

  @override
  String selectionBatchConvertProgress(int current, int total) {
    return 'Conversion de $current sur $total...';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return '$success pistes sur $total ont été converties au format $format';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count téléchargements';
  }

  @override
  String get downloadUseAlbumArtistForFoldersAlbumSubtitle =>
      'Dossier nommé d\'après la balise « Artiste de l\'album »';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      'Dossier nommé d\'après la balise « Artiste » de la piste';

  @override
  String get lyricsProvidersTitle => 'Priorité au fournisseur de paroles';

  @override
  String get lyricsProvidersDescription =>
      'Activer, désactiver et réorganiser les sources de paroles. Les sources sont parcourues de haut en bas jusqu\'à ce que les paroles soient trouvées.';

  @override
  String get lyricsProvidersInfoText =>
      'Extension lyrics providers run before built-in lyrics providers. At least one provider must remain enabled.';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return 'Activé ($count)';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return 'Désactivés ($count)';
  }

  @override
  String get lyricsProvidersAtLeastOne =>
      'Au moins un fournisseur doit rester activé';

  @override
  String get lyricsProvidersSaved =>
      'Priorité du fournisseur de paroles enregistrée';

  @override
  String get lyricsProvidersDiscardContent =>
      'Vous avez des modifications non enregistrées qui seront perdues.';

  @override
  String get lyricsProviderLrclibDesc =>
      'Base de données open source de paroles synchronisées';

  @override
  String get lyricsProviderNeteaseDesc =>
      'NetEase Cloud Music (idéal pour les titres asiatiques)';

  @override
  String get lyricsProviderMusixmatchDesc =>
      'La plus grande base de données de paroles (multilingue)';

  @override
  String get lyricsProviderAppleMusicDesc =>
      'Paroles synchronisées mot à mot (via un proxy)';

  @override
  String get lyricsProviderQqMusicDesc =>
      'QQ Music (idéal pour écouter des titres chinois, via un proxy)';

  @override
  String get lyricsProviderLyricsPlusDesc =>
      'Word-by-word karaoke lyrics (Apple/Musixmatch/Spotify/QQ, via proxy)';

  @override
  String get lyricsProviderExtensionDesc => 'Fournisseur d\'extensions';

  @override
  String get safMigrationTitle => 'Mise à jour du stockage requise';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC utilise désormais le framework d\'accès au stockage Android (SAF) pour les téléchargements. Cela permet de résoudre les erreurs « autorisation refusée » sur Android 10 et versions ultérieures.';

  @override
  String get safMigrationMessage2 =>
      'Veuillez sélectionner à nouveau votre dossier de téléchargement pour passer au nouveau système de stockage.';

  @override
  String get safMigrationSuccess =>
      'Le dossier de téléchargement a été mis à jour en mode SAF';

  @override
  String get settingsDonate => 'Soutien au développement';

  @override
  String get settingsDonateSubtitle => 'Offrez un café au développeur';

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
  String get backupCreating => 'Creating backup...';

  @override
  String get backupCreated => 'Backup created';

  @override
  String get backupCreateFailed => 'Failed to create backup';

  @override
  String get backupEmpty => 'There is nothing to back up yet';

  @override
  String get backupRestoreConfirmTitle => 'Restore this backup?';

  @override
  String get backupRestoreConfirmMessage =>
      'This will replace your current settings, download history, liked tracks, wishlist and playlists with the contents of the backup. This cannot be undone.';

  @override
  String get backupRestoreConfirmButton => 'Restore';

  @override
  String get backupRestoring => 'Restoring backup...';

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
    return '$count $_temp0 could not be reinstalled. Install them manually from the store.';
  }

  @override
  String get tooltipLoveAll => 'Tout aimer';

  @override
  String get tooltipAddToPlaylist => 'Ajouter à la playlist';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return '$count titres supprimés des Favoris';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return '$count titres ajoutés aux Favoris';
  }

  @override
  String get dialogDownloadAllTitle => 'Tout télécharger';

  @override
  String dialogDownloadAllMessage(int count) {
    return 'Télécharger $count titres ?';
  }

  @override
  String get homeSkipAlreadyDownloaded =>
      'Ignorer les morceaux déjà téléchargés';

  @override
  String get homeGoToAlbum => 'Aller à l\'album';

  @override
  String get homeAlbumInfoUnavailable =>
      'Informations sur l\'album non disponibles';

  @override
  String get snackbarLoadingCueSheet => 'Chargement de la liste CUE...';

  @override
  String get snackbarMetadataSaved =>
      'Les métadonnées ont été enregistrées avec succès';

  @override
  String get snackbarFailedToEmbedLyrics =>
      'Impossible d\'intégrer les paroles';

  @override
  String get snackbarFailedToWriteStorage =>
      'Échec de l\'écriture sur le support de stockage';

  @override
  String snackbarError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get snackbarNoActionDefined =>
      'Aucune action n\'est associée à ce bouton';

  @override
  String get noTracksFoundForAlbum => 'Aucun morceau trouvé pour cet album';

  @override
  String get downloadLocationSubtitle =>
      'Choisissez l\'emplacement où enregistrer vos morceaux téléchargés';

  @override
  String get storageModeAppFolder => 'Dossier « Applications » (recommandé)';

  @override
  String get storageModeAppFolderSubtitle =>
      'Enregistrement par défaut dans le dossier « Musique/SpotiFLAC »';

  @override
  String get storageModeSaf => 'Dossier personnalisé (SAF)';

  @override
  String get storageModeSafSubtitle =>
      'Choisissez n\'importe quel dossier, y compris la carte SD';

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
    return 'Utilisez $artist, $title, $album, $track, $year, $date et $disc comme variables de remplacement.';
  }

  @override
  String get downloadFilenameInsertTag => 'Appuyez pour insérer une balise :';

  @override
  String get downloadSeparateSinglesEnabled =>
      'Les singles et les EP sont enregistrés dans un dossier séparé';

  @override
  String get downloadSeparateSinglesDisabled =>
      'Les singles et les albums sont enregistrés dans le même dossier';

  @override
  String get downloadArtistNameFilters => 'Filtres par nom d\'artiste';

  @override
  String get downloadCreatePlaylistSourceFolder =>
      'Dossier source de la playlist';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      'Un sous-dossier est créé pour chaque playlist';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      'Tous les morceaux sont enregistrés directement dans le dossier de téléchargement';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant =>
      'Géré par les paramètres d\'organisation des dossiers';

  @override
  String get downloadSongLinkRegion => 'Région SongLink';

  @override
  String get downloadNetworkCompatibilityMode => 'Mode de compatibilité réseau';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Utilisation des paramètres TLS hérités pour les réseaux plus anciens';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Utilisation des paramètres réseau par défaut';

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
  String get downloadSelectTidalQobuz =>
      'Select a provider with quality options to choose audio quality';

  @override
  String get downloadEmbedLyricsDisabled =>
      'Activez d\'abord l\'intégration des métadonnées';

  @override
  String get downloadNeteaseIncludeTranslation =>
      'Netease : inclure la traduction';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Lignes de traduction en chinois incluses';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Paroles originales uniquement';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease : inclure la romanisation';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled =>
      'Lignes de romanisation incluses';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled =>
      'Pas de romanisation';

  @override
  String get downloadAppleQqMultiPerson =>
      'Apple / QQ : Paroles pour plusieurs personnes';

  @override
  String get downloadAppleQqMultiPersonEnabled =>
      'Étiquettes d\'intervenants incluses pour les duos et les morceaux en groupe';

  @override
  String get downloadAppleQqMultiPersonDisabled =>
      'Paroles standard sans indication du haut-parleur';

  @override
  String get downloadAppleElrcWordSync =>
      'Synchronisation des paroles Apple Music eLRC';

  @override
  String get downloadAppleElrcWordSyncEnabled =>
      'Conservation des horodatages bruts mot à mot';

  @override
  String get downloadAppleElrcWordSyncDisabled =>
      'Paroles d\'Apple Music, ligne par ligne, en toute sécurité';

  @override
  String get downloadMusixmatchLanguage => 'Langue Musixmatch';

  @override
  String get downloadMusixmatchLanguageAuto => 'Auto (langue d\'origine)';

  @override
  String get downloadFilterContributing => 'Filtrer les artistes participants';

  @override
  String get downloadFilterContributingEnabled =>
      'Les artistes ayant contribué à l\'album ont été supprimés du nom du dossier « Artiste de l\'album »';

  @override
  String get downloadFilterContributingDisabled =>
      'Chaîne « Artiste » de l\'album complet utilisée';

  @override
  String get downloadProvidersNoneEnabled => 'Aucun fournisseur n\'est activé';

  @override
  String get downloadMusixmatchLanguageCode => 'Code de langue';

  @override
  String get downloadMusixmatchLanguageHint => 'par exemple : en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Saisissez un code de langue BCP-47 (par exemple : en, de, ja) pour demander les paroles traduites à Musixmatch.';

  @override
  String get downloadMusixmatchAuto => 'Auto';

  @override
  String get downloadNetworkAnySubtitle =>
      'Utilisez le Wi-Fi ou les données mobiles';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Les téléchargements sont mis en pause lors de l\'utilisation des données mobiles';

  @override
  String get downloadSongLinkRegionDesc =>
      'Région utilisée lors de la résolution des liens vers les morceaux via SongLink. Sélectionnez le pays dans lequel vos services de streaming sont disponibles.';

  @override
  String get snackbarUnsupportedAudioFormat =>
      'Format audio non pris en charge';

  @override
  String get cacheRefresh => 'Actualiser';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    String _temp1 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Télécharger $trackCount $_temp0 depuis $playlistCount $_temp1 ?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Télécharger $count $_temp0';
  }

  @override
  String get bulkDownloadSelectPlaylists =>
      'Sélectionnez les playlists à télécharger';

  @override
  String get snackbarSelectedPlaylistsEmpty =>
      'Les playlists sélectionnées ne contiennent aucun morceau';

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
  String get editMetadataAutoFill => 'Remplissage automatique en ligne';

  @override
  String get editMetadataAutoFillDesc =>
      'Sélectionnez les champs à remplir automatiquement à partir des métadonnées en ligne';

  @override
  String get editMetadataAutoFillFetch => 'Récupérer & remplir';

  @override
  String get editMetadataAutoFillSearching => 'Recherche en ligne...';

  @override
  String get editMetadataAutoFillNoResults =>
      'Aucune métadonnée correspondante n\'a été trouvée en ligne';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'champs',
      one: 'champ',
    );
    return '$count $_temp0 renseignés à partir des métadonnées en ligne';
  }

  @override
  String get editMetadataAutoFillNoneSelected =>
      'Sélectionnez au moins un champ pour le remplir automatiquement';

  @override
  String get editMetadataFieldTitle => 'Titre';

  @override
  String get editMetadataFieldArtist => 'Artiste';

  @override
  String get editMetadataFieldAlbum => 'Album';

  @override
  String get editMetadataFieldAlbumArtist => 'Artiste de l\'album';

  @override
  String get editMetadataFieldDate => 'Date';

  @override
  String get editMetadataFieldTrackNum => 'Piste n°';

  @override
  String get editMetadataFieldDiscNum => 'Disque n°';

  @override
  String get editMetadataFieldGenre => 'Genre';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => 'Label';

  @override
  String get editMetadataFieldCopyright => 'Droits d\'auteur';

  @override
  String get editMetadataFieldCover => 'Illustration de couverture';

  @override
  String get editMetadataSelectAll => 'Tout';

  @override
  String get editMetadataSelectEmpty => 'Vide uniquement';

  @override
  String queueDownloadingCount(int count) {
    return 'Téléchargement ($count)';
  }

  @override
  String get queueDownloadedHeader => 'Téléchargé';

  @override
  String get queueFilteringIndicator => 'Filtrage...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '1 titre',
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
  String get queueEmptyAlbums => 'Aucun album téléchargé';

  @override
  String get queueEmptyAlbumsSubtitle =>
      'Téléchargez plusieurs titres d\'un album pour les écouter ici';

  @override
  String get queueEmptySingles => 'Pas de téléchargement individuel';

  @override
  String get queueEmptySinglesSubtitle =>
      'Les téléchargements de titres individuels apparaîtront ici';

  @override
  String get queueEmptyHistory => 'Aucun historique de téléchargement';

  @override
  String get queueEmptyHistorySubtitle =>
      'Les morceaux téléchargés apparaîtront ici';

  @override
  String get selectionAllPlaylistsSelected =>
      'Toutes les playlists sélectionnées';

  @override
  String get selectionTapPlaylistsToSelect =>
      'Appuyez sur les playlists pour les sélectionner';

  @override
  String get selectionSelectPlaylistsToDelete =>
      'Sélectionnez les playlists à supprimer';

  @override
  String get audioAnalysisTitle => 'Analyse de la qualité audio';

  @override
  String get audioAnalysisDescription =>
      'Vérifier la qualité sans perte à l\'aide d\'une analyse spectrale';

  @override
  String get audioAnalysisAnalyzing => 'Analyse audio en cours...';

  @override
  String get audioAnalysisSampleRate => 'Fréquence d\'échantillonnage';

  @override
  String get audioAnalysisCodec => 'Codec';

  @override
  String get audioAnalysisContainer => 'Conteneur';

  @override
  String get audioAnalysisDecodedFormat => 'Format décodé';

  @override
  String get audioAnalysisBitDepth => 'Nombre de bits';

  @override
  String get audioAnalysisChannels => 'Chaînes';

  @override
  String get audioAnalysisDuration => 'Durée';

  @override
  String get audioAnalysisNyquist => 'Nyquist';

  @override
  String get audioAnalysisFileSize => 'Taille';

  @override
  String get audioAnalysisDynamicRange => 'Plage dynamique';

  @override
  String get audioAnalysisPeak => 'Pic';

  @override
  String get audioAnalysisRms => 'RMS';

  @override
  String get audioAnalysisLufs => 'LUFS';

  @override
  String get audioAnalysisTruePeak => 'True Peak';

  @override
  String get audioAnalysisClipping => 'Coupure';

  @override
  String get audioAnalysisNoClipping => 'Pas de coupure';

  @override
  String get audioAnalysisSpectralCutoff => 'Limite spectrale';

  @override
  String get audioAnalysisChannelStats => 'Statistiques par chaîne';

  @override
  String get audioAnalysisSamples => 'Échantillons';

  @override
  String get audioAnalysisRescan => 'Réanalyser';

  @override
  String get audioAnalysisRescanning => 'Réanalyse du fichier audio...';

  @override
  String extensionsSearchWith(String providerName) {
    return 'Rechercher avec $providerName';
  }

  @override
  String get extensionsHomeFeedProvider => 'Fournisseur de flux RSS';

  @override
  String get extensionsHomeFeedDescription =>
      'Choisissez l\'extension qui affiche le fil d\'actualité sur l\'écran principal';

  @override
  String get extensionsHomeFeedAuto => 'Auto';

  @override
  String get extensionsHomeFeedAutoSubtitle =>
      'Sélectionnez automatiquement la meilleure option disponible';

  @override
  String get extensionsHomeFeedOff => 'Off';

  @override
  String get extensionsHomeFeedOffSubtitle =>
      'Ne pas afficher le fil d\'actualité sur l\'écran principal';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return 'Utiliser le fil d\'actualité de $extensionName';
  }

  @override
  String get extensionsNoHomeFeedExtensions =>
      'Aucune extension avec le flux principal';

  @override
  String get sortAlphaAsc => 'A-Z';

  @override
  String get sortAlphaDesc => 'Z-A';

  @override
  String get cancelDownloadTitle => 'Annuler le téléchargement ?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'Cela annulera le téléchargement en cours de « $trackName ».';
  }

  @override
  String get cancelDownloadKeep => 'Conserver';

  @override
  String get metadataSaveFailedFfmpeg =>
      'Échec de l\'enregistrement des métadonnées via FFmpeg';

  @override
  String get metadataSaveFailedStorage =>
      'Échec de la réécriture des métadonnées sur le support de stockage';

  @override
  String snackbarFolderPickerFailed(String error) {
    return 'Impossible d\'ouvrir le sélecteur de dossiers : $error';
  }

  @override
  String get errorLoadAlbum => 'Impossible de charger l\'album';

  @override
  String get errorLoadPlaylist => 'Impossible de charger la playlist';

  @override
  String get errorLoadArtist => 'Impossible de charger l\'artiste';

  @override
  String get notifChannelDownloadName => 'Progression du téléchargement';

  @override
  String get notifChannelDownloadDesc =>
      'Affiche la progression du téléchargement des morceaux';

  @override
  String get notifChannelLibraryScanName => 'Analyse de la bibliothèque';

  @override
  String get notifChannelLibraryScanDesc =>
      'Affiche la progression de la numérisation dans la bibliothèque locale';

  @override
  String notifDownloadingTrack(String trackName) {
    return 'Téléchargement de $trackName';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return 'Finalisation de $trackName';
  }

  @override
  String get notifEmbeddingMetadata => 'Intégration des métadonnées...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return 'Déjà dans la bibliothèque ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => 'Déjà dans la bibliothèque';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return 'Téléchargement terminé ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => 'Télécharger l\'intégralité';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return 'Téléchargements terminés ($completed terminé, $failed en échec)';
  }

  @override
  String get notifAllDownloadsComplete =>
      'Tous les téléchargements sont terminés';

  @override
  String notifTracksDownloadedSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistes téléchargées avec succès',
      one: '1 piste téléchargée avec succès',
    );
    return '$_temp0';
  }

  @override
  String notifDownloadsFinishedBody(int completed, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      completed,
      locale: localeName,
      other: '$completed titres téléchargés',
      one: '1 titre téléchargé',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed échecs',
      one: '1 échec',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get notifDownloadsCanceledTitle => 'Téléchargements annulés';

  @override
  String notifDownloadsCanceledBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count téléchargements annulés par l\'utilisateur',
      one: '1 téléchargement annulé par l\'utilisateur',
    );
    return '$_temp0';
  }

  @override
  String get notifScanningLibrary => 'Numérisation de la bibliothèque locale';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total fichiers • $percentage %';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned fichiers analysés • $percentage %';
  }

  @override
  String get notifLibraryScanComplete => 'Analyse de la bibliothèque terminée';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count titres indexés';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count exclus';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count erreurs';
  }

  @override
  String get notifLibraryScanFailed => 'Échec de l\'analyse de la bibliothèque';

  @override
  String get notifLibraryScanCancelled =>
      'Annulation de la numérisation de la bibliothèque';

  @override
  String get notifLibraryScanStopped =>
      'L\'analyse a été interrompue avant d\'être terminée.';

  @override
  String notifDownloadingUpdate(String version) {
    return 'Télécharger SpotiFLAC v$version';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total Mo • $percentage%';
  }

  @override
  String get notifUpdateReady => 'Prêt pour la mise à jour';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC v$version a été téléchargé. Appuyez pour l\'installer.';
  }

  @override
  String get notifUpdateFailed => 'Échec de la mise à jour';

  @override
  String get notifUpdateFailedBody =>
      'Impossible de télécharger la mise à jour. Veuillez réessayer plus tard.';

  @override
  String get searchTracks => 'Titres';

  @override
  String get homeSearchHintDefault =>
      'Collez une URL valide ou effectuez une recherche...';

  @override
  String homeSearchHintProvider(String providerName) {
    return 'Rechercher avec $providerName...';
  }

  @override
  String get homeImportCsvTooltip => 'Importer un fichier CSV';

  @override
  String get homeChangeSearchProviderTooltip =>
      'Changer de moteur de recherche';

  @override
  String get actionPaste => 'Coller';

  @override
  String get searchTracksHint => 'Rechercher des morceaux...';

  @override
  String get searchTracksEmptyPrompt => 'Rechercher des morceaux';

  @override
  String get tutorialSearchHint => 'Collez ou effectuez une recherche...';

  @override
  String get tutorialDownloadCompletedSemantics => 'Téléchargement terminé';

  @override
  String get tutorialDownloadInProgressSemantics => 'Téléchargement en cours';

  @override
  String get tutorialStartDownloadSemantics => 'Lancer le téléchargement';

  @override
  String get optionsEmbedMetadata => 'Intégrer des métadonnées';

  @override
  String get optionsEmbedMetadataSubtitleOn =>
      'Ajouter des métadonnées, des pochettes et des paroles intégrées aux fichiers';

  @override
  String get optionsEmbedMetadataSubtitleOff =>
      'Désactivé (avancé) : ignorer l\'intégration de toutes les métadonnées';

  @override
  String get optionsMaxQualityCoverSubtitleDisabled =>
      'Désactivé lorsque l\'intégration des métadonnées est désactivée';

  @override
  String downloadFilenameHintExample(Object artist, Object title) {
    return '$artist - $title';
  }

  @override
  String get trackCoverNoEmbeddedArt =>
      'Aucune pochette d\'album n\'a été trouvée';

  @override
  String get trackCoverReplace => 'Remplacer la pochette';

  @override
  String get trackCoverPick => 'Choisir une pochette';

  @override
  String get trackCoverClearSelected => 'Supprimer la pochette sélectionnée';

  @override
  String get trackCoverCurrent => 'Pochette actuelle';

  @override
  String get trackCoverSelected => 'Pochette choisie';

  @override
  String get trackCoverReplaceNotice =>
      'La pochette sélectionnée remplacera la pochette actuellement intégrée lorsque vous appuierez sur « Enregistrer ».';

  @override
  String get actionStop => 'Arrêter';

  @override
  String get queueFinalizingDownload => 'Téléchargement en cours';

  @override
  String get queueDownloadedFileMissing => 'Fichier téléchargé manquant';

  @override
  String get queueDownloadCompleted => 'Téléchargement terminé';

  @override
  String get queueRateLimitTitle => 'Débit limité';

  @override
  String get queueRateLimitMessage =>
      'Ce titre est peut-être encore disponible. Patientez quelques minutes, réduisez le nombre de téléchargements simultanés, puis réessayez.';

  @override
  String appearanceSelectAccentColor(String hex) {
    return 'Sélectionnez une couleur d\'accentuation $hex';
  }

  @override
  String get logAutoScrollOn => 'Défilement automatique activé';

  @override
  String get logAutoScrollOff => 'Défilement automatique désactivé';

  @override
  String get logCopyLogs => 'Copier les journaux';

  @override
  String get logClearSearch => 'Effacer la recherche';

  @override
  String get logIssueIspBlockingLabel => 'BLOCAGE PAR LE FAI DÉTECTÉ';

  @override
  String get logIssueIspBlockingDescription =>
      'Il se peut que votre fournisseur d\'accès Internet bloque l\'accès aux services de téléchargement';

  @override
  String get logIssueIspBlockingSuggestion =>
      'Essayez d\'utiliser un VPN ou de modifier vos paramètres DNS pour les remplacer par 1.1.1.1 ou 8.8.8.8';

  @override
  String get logIssueRateLimitedLabel => 'NOMBRE LIMITÉ';

  @override
  String get logIssueRateLimitedDescription =>
      'Trop de requêtes adressées au service';

  @override
  String get logIssueRateLimitedSuggestion =>
      'Attendez quelques minutes avant de réessayer';

  @override
  String get logIssueNetworkErrorLabel => 'ERREUR DE RÉSEAU';

  @override
  String get logIssueNetworkErrorDescription =>
      'Problèmes de connexion détectés';

  @override
  String get logIssueNetworkErrorSuggestion =>
      'Vérifiez votre connexion Internet';

  @override
  String get logIssueTrackNotFoundLabel => 'PISTE INTROUVABLE';

  @override
  String get logIssueTrackNotFoundDescription =>
      'Certains titres n\'ont pas pu être trouvés sur les plateformes de téléchargement';

  @override
  String get logIssueTrackNotFoundSuggestion =>
      'Il se peut que ce morceau ne soit pas disponible en qualité sans perte';

  @override
  String get clickableLookingUpArtist => 'Recherche d\'artiste...';

  @override
  String clickableInformationUnavailable(String type) {
    return 'Informations sur $type non disponibles';
  }

  @override
  String get extensionDetailsTags => 'Balises';

  @override
  String get extensionDetailsInformation => 'Information';

  @override
  String get extensionUtilityFunctions => 'Fonctions utilitaires';

  @override
  String get actionDismiss => 'Ignorer';

  @override
  String get setupChangeFolderTooltip => 'Changer de dossier';

  @override
  String a11yOpenTrackByArtist(String trackName, String artistName) {
    return 'Écouter le morceau $trackName de $artistName';
  }

  @override
  String a11yOpenItem(String itemType, String name) {
    return 'Ouvrir $itemType $name';
  }

  @override
  String a11yOpenItemCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'éléments',
      one: 'item',
    );
    return 'Ouvrir $title, $count $_temp0';
  }

  @override
  String a11yOpenAlbumByArtistTrackCount(
    String albumName,
    String artistName,
    int trackCount,
  ) {
    return 'Ouvrir l\'album $albumName de $artistName, $trackCount titres';
  }

  @override
  String a11yTrackByArtist(String trackName, String artistName) {
    return '$trackName de $artistName';
  }

  @override
  String a11ySelectAlbum(String albumName) {
    return 'Sélectionnez l\'album $albumName';
  }

  @override
  String a11yOpenAlbum(String albumName) {
    return 'Ouvrir l\'album $albumName';
  }

  @override
  String get optionsDefaultSearchTabAlbums => 'Albums';

  @override
  String get optionsDefaultSearchTabTracks => 'Titres';

  @override
  String get settingsFiles => 'Fichiers & Dossiers';

  @override
  String get settingsFilesSubtitle =>
      'Emplacement de téléchargement, nom de fichier, structure des dossiers';

  @override
  String get settingsMetadata => 'Métadonnées';

  @override
  String get settingsMetadataSubtitle =>
      'Pochettes, balises, ReplayGain, fournisseurs';

  @override
  String get settingsLyrics => 'Paroles';

  @override
  String get settingsLyricsSubtitle =>
      'Intégration, mode, fournisseurs, options linguistiques';

  @override
  String get settingsApp => 'Application';

  @override
  String get settingsAppSubtitle =>
      'Mises à jour, données, dépôt d\'extension, débogage';

  @override
  String get sectionMetadataProviders => 'Fournisseurs';

  @override
  String get sectionDuplicates => 'Doublons';

  @override
  String get sectionLyricsProviderOptions => 'Options du fournisseur';

  @override
  String get metadataProvidersTitle =>
      'Priorité des fournisseurs de métadonnées';

  @override
  String get metadataProvidersSubtitle =>
      'Faites glisser pour définir l\'ordre des sources de recherche et de métadonnées';

  @override
  String get downloadDeduplication => 'Éviter les téléchargements en double';

  @override
  String get downloadDeduplicationEnabled =>
      'Les morceaux déjà téléchargés seront ignorés';

  @override
  String get downloadDeduplicationDisabled =>
      'Tous les morceaux seront téléchargés, quel que soit l\'historique';

  @override
  String get downloadFallbackExtensions => 'Extensions de secours';

  @override
  String get downloadFallbackExtensionsSubtitle =>
      'Choisissez les extensions pouvant servir de solution de secours';

  @override
  String get editMetadataFieldDateHint => 'AAAA-MM-JJ ou AAAA';

  @override
  String get editMetadataFieldTrackTotal => 'Total des pistes';

  @override
  String get editMetadataFieldDiscTotal => 'Total des disques';

  @override
  String get editMetadataFieldComposer => 'Compositeur';

  @override
  String get editMetadataFieldComment => 'Commentaire';

  @override
  String get editMetadataAdvanced => 'Avancé';

  @override
  String get libraryFilterMetadataMissingTrackNumber =>
      'Numéro de piste manquant';

  @override
  String get libraryFilterMetadataMissingDiscNumber =>
      'Numéro de disque manquant';

  @override
  String get libraryFilterMetadataMissingArtist => 'Artiste manquant';

  @override
  String get libraryFilterMetadataIncorrectIsrcFormat =>
      'Format ISRC incorrect';

  @override
  String get libraryFilterMetadataMissingLabel => 'Label manquant';

  @override
  String collectionDeletePlaylistsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return 'Supprimer $count $_temp0?';
  }

  @override
  String collectionPlaylistsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'playlists',
      one: 'playlist',
    );
    return '$count $_temp0 supprimées';
  }

  @override
  String collectionAddedTracksToPlaylist(int count, String playlistName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Ajout de $count $_temp0 à $playlistName';
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
      other: 'titres',
      one: 'titre',
    );
    return 'Ajout de $count $_temp0 à $playlistName ($alreadyCount titres déjà présents dans la playlist)';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'éléments',
      one: 'élément',
    );
    return '$count $_temp0';
  }

  @override
  String trackReEnrichSuccessWithFailures(
    int successCount,
    int total,
    int failedCount,
  ) {
    return 'Les métadonnées ont été réenrichies avec succès ($successCount/$total) - Échec : $failedCount';
  }

  @override
  String selectionDeleteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titres',
      one: 'titre',
    );
    return 'Supprimer $count $_temp0';
  }

  @override
  String queueDownloadSpeedStatus(String speed) {
    return 'Téléchargement - $speed Mo/s';
  }

  @override
  String get queueDownloadStarting => 'C\'est parti...';

  @override
  String get a11ySelectTrack => 'Sélectionner une piste';

  @override
  String get a11yDeselectTrack => 'Désélectionner la piste';

  @override
  String a11yPlayTrackByArtist(String trackName, String artistName) {
    return 'Écouter $trackName de $artistName';
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
    return 'Nécessite la version v$version+';
  }

  @override
  String get actionGo => 'Aller';

  @override
  String get logIssueSummary => 'Résumé du problème';

  @override
  String logTotalErrors(int count) {
    return 'Nombre total d\'erreurs : $count';
  }

  @override
  String logAffectedDomains(String domains) {
    return 'Concerne : $domains';
  }

  @override
  String get libraryScanCancelled => 'Analyse annulée';

  @override
  String get libraryScanCancelledSubtitle =>
      'Vous pouvez relancer l\'analyse dès que vous êtes prêt.';

  @override
  String libraryDownloadsHistoryExcluded(int count) {
    return '$count dans l\'historique des téléchargements (exclu de la liste)';
  }

  @override
  String get downloadNativeWorker => 'Tâche de téléchargement native';

  @override
  String get downloadNativeWorkerSubtitle =>
      'Service worker Android en version bêta pour le téléchargement d\'extensions';

  @override
  String get badgeBeta => 'BÊTA';

  @override
  String get extensionServiceStatus => 'État du service';

  @override
  String get extensionServiceHealth => 'Santé du service';

  @override
  String extensionHealthChecksConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vérifications',
      one: 'vérification',
    );
    return '$count $_temp0 configurées';
  }

  @override
  String get extensionOauthConnectHint =>
      'Appuyez sur « Se connecter à Spotify » pour remplir ce champ.';

  @override
  String extensionLastChecked(String time) {
    return 'Dernière vérification à $time';
  }

  @override
  String get extensionRefreshStatus => 'Actualiser l\'état';

  @override
  String get extensionCustomUrlHandling => 'Gestion des URL personnalisées';

  @override
  String get extensionCustomUrlHandlingSubtitle =>
      'Cette extension prend en charge les liens provenant de ces sites';

  @override
  String get extensionCustomUrlHandlingShareHint =>
      'Partagez des liens provenant de ces sites vers SpotiFLAC Mobile et cette extension s\'en chargera.';

  @override
  String extensionSettingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'paramètres',
      one: 'paramètre',
    );
    return '$count $_temp0';
  }

  @override
  String get extensionHealthOnline => 'En ligne';

  @override
  String get extensionHealthDegraded => 'Dégradé';

  @override
  String get extensionHealthOffline => 'Hors ligne';

  @override
  String get extensionHealthNotConfigured => 'Non configuré';

  @override
  String get extensionHealthUnknown => 'Inconnu';

  @override
  String get extensionHealthRequired => 'requis';

  @override
  String get extensionSettingNotSet => 'Non défini';

  @override
  String get extensionActionFailed => 'L\'action a échoué';

  @override
  String get extensionEnterValue => 'Saisir une valeur';

  @override
  String get extensionHealthServiceOnline => 'Service en ligne';

  @override
  String get extensionHealthServiceDegraded => 'Service perturbé';

  @override
  String get extensionHealthServiceOffline => 'Service hors ligne';

  @override
  String get extensionHealthServiceUnknown => 'État du service inconnu';

  @override
  String get audioAnalysisStereo => 'Stéréo';

  @override
  String get audioAnalysisMono => 'Mono';

  @override
  String trackOpenInService(String serviceName) {
    return 'Ouvrir dans $serviceName';
  }

  @override
  String get trackLyricsEmbeddedSource => 'Intégré';

  @override
  String get unknownAlbum => 'Album inconnu';

  @override
  String get unknownArtist => 'Artiste inconnu';

  @override
  String get permissionAudio => 'Audio';

  @override
  String get permissionStorage => 'Stockage';

  @override
  String get permissionNotification => 'Notification';

  @override
  String get errorInvalidFolderSelected => 'Dossier non valide sélectionné';

  @override
  String get errorCouldNotKeepFolderAccess =>
      'Impossible de conserver l\'accès au dossier sélectionné';

  @override
  String get storeAnyVersion => 'N\'importe lequel';

  @override
  String get storeCategoryMetadata => 'Métadonnées';

  @override
  String get storeCategoryDownload => 'Télécharger';

  @override
  String get storeCategoryUtility => 'Utilitaire';

  @override
  String get storeCategoryLyrics => 'Paroles';

  @override
  String get storeCategoryIntegration => 'Intégration';

  @override
  String get artistReleases => 'Sorties';

  @override
  String get editMetadataSelectNone => 'Aucun';

  @override
  String queueRetryAllFailed(int count) {
    return '$count tentatives ont échoué';
  }

  @override
  String get settingsSaveDownloadHistory =>
      'Enregistrer l\'historique des téléchargements';

  @override
  String get settingsSaveDownloadHistorySubtitle =>
      'Conserver les téléchargements terminés dans l\'historique et la bibliothèque';

  @override
  String get dialogDisableHistoryTitle =>
      'Désactiver l\'historique des téléchargements ?';

  @override
  String get dialogDisableHistoryMessage =>
      'L\'historique actuel sera effacé. Les fichiers téléchargés ne seront pas supprimés.';

  @override
  String get dialogDisableAndClear => 'Désactiver et effacer';

  @override
  String get openInOtherServices => 'Ouvrir dans d\'autres services';

  @override
  String get shareSheetNoExtensions => 'Aucun autre service compatible';

  @override
  String get shareSheetNotFound => 'Introuvable';

  @override
  String get shareSheetCopyLink => 'Copier le lien';

  @override
  String shareSheetLinkCopied(Object service) {
    return 'Lien $service copié';
  }
}
