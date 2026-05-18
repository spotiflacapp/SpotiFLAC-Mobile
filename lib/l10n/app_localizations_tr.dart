// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => 'Ana sayfa';

  @override
  String get navLibrary => 'Kitaplığın';

  @override
  String get navSettings => 'Ayarlar';

  @override
  String get navStore => 'Depo';

  @override
  String get homeTitle => 'Ana sayfa';

  @override
  String get homeSubtitle =>
      'Desteklenen bir URL yapıştırın veya isme göre arayın';

  @override
  String get homeEmptyTitle => 'No search providers yet';

  @override
  String get homeEmptySubtitle => 'Install an extension to continue.';

  @override
  String get homeSupports =>
      'Desteklenen linkler: Şarkı, Albüm, Çalma Listesi, Sanatçı linkleri';

  @override
  String get homeRecent => 'En son';

  @override
  String get historyFilterAll => 'Tümü';

  @override
  String get historyFilterAlbums => 'Albümler';

  @override
  String get historyFilterSingles => 'Single\'lar';

  @override
  String get historySearchHint => 'Arama geçmişi...';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get settingsDownload => 'İndirme';

  @override
  String get settingsAppearance => 'Görünüm';

  @override
  String get settingsOptions => 'Seçenekler';

  @override
  String get settingsExtensions => 'Eklentiler';

  @override
  String get settingsAbout => 'Hakkında';

  @override
  String get downloadTitle => 'İndirme';

  @override
  String get downloadAskQualitySubtitle =>
      'Her indirmeden önce kalite seçim ekranını göster';

  @override
  String get downloadFilenameFormat => 'Dosya adı formatı';

  @override
  String get downloadSingleFilenameFormat => 'Single Dosya Adı Formatı';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Single ve EP\'ler için dosya adı örneği. Albüm formatıyla aynı etiketleri kullanır.';

  @override
  String get downloadFolderOrganization => 'Dosya Organizasyonu';

  @override
  String get appearanceTitle => 'Görünüm';

  @override
  String get appearanceThemeSystem => 'Sistem';

  @override
  String get appearanceThemeLight => 'Açık';

  @override
  String get appearanceThemeDark => 'Koyu';

  @override
  String get appearanceDynamicColor => 'Dinamik Renk';

  @override
  String get appearanceDynamicColorSubtitle =>
      'Duvar kağıdının renklerini kullan';

  @override
  String get appearanceHistoryView => 'Geçmiş Düzeni';

  @override
  String get appearanceHistoryViewList => 'Liste';

  @override
  String get appearanceHistoryViewGrid => 'Izgara';

  @override
  String get optionsTitle => 'Seçenekler';

  @override
  String get optionsPrimaryProvider => 'Ana Kaynek';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Şarkı ismi aratılırken kullanılan kaynak.';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Kullanılan eklenti: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Default Search Tab';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Choose which tab opens first for new search results.';

  @override
  String get optionsSwitchBack =>
      'Dahili kaynaklara dönmek için Deezer veya Spotify\'a tıkla';

  @override
  String get optionsAutoFallback => 'Diğerlerini dene';

  @override
  String get optionsAutoFallbackSubtitle =>
      'İndirme başarısız olursa diğer hizmetleri dene';

  @override
  String get optionsUseExtensionProviders => 'Eklenti sağlayıcılarını kullan';

  @override
  String get optionsUseExtensionProvidersOn => 'Eklentiler ilk denenecek';

  @override
  String get optionsUseExtensionProvidersOff =>
      'Sadece dahili sağlayıcıları kullan';

  @override
  String get optionsEmbedLyrics => 'Şarkı Sözlerini Göm';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Senkronize şarkı sözlerini FLAC dosyalarına göm';

  @override
  String get optionsMaxQualityCover => 'En Yüksek Kapak Kalitesi';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'En yüksek kalitedeki albüm kapaklarını indir';

  @override
  String get optionsReplayGain => 'ReplayGain';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Ses yüksekliğini tara ve ReplayGain etiketlerini göm (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Devre dışı: Ses normalleştirme etiketi yok';

  @override
  String get optionsArtistTagMode => 'Sanatçı Etiketi Modu';

  @override
  String get optionsArtistTagModeDescription =>
      'Birden fazla sanatçının gömülü etiketlere nasıl yazılacağını seçin.';

  @override
  String get optionsArtistTagModeJoined => 'Birleşik tek değer';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Maksimum oynatıcı uyumluluğu için \'Sanatçı A, Sanatçı B\' şeklinde tek bir SANATÇI değeri yazın.';

  @override
  String get optionsArtistTagModeSplitVorbis =>
      'FLAC/Opus için ayrılmış etiketler';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'FLAC ve Opus için her sanatçıya ayrı bir etiket yazın; MP3 ve M4A birleşik kalır.';

  @override
  String get optionsConcurrentDownloads => 'Eş Zamanlı İndirmeler';

  @override
  String get optionsConcurrentSequential => 'Sıralı (Birer birer)';

  @override
  String optionsConcurrentParallel(int count) {
    return 'Aynı anda $count indirme';
  }

  @override
  String get optionsConcurrentWarning =>
      'Aynı anda birden fazla indirme sınırlamaya takılabilir';

  @override
  String get optionsExtensionStore => 'Eklenti Deposu';

  @override
  String get optionsExtensionStoreSubtitle =>
      'Gezinme menüsünde Depo sekmesini göster';

  @override
  String get optionsCheckUpdates => 'Güncelleştirmeleri Denetle';

  @override
  String get optionsCheckUpdatesSubtitle => 'Yeni sürüm çıktığında bildir';

  @override
  String get optionsUpdateChannel => 'Güncelleme Kanalı';

  @override
  String get optionsUpdateChannelStable => 'Sadece stabil sürümler';

  @override
  String get optionsUpdateChannelPreview => 'Önizleme sürümlerini al';

  @override
  String get optionsUpdateChannelWarning =>
      'Önizleme sürümleri hatalar veya tamamlanmamış özellikler içerebilir';

  @override
  String get optionsClearHistory => 'İndirme Geçmişini Temizle';

  @override
  String get optionsClearHistorySubtitle =>
      'İndirilen bütün şarkıları geçmişten temizle';

  @override
  String get optionsDetailedLogging => 'Detaylı Günlükleme';

  @override
  String get optionsDetailedLoggingOn => 'Detaylı günlük kayıt ediliyor';

  @override
  String get optionsDetailedLoggingOff => 'Hata bildirmek için aç';

  @override
  String get optionsSpotifyCredentials => 'Spotify Kimlik Bilgileri';

  @override
  String optionsSpotifyCredentialsConfigured(String clientId) {
    return 'Client ID: $clientId...';
  }

  @override
  String get optionsSpotifyCredentialsRequired =>
      'Zorunlu - değiştirmek için tıkla';

  @override
  String get optionsSpotifyWarning =>
      'Spotify\'ın senin API kimlik bilgilerine ihtiyacı var. Onları developer.spotify.com\'dan alabilirsin';

  @override
  String get optionsSpotifyDeprecationWarning =>
      'Spotify API değişiklikleri nedeniyle Spotify araması 3 Mart 2026 tarihinde kullanımdan kaldırılacaktır. Lütfen Deezer\'a geçiş yapın.';

  @override
  String get extensionsTitle => 'Eklentiler';

  @override
  String get extensionsDisabled => 'Devre Dışı';

  @override
  String extensionsVersion(String version) {
    return 'Versiyon $version';
  }

  @override
  String extensionsAuthor(String author) {
    return '$author tarafından';
  }

  @override
  String get extensionsUninstall => 'Kaldır';

  @override
  String get storeTitle => 'Uzantı Deposu';

  @override
  String get storeSearch => 'Eklenti ara...';

  @override
  String get storeInstall => 'Kur';

  @override
  String get storeInstalled => 'Kuruldu';

  @override
  String get storeUpdate => 'Güncelle';

  @override
  String get aboutTitle => 'Hakkında';

  @override
  String get aboutContributors => 'Katkıda Bulunanlar';

  @override
  String get aboutMobileDeveloper => 'Mobil versiyon geliştiricisi';

  @override
  String get aboutOriginalCreator => 'Orijinal SpotiFLAC\'ın kurucusu';

  @override
  String get aboutLogoArtist =>
      'Uygulama logomuzu yaratmış yetenekli sanatçımız!';

  @override
  String get aboutTranslators => 'Çevirmenler';

  @override
  String get aboutSpecialThanks => 'Özel teşekkür';

  @override
  String get aboutLinks => 'Linkler';

  @override
  String get aboutMobileSource => 'Mobil kaynak kodu';

  @override
  String get aboutPCSource => 'PC kaynak kodu';

  @override
  String get aboutKeepAndroidOpen => 'Keep Android Open';

  @override
  String get aboutReportIssue => 'Sorun bildir';

  @override
  String get aboutReportIssueSubtitle =>
      'Karşılaştığın herhangi bir problemi bildir';

  @override
  String get aboutFeatureRequest => 'Özellik isteği';

  @override
  String get aboutFeatureRequestSubtitle =>
      'Uygulama için yeni özellikler isteyin';

  @override
  String get aboutTelegramChannel => 'Telegram Kanalı';

  @override
  String get aboutTelegramChannelSubtitle => 'Duyurular ve güncellemeler';

  @override
  String get aboutTelegramChat => 'Telegram Grubu';

  @override
  String get aboutTelegramChatSubtitle => 'Diğer kullanıcılarla sohbet et';

  @override
  String get aboutSocial => 'Sosyal ağlar';

  @override
  String get aboutApp => 'Uygulama';

  @override
  String get aboutVersion => 'Versiyon';

  @override
  String get aboutBinimumDesc =>
      'QQDL ve HiFi API\'ın kurucusu. Bu API olmadan, Tidal indirmeleri olmazdı!';

  @override
  String get aboutSachinsenalDesc =>
      'Orijinal HiFi projesi kurucusu. Tidal entegrasyonun temeli!';

  @override
  String get aboutSjdonadoDesc =>
      'I Don\'t Have Spotify (IDHS) yaratıcısı. Günü kurtaran yedek bağlantı çözücü!';

  @override
  String get aboutAppDescription =>
      'Search music metadata, manage extensions, and organize your library.';

  @override
  String get artistAlbums => 'Albümler';

  @override
  String get artistSingles => 'Single\'lar ve EP\'ler';

  @override
  String get artistCompilations => 'Derlemeler';

  @override
  String get artistPopular => 'Popüler';

  @override
  String artistMonthlyListeners(String count) {
    return 'Aylık $count dinleyici';
  }

  @override
  String get trackMetadataService => 'Hizmet';

  @override
  String get trackMetadataPlay => 'Oynat';

  @override
  String get trackMetadataShare => 'Paylaş';

  @override
  String get trackMetadataDelete => 'Sil';

  @override
  String get setupGrantPermission => 'İzin Ver';

  @override
  String get setupSkip => 'Şimdilik atla';

  @override
  String get setupStorageAccessRequired => 'Depolama Erişimi Gerekli';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Android 11 ve sonrasında şarkıların seçili klasörünüze kaydedilebilmesi için \"Bütün dosyalara eriş\" iznine ihtiyaç var.';

  @override
  String get setupOpenSettings => 'Ayarları Aç';

  @override
  String get setupPermissionDeniedMessage =>
      'İzin reddedildi. Devam etmek için lütfen bütün izinleri verin.';

  @override
  String setupPermissionRequired(String permissionType) {
    return '$permissionType İzni Zorunlu';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return 'En iyi deneyim için $permissionType izni zorunludur. Bunu ayarlardan daha sonra değiştirebilirsiniz.';
  }

  @override
  String get setupUseDefaultFolder => 'Varsayılan Klasörü Kullan?';

  @override
  String get setupNoFolderSelected =>
      'Klasör seçilmedi. Varsayılan \"Music\" klasörünü kullanmak ister misiniz?';

  @override
  String get setupUseDefault => 'Varsayılanı Kullan';

  @override
  String get setupDownloadLocationTitle => 'İndirme Konumu';

  @override
  String get setupDownloadLocationIosMessage =>
      'iOS\'ta indirilenler uygulamanın \"Documents\" dosyasına kaydedilir. Onlara Dosyalar uygulamasından erişebilirsiniz.';

  @override
  String get setupAppDocumentsFolder => 'Uygulama Belgeler Klasörü';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Tavsiye edilen - Dosyalar uygulamasından erişilebilir';

  @override
  String get setupChooseFromFiles => 'Dosyalar\'dan Seç';

  @override
  String get setupChooseFromFilesSubtitle => 'iCloud veya başka konum seç';

  @override
  String get setupIosEmptyFolderWarning =>
      'iOS\'un sınırlaması: Boş klasörler seçilemiyor. İçinde en az bir dosya bulunan bir klasör seçin.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive desteklenmiyor. Lütfen uygulama Belgeler klasörünü kullanın.';

  @override
  String get setupDownloadInFlac => 'Spotify şarkılarını FLAC olarak indirin';

  @override
  String get setupStorageGranted => 'Depolama İzni Verildi!';

  @override
  String get setupStorageRequired => 'Depolama İzni Gerekli';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC\'ın şarkılarınızı kaydetmek için depolama iznine ihtiyacı var.';

  @override
  String get setupNotificationGranted => 'Bildirim İzni Verildi!';

  @override
  String get setupNotificationEnable => 'Bildirimleri Etkinleştir';

  @override
  String get setupFolderChoose => 'İndirilecek Klasörü Seç';

  @override
  String get setupFolderDescription =>
      'İndirdiğin şarkıların kaydedileceği klasörü seç.';

  @override
  String get setupSelectFolder => 'Klasör Seç';

  @override
  String get setupEnableNotifications => 'Bildirimleri Etkinleştir';

  @override
  String get setupNotificationBackgroundDescription =>
      'İndirmelerin durumu hakkında bildirim al. Bunu açmak uygulama arka plandayken indirmelerinizi takip etmenizi sağlar.';

  @override
  String get setupSkipForNow => 'Şimdilik atla';

  @override
  String get setupNext => 'Sıradaki';

  @override
  String get setupGetStarted => 'Başla';

  @override
  String get setupAllowAccessToManageFiles =>
      'Lütfen bir sonraki ekranda \"Bütün dosyalara eriş\" iznini sağlayın.';

  @override
  String get setupLanguageTitle => 'Choose Language';

  @override
  String get setupLanguageDescription =>
      'Select your preferred language for the app. You can change this later in Settings.';

  @override
  String get setupLanguageSystemDefault => 'System Default';

  @override
  String get dialogCancel => 'İptal';

  @override
  String get dialogSave => 'Kaydet';

  @override
  String get dialogDelete => 'Sil';

  @override
  String get dialogRetry => 'Yeniden dene';

  @override
  String get dialogClear => 'Temizle';

  @override
  String get dialogDone => 'Tamamlandı';

  @override
  String get dialogImport => 'İçe aktar';

  @override
  String get dialogDownload => 'İndir';

  @override
  String get dialogDiscard => 'Vazgeç';

  @override
  String get dialogRemove => 'Kaldır';

  @override
  String get dialogUninstall => 'Kaldır';

  @override
  String get dialogDiscardChanges => 'Değişiklikleri İptal Et?';

  @override
  String get dialogUnsavedChanges =>
      'Kaydedilmeyen değişiklikler mevcut. Bu değişiklikleri iptal etmek istiyor musunuz?';

  @override
  String get dialogClearAll => 'Tümünü Temizle';

  @override
  String get dialogRemoveExtension => 'Eklentiyi Kaldır';

  @override
  String get dialogRemoveExtensionMessage =>
      'Bu eklentiyi kaldırmak istediğine emin misin? Bu işlem geri alınamaz.';

  @override
  String get dialogUninstallExtension => 'Eklentiyi Kaldır?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return '$extensionName eklentisini kaldırmak istediğine emin misin?';
  }

  @override
  String get dialogClearHistoryTitle => 'Geçmişi Temizle';

  @override
  String get dialogClearHistoryMessage =>
      'Tüm indirme geçmişini temizlemek istediğinizden emin misiniz? Bu işlem geri alınamaz.';

  @override
  String get dialogDeleteSelectedTitle => 'Seçileni Sil';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'şarkıyı',
      one: 'şarkıyı',
    );
    return '$count $_temp0 geçmişten silmeye emin misiniz?\n\nBu işlem seçilenleri cihazınızdan da silecektir.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Çalma listesini içe aktar';

  @override
  String dialogImportPlaylistMessage(int count) {
    return 'CSV\'de $count şarkı bulundu. İndirme kuyruğuna ekle?';
  }

  @override
  String csvImportTracks(int count) {
    return 'CSV\'den $count şarkı';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return '\"$trackName\" kuyruğa eklendi';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return '$count şarkı kuyruğa eklendi';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\"$trackName\" zaten indirilmiş';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '\"$trackName\" kitaplığınızda zaten mevcut';
  }

  @override
  String get snackbarHistoryCleared => 'Geçmiş temizlendi';

  @override
  String get snackbarCredentialsSaved => 'Kimlik bilgileri kaydedildi';

  @override
  String get snackbarCredentialsCleared => 'Kimlik bilgileri temizlendi';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'şarkı',
      one: 'şarkı',
    );
    return '$count $_temp0 silindi';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'Dosya açılamadı: $error';
  }

  @override
  String get snackbarFillAllFields => 'Lütfen tüm alanları doldurun';

  @override
  String get snackbarViewQueue => 'Kuyruğu Görüntüle';

  @override
  String snackbarUrlCopied(String platform) {
    return '$platform Bağlantı panoya kopyalandı';
  }

  @override
  String get snackbarFileNotFound => 'Dosya bulunamadı';

  @override
  String get snackbarSelectExtFile => 'Lütfen .spotiflac-ext dosyasını seçin';

  @override
  String get snackbarProviderPrioritySaved => 'Sağlayıcı önceliği kaydedildi';

  @override
  String get snackbarMetadataProviderSaved =>
      'Meta veri sağlayıcı önceliği kaydedildi';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return '$extensionName yüklendi.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName güncellendi.';
  }

  @override
  String get snackbarFailedToInstall => 'Eklenti yüklenirken hata oluştu';

  @override
  String get snackbarFailedToUpdate => 'Eklenti güncellenirken hata oluştu';

  @override
  String get errorRateLimited => 'Aşırı istek gönderildi';

  @override
  String get errorRateLimitedMessage =>
      'Çok fazla istek. Lütfen arama yapmadan önce biraz bekleyin.';

  @override
  String get errorNoTracksFound => 'Parça bulunamadı';

  @override
  String get errorUrlNotRecognized => 'Bağlantı tanınamadı';

  @override
  String get errorUrlNotRecognizedMessage =>
      'Bu bağlantı desteklenmiyor. URL\'nin doğru olduğundan ve uyumlu bir uzantının yüklü olduğundan emin olun.';

  @override
  String get errorUrlFetchFailed =>
      'Bu bağlantıdan içerik yüklenemedi. Lütfen tekrar deneyin.';

  @override
  String errorMissingExtensionSource(String item) {
    return '$item yüklenemedi: Eksik eklenti kaynağı';
  }

  @override
  String get actionPause => 'Duraklat';

  @override
  String get actionResume => 'Devam et';

  @override
  String get actionCancel => 'Vazgeç';

  @override
  String get actionSelectAll => 'Tümünü Seç';

  @override
  String get actionDeselect => 'Seçimi kaldır';

  @override
  String get actionRemoveCredentials => 'Özellikleri kaldır';

  @override
  String get actionSaveCredentials => 'Özellikleri kaydet';

  @override
  String selectionSelected(int count) {
    return '$count seçildi';
  }

  @override
  String get selectionAllSelected => 'Tüm parçalar seçildi';

  @override
  String get selectionSelectToDelete => 'Silinecek parçaları seçin';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Meta verileri alınıyor... $current/$total';
  }

  @override
  String get progressReadingCsv => 'CSV okunuyor...';

  @override
  String get searchSongs => 'Şarkılar';

  @override
  String get searchArtists => 'Sanatçılar';

  @override
  String get searchAlbums => 'Albümler';

  @override
  String get searchPlaylists => 'Çalma Listeleri';

  @override
  String get searchSortTitle => 'Sonuçları Sırala';

  @override
  String get searchSortDefault => 'Varsayılan';

  @override
  String get searchSortTitleAZ => 'Başlık (A-Z)';

  @override
  String get searchSortTitleZA => 'Başlık (Z-A)';

  @override
  String get searchSortArtistAZ => 'Sanatçı (A-Z)';

  @override
  String get searchSortArtistZA => 'Sanatçı (Z-A)';

  @override
  String get searchSortDurationShort => 'Süre (en kısa)';

  @override
  String get searchSortDurationLong => 'Süre (en uzun)';

  @override
  String get searchSortDateOldest => 'Yayın Tarihi (En eski)';

  @override
  String get searchSortDateNewest => 'Yayın Tarihi (En yeni)';

  @override
  String get tooltipPlay => 'Oynat';

  @override
  String get filenameFormat => 'Dosya adı formatı';

  @override
  String get filenameShowAdvancedTags => 'Gelişmiş etiketleri göster';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Parça numarası tamamlama ve tarih desenleri için biçimlendirilmiş etiketleri etkinleştir';

  @override
  String get folderOrganizationNone => 'Organizasyon yok';

  @override
  String get folderOrganizationByPlaylist => 'Çalma Listesine Göre';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Her çalma listesi için ayrı klasör';

  @override
  String get folderOrganizationByArtist => 'Sanatçıya Göre';

  @override
  String get folderOrganizationByAlbum => 'Albüme Göre';

  @override
  String get folderOrganizationByArtistAlbum => 'Sanatçı/Albüm';

  @override
  String get folderOrganizationDescription =>
      'İndirilenleri klasörlerle organize et';

  @override
  String get folderOrganizationNoneSubtitle =>
      'Her şey indirilen dosyasına kaydedilecek';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Her sanatçı için ayrı klasör';

  @override
  String get folderOrganizationByAlbumSubtitle => 'Her albüm için ayrı klasör';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Sanatçı klasörlerinin içinde Albüm klasörleri';

  @override
  String get updateAvailable => 'Güncelleme Mevcut';

  @override
  String get updateLater => 'Daha Sonra';

  @override
  String get updateStartingDownload => 'İndirme başlıyor...';

  @override
  String get updateDownloadFailed => 'İndirme başarısız';

  @override
  String get updateFailedMessage => 'Güncelleme indirilemedi';

  @override
  String get updateNewVersionReady => 'Yeni bir sürüm hazır';

  @override
  String get updateCurrent => 'Şimdiki';

  @override
  String get updateNew => 'Yeni';

  @override
  String get updateDownloading => 'İndiriliyor...';

  @override
  String get updateWhatsNew => 'Yenilikler';

  @override
  String get updateDownloadInstall => 'İndir & Yükle';

  @override
  String get updateDontRemind => 'Bir daha sorma';

  @override
  String get providerPriorityTitle => 'İndirme hizmetleri öncelik sırası';

  @override
  String get providerPriorityDescription =>
      'İndirme hizmetlerini sıralamak için kaydır. Uygulama şarkı indirirken hizmetleri yukarıdan aşağıya doğru deneyecektir.';

  @override
  String get providerPriorityInfo =>
      'Eğer bir şarkı ilk hizmette mevcut değilse uygulama otomatik olarak bir sonrakini deneyecektir.';

  @override
  String get providerPriorityFallbackExtensionsTitle => 'Uzantı Yedeği';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Otomatik yedekleme sırasında hangi yüklü indirme uzantılarının kullanılabileceğini seçin. Yerleşik sağlayıcılar hâlâ yukarıdaki öncelik sırasını takip eder.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Burada yalnızca indirme sağlayıcısı yeteneğine sahip olan ve etkinleştirilmiş uzantılar listelenir.';

  @override
  String get providerBuiltIn => 'Dahili';

  @override
  String get providerExtension => 'Eklenti';

  @override
  String get metadataProviderPriorityTitle => 'Meta Veri Önceliği';

  @override
  String get metadataProviderPriorityDescription =>
      'Meta veri sağlayıcılarını yeniden sıralamak için sürükleyin. Uygulama, parça ararken ve meta verileri alırken sağlayıcıları yukarıdan aşağıya doğru deneyecektir.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer\'da istek sınırı yoktur ve birincil olarak önerilir. Spotify, çok sayıda istekten sonra hız sınırlaması uygulayabilir.';

  @override
  String get metadataNoRateLimits => 'İstek sınırı yok';

  @override
  String get metadataMayRateLimit => 'Hız sınırlaması uygulanabilir';

  @override
  String get logTitle => 'Kayıtlar';

  @override
  String get logCopied => 'Kayıtlar panoya kopyalandı';

  @override
  String get logSearchHint => 'Kayıtları Ara...';

  @override
  String get logFilterLevel => 'Seviye';

  @override
  String get logFilterSection => 'Filtre';

  @override
  String get logShareLogs => 'Kayıtları paylaş';

  @override
  String get logClearLogs => 'Kayıtları temizle';

  @override
  String get logClearLogsTitle => 'Kayıtları temizle';

  @override
  String get logClearLogsMessage =>
      'Tüm kayıtları temizlemek istediğinize emin misiniz?';

  @override
  String get logFilterBySeverity => 'Günlükleri önem derecesine göre filtrele';

  @override
  String get logNoLogsYet => 'Henüz kayıt yok';

  @override
  String get logNoLogsYetSubtitle =>
      'Uygulamayı kullandıkça günlükler burada görünecektir';

  @override
  String logEntriesFiltered(int count) {
    return 'Kayıtlar ($count filtrelendi)';
  }

  @override
  String logEntries(int count) {
    return 'Kayıtlar ($count)';
  }

  @override
  String get credentialsTitle => 'Spotify Kimlik Bilgileri';

  @override
  String get credentialsDescription =>
      'Kendi Spotify uygulama kotanızı kullanmak için Client ID ve Secret girin.';

  @override
  String get credentialsClientId => 'Client ID';

  @override
  String get credentialsClientIdHint => 'Client ID yapıştır';

  @override
  String get credentialsClientSecret => 'Client Secret';

  @override
  String get credentialsClientSecretHint => 'Client Secret yapıştır';

  @override
  String get channelStable => 'Kararlı';

  @override
  String get channelPreview => 'Önizleme';

  @override
  String get sectionSearchSource => 'Arama Kaynağı';

  @override
  String get sectionDownload => 'İndir';

  @override
  String get sectionPerformance => 'Performans';

  @override
  String get sectionApp => 'Uygulama';

  @override
  String get sectionData => 'Veri';

  @override
  String get sectionDebug => 'Hata ayıklama';

  @override
  String get sectionService => 'Servis';

  @override
  String get sectionAudioQuality => 'Ses Kalitesi';

  @override
  String get sectionFileSettings => 'Dosya Ayarları';

  @override
  String get sectionLyrics => 'Şarkı sözleri';

  @override
  String get lyricsMode => 'Şarkı Sözü Modu';

  @override
  String get lyricsModeDescription =>
      'Şarkı sözlerinin indirmelerinizle birlikte nasıl kaydedileceğini seçin';

  @override
  String get lyricsModeEmbed => 'Dosyaya göm';

  @override
  String get lyricsModeEmbedSubtitle =>
      'Şarkı sözleri FLAC meta verilerinin içinde saklanır';

  @override
  String get lyricsModeExternal => 'Harici .lrc dosyası';

  @override
  String get lyricsModeExternalSubtitle =>
      'Samsung Music gibi oynatıcılar için ayrı .lrc dosyası';

  @override
  String get lyricsModeBoth => 'Her ikisi de';

  @override
  String get lyricsModeBothSubtitle =>
      'Hem göm hem de .lrc dosyası olarak kaydet';

  @override
  String get sectionColor => 'Renk';

  @override
  String get sectionTheme => 'Tema';

  @override
  String get sectionLayout => 'Düzen';

  @override
  String get sectionLanguage => 'Dil';

  @override
  String get appearanceLanguage => 'Uygulama Dili';

  @override
  String get settingsAppearanceSubtitle => 'Tema, renkler, görünüm';

  @override
  String get settingsDownloadSubtitle => 'Servis, kalite, dosya adı formatı';

  @override
  String get settingsOptionsSubtitle =>
      'Yedekleme, sözler, kapak resmi, güncellemeler';

  @override
  String get settingsExtensionsSubtitle => 'İndirme sağlayıcılarını yönet';

  @override
  String get settingsLogsSubtitle =>
      'Hata ayıklama için uygulama günlüklerini görüntüle';

  @override
  String get loadingSharedLink => 'Paylaşılan bağlantı yükleniyor...';

  @override
  String get pressBackAgainToExit => 'Çıkmak için tekrar geri basın';

  @override
  String downloadAllCount(int count) {
    return 'Tümünü İndir ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parça',
      one: '1 parça',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Dosya yolunu kopyala';

  @override
  String get trackRemoveFromDevice => 'Cihazdan kaldır';

  @override
  String get trackLoadLyrics => 'Şarkı Sözlerini Yükle';

  @override
  String get trackMetadata => 'Meta Veri';

  @override
  String get trackFileInfo => 'Dosya Bilgisi';

  @override
  String get trackLyrics => 'Şarkı Sözleri';

  @override
  String get trackFileNotFound => 'Dosya bulunamadı';

  @override
  String get trackOpenInDeezer => 'Deezer\'da aç';

  @override
  String get trackOpenInSpotify => 'Spotify\'da aç';

  @override
  String get trackTrackName => 'Parça adı';

  @override
  String get trackArtist => 'Sanatçı';

  @override
  String get trackAlbumArtist => 'Albüm sanatçısı';

  @override
  String get trackAlbum => 'Albüm';

  @override
  String get trackTrackNumber => 'Parça numarası';

  @override
  String get trackDiscNumber => 'Disk numarası';

  @override
  String get trackDuration => 'Süre';

  @override
  String get trackAudioQuality => 'Ses kalitesi';

  @override
  String get trackReleaseDate => 'Yayın tarihi';

  @override
  String get trackGenre => 'Tür';

  @override
  String get trackLabel => 'Etiket / Müzik Şirketi';

  @override
  String get trackCopyright => 'Telif Hakkı';

  @override
  String get trackDownloaded => 'İndirildi';

  @override
  String get trackCopyLyrics => 'Şarkı sözlerini kopyala';

  @override
  String trackLyricsSource(String source) {
    return 'Source: $source';
  }

  @override
  String get trackLyricsNotAvailable => 'Bu parça için şarkı sözü mevcut değil';

  @override
  String get trackLyricsNotInFile => 'Bu dosyada şarkı sözü bulunamadı';

  @override
  String get trackFetchOnlineLyrics => 'İnternetten Getir';

  @override
  String get trackLyricsTimeout =>
      'İstek zaman aşımına uğradı. Daha sonra tekrar deneyin.';

  @override
  String get trackLyricsLoadFailed => 'Şarkı sözleri yüklenemedi';

  @override
  String get trackEmbedLyrics => 'Şarkı Sözlerini Göm';

  @override
  String get trackLyricsEmbedded => 'Şarkı sözleri başarıyla gömüldü';

  @override
  String get trackInstrumental => 'Enstrümantal parça';

  @override
  String get trackCopiedToClipboard => 'Panoya kopyalandı';

  @override
  String get trackDeleteConfirmTitle => 'Cihazdan kaldırılsın mı?';

  @override
  String get trackDeleteConfirmMessage =>
      'Bu işlem, indirilen dosyayı kalıcı olarak silecek ve geçmişinizden kaldıracaktır.';

  @override
  String get dateToday => 'Bugün';

  @override
  String get dateYesterday => 'Dün';

  @override
  String dateDaysAgo(int count) {
    return '$count gün önce';
  }

  @override
  String dateWeeksAgo(int count) {
    return '$count hafta önce';
  }

  @override
  String dateMonthsAgo(int count) {
    return '$count ay önce';
  }

  @override
  String get storeFilterAll => 'Tümü';

  @override
  String get storeFilterMetadata => 'Meta Veri';

  @override
  String get storeFilterDownload => 'İndir';

  @override
  String get storeFilterUtility => 'Araç';

  @override
  String get storeFilterLyrics => 'Şarkı Sözleri';

  @override
  String get storeFilterIntegration => 'Entegrasyon';

  @override
  String get storeClearFilters => 'Filtreleri temizle';

  @override
  String get storeAddRepoTitle => 'Uzantı Deposu Ekle';

  @override
  String get storeAddRepoDescription =>
      'Uzantılara göz atmak ve yüklemek için registry.json dosyası içeren bir GitHub depo URL\'si girin.';

  @override
  String get storeRepoUrlLabel => 'Depo URL\'si';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeRepoUrlHelper =>
      'örn. https://github.com/user/extensions-repo';

  @override
  String get storeAddRepoButton => 'Depo Ekle';

  @override
  String get storeChangeRepoTooltip => 'Depoyu değiştir';

  @override
  String get storeRepoDialogTitle => 'Uzantı Deposu';

  @override
  String get storeRepoDialogCurrent => 'Mevcut depo:';

  @override
  String get storeNewRepoUrlLabel => 'Yeni Depo URL\'si';

  @override
  String get storeLoadError => 'Depo yüklenemedi';

  @override
  String get storeEmptyNoExtensions => 'Uygun uzantı yok';

  @override
  String get storeEmptyNoResults => 'Uzantı bulunamadı';

  @override
  String get extensionDefaultProvider => 'Varsayılan (Deezer)';

  @override
  String get extensionDefaultProviderSubtitle => 'Yerleşik aramayı kullan';

  @override
  String get extensionAuthor => 'Oluşturan';

  @override
  String get extensionId => 'ID';

  @override
  String get extensionError => 'Hata';

  @override
  String get extensionCapabilities => 'Özellikler';

  @override
  String get extensionMetadataProvider => 'Meta Veri Sağlayıcı';

  @override
  String get extensionDownloadProvider => 'İndirme Sağlayıcı';

  @override
  String get extensionLyricsProvider => 'Şarkı Sözü Sağlayıcı';

  @override
  String get extensionUrlHandler => 'URL İşleyici';

  @override
  String get extensionQualityOptions => 'Kalite Seçenekleri';

  @override
  String get extensionPostProcessingHooks => 'Son İşlem Kancaları';

  @override
  String get extensionPermissions => 'İzinler';

  @override
  String get extensionSettings => 'Ayarlar';

  @override
  String get extensionRemoveButton => 'Uzantıyı Kaldır';

  @override
  String get extensionUpdated => 'Güncellendi';

  @override
  String get extensionMinAppVersion => 'Minimum Uygulama Sürümü';

  @override
  String get extensionCustomTrackMatching => 'Özel Parça Eşleştirme';

  @override
  String get extensionPostProcessing => 'Son İşlem';

  @override
  String extensionHooksAvailable(int count) {
    return '$count kanca kullanılabilir';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count desen';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Strateji: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => 'Sağlayıcı Önceliği';

  @override
  String get extensionsInstalledSection => 'Kurulu uzantılar';

  @override
  String get extensionsNoExtensions => 'Hiçbir eklenti kurulmamış';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Yeni sağlayıcılar eklemek için .spotiflac-ext dosyalarını yükleyin';

  @override
  String get extensionsInstallButton => 'Uzantı Yükle';

  @override
  String get extensionsInfoTip =>
      'Uzantılar yeni meta veri ve indirme sağlayıcıları ekleyebilir. Yalnızca güvenilir kaynaklardan gelen uzantıları yükleyin.';

  @override
  String get extensionsInstalledSuccess => 'Uzantı başarıyla yüklendi';

  @override
  String extensionsInstalledCount(int count) {
    return '$count extensions installed successfully';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return 'Installed $installed of $attempted extensions';
  }

  @override
  String get extensionsDownloadPriority => 'İndirme Önceliği';

  @override
  String get extensionsDownloadPrioritySubtitle =>
      'İndirme servisi sırasını ayarla';

  @override
  String get extensionsFallbackTitle => 'Yedekleme Uzantıları';

  @override
  String get extensionsFallbackSubtitle =>
      'Hangi yüklü indirme uzantılarının yedekleme olarak kullanılabileceğini seçin';

  @override
  String get extensionsNoDownloadProvider =>
      'İndirme sağlayıcısı olan uzantı yok';

  @override
  String get extensionsMetadataPriority => 'Meta Veri Önceliği';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Arama ve meta veri kaynağı sırasını ayarla';

  @override
  String get extensionsNoMetadataProvider =>
      'Meta veri sağlayıcısı içeren uzantı bulunamadı';

  @override
  String get extensionsSearchProvider => 'Arama Sağlayıcısı';

  @override
  String get extensionsNoCustomSearch => 'Özel arama içeren uzantı bulunamadı';

  @override
  String get extensionsSearchProviderDescription =>
      'Parça aramak için hangi servisin kullanılacağını seçin';

  @override
  String get extensionsCustomSearch => 'Özel arama';

  @override
  String get extensionsErrorLoading => 'Uzantı yüklenirken hata oluştu';

  @override
  String get qualityFlacLossless => 'FLAC Kayıpsız';

  @override
  String get qualityFlacLosslessSubtitle => '16-bit / 44.1kHz';

  @override
  String get qualityHiResFlac => 'Hi-Res FLAC';

  @override
  String get qualityHiResFlacSubtitle => '24-bit / 96kHz\'e kadar';

  @override
  String get qualityHiResFlacMax => 'Hi-Res FLAC Max';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-bit / 192kHz\'e kadar';

  @override
  String get downloadLossy320 => 'Kayıplı 320kbps';

  @override
  String get downloadLossyFormat => 'Kayıplı Format';

  @override
  String get downloadLossy320Format => 'Kayıplı 320kbps Formatı';

  @override
  String get downloadLossy320FormatDesc =>
      'Tidal 320kbps kayıplı indirmeler için çıktı formatını seçin. Orijinal AAC akışı seçtiğiniz formata dönüştürülecektir.';

  @override
  String get downloadLossyMp3 => 'MP3 320kbps';

  @override
  String get downloadLossyMp3Subtitle =>
      'En iyi uyumluluk, parça başına ~10 Mb';

  @override
  String get downloadLossyAac => 'AAC/M4A 320kbps';

  @override
  String get downloadLossyAacSubtitle =>
      'Best mobile compatibility, M4A container';

  @override
  String get downloadLossyOpus256 => 'Opus 256kbps';

  @override
  String get downloadLossyOpus256Subtitle =>
      'En iyi Opus kalitesi, parça başına ~8 Mb';

  @override
  String get downloadLossyOpus128 => 'Opus 128kbps';

  @override
  String get downloadLossyOpus128Subtitle =>
      'En küçük boyut, parça başına ~4 Mb';

  @override
  String get qualityNote =>
      'Gerçek kalite, parçanın servisteki uygunluğuna bağlıdır';

  @override
  String get downloadAskBeforeDownload => 'İndirmeden Önce Sor';

  @override
  String get downloadDirectory => 'İndirme Dizini';

  @override
  String get downloadSeparateSinglesFolder => 'Ayrı Single Klasörü';

  @override
  String get downloadAlbumFolderStructure => 'Albüm Klasör Yapısı';

  @override
  String get downloadUseAlbumArtistForFolders =>
      'Klasörler için Albüm Sanatçısı\'nı kullan';

  @override
  String get downloadUsePrimaryArtistOnly =>
      'Klasörler için yalnızca birincil sanatçıyı kullan';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Düet sanatçıları klasör adından kaldırılır (örn. Justin Bieber, Quavo → Justin Bieber)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Klasör adı için tam sanatçı dizesi kullanılır';

  @override
  String get downloadSelectQuality => 'Kalite seçin';

  @override
  String get downloadFrom => 'İndirme Kaynağı';

  @override
  String get appearanceAmoledDark => 'AMOLED Koyu';

  @override
  String get appearanceAmoledDarkSubtitle => 'Saf siyah arka plan';

  @override
  String get queueClearAll => 'Tümünü Temizle';

  @override
  String get queueClearAllMessage =>
      'Tüm indirmeleri temizlemek istediğinizden emin misiniz?';

  @override
  String get settingsAutoExportFailed =>
      'Başarısız indirmeleri otomatik dışa aktar';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Başarısız indirmeleri otomatik olarak TXT dosyasına kaydet';

  @override
  String get settingsDownloadNetwork => 'İndirme Ağı';

  @override
  String get settingsDownloadNetworkAny => 'WiFi + Mobil Veri';

  @override
  String get settingsDownloadNetworkWifiOnly => 'Yalnızca WiFi';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'İndirmeler için hangi ağın kullanılacağını seçin. Yalnızca WiFi olarak ayarlandığında, mobil veriye geçildiğinde indirmeler duraklatılır.';

  @override
  String get albumFolderArtistAlbum => 'Sanatçı / Albüm';

  @override
  String get albumFolderArtistAlbumSubtitle =>
      'Albümler/Sanatçı Adı/Albüm Adı/';

  @override
  String get albumFolderArtistYearAlbum => 'Sanatçı / [Yıl] Albüm';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Albümler/Sanatçı Adı/[2005] Albüm Adı/';

  @override
  String get albumFolderAlbumOnly => 'Yalnızca Albüm';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Albümler/Albüm Adı/';

  @override
  String get albumFolderYearAlbum => '[Yıl] Albüm';

  @override
  String get albumFolderYearAlbumSubtitle => 'Albümler/[2005] Albüm Adı/';

  @override
  String get albumFolderArtistAlbumSingles => 'Sanatçı / Albüm + Singlelar';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Sanatçı/Albüm/ ve Sanatçı/Singlelar/';

  @override
  String get albumFolderArtistAlbumFlat =>
      'Sanatçı / Albüm (Singlelar alt klasörsüz)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Sanatçı/Albüm/ ve Sanatçı/şarkı.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Seçilenleri Sil';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'parça',
      one: 'parça',
    );
    return 'Bu albümden $count $_temp0 parça silinsin mi?\n\nBu işlem dosyaları depolama alanından da kalıcı olarak silecektir.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return '$count seçildi';
  }

  @override
  String get downloadedAlbumAllSelected => 'Tüm parçalar seçildi';

  @override
  String get downloadedAlbumTapToSelect => 'Seçmek için parçalara dokunun';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'parçayı',
      one: 'parçayı',
    );
    return '$count $_temp0 sil';
  }

  @override
  String get downloadedAlbumSelectToDelete => 'Silinecek parçaları seçin';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Disk $discNumber';
  }

  @override
  String get recentTypeArtist => 'Sanatçı';

  @override
  String get recentTypeAlbum => 'Albüm';

  @override
  String get recentTypeSong => 'Şarkı';

  @override
  String get recentTypePlaylist => 'Çalma Listesi';

  @override
  String get recentEmpty => 'Henüz son kullanılan öğe yok';

  @override
  String get recentShowAllDownloads => 'Tüm İndirmeleri Göster';

  @override
  String recentPlaylistInfo(String name) {
    return 'Çalma Listesi: $name';
  }

  @override
  String get discographyDownload => 'Diskografiyi İndir';

  @override
  String get discographyDownloadAll => 'Tümünü İndir';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$albumCount yayından $count parça';
  }

  @override
  String get discographyAlbumsOnly => 'Yalnızca Albümler';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$albumCount albümden $count parça';
  }

  @override
  String get discographySinglesOnly => 'Yalnızca Single\'lar ve EP\'ler';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$albumCount tekliden $count parça';
  }

  @override
  String get discographySelectAlbums => 'Albümleri Seç...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Belirli albümleri veya single\'ları seçin';

  @override
  String get discographyFetchingTracks => 'Parçalar getiriliyor...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return '$total üzerinden $current getiriliyor...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count seçildi';
  }

  @override
  String get discographyDownloadSelected => 'Seçilenleri İndir';

  @override
  String discographyAddedToQueue(int count) {
    return '$count parça kuyruğa eklendi';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added eklendi, $skipped zaten indirilmiş';
  }

  @override
  String get discographyNoAlbums => 'Kullanılabilir albüm yok';

  @override
  String get discographyFailedToFetch => 'Bazı albümler getirilemedi';

  @override
  String get sectionStorageAccess => 'Depolama Erişimi';

  @override
  String get allFilesAccess => 'Tüm Dosyalara Erişim';

  @override
  String get allFilesAccessEnabledSubtitle => 'Herhangi bir klasöre yazabilir';

  @override
  String get allFilesAccessDisabledSubtitle =>
      'Yalnızca medya klasörleriyle sınırlı';

  @override
  String get allFilesAccessDescription =>
      'Özel klasörlere kaydederken yazma hatalarıyla karşılaşırsanız bunu etkinleştirin. Android 13 ve üzeri, varsayılan olarak belirli dizinlere erişimi kısıtlar.';

  @override
  String get allFilesAccessDeniedMessage =>
      'İzin reddedildi. Lütfen sistem ayarlarından \'Tüm dosyalara erişim\' iznini manuel olarak etkinleştirin.';

  @override
  String get allFilesAccessDisabledMessage =>
      'Tüm Dosyalara Erişim devre dışı bırakıldı. Uygulama kısıtlı depolama erişimi kullanacak.';

  @override
  String get settingsLocalLibrary => 'Yerel Kitaplık';

  @override
  String get settingsLocalLibrarySubtitle =>
      'Müziği tara ve kopyaları tespit et';

  @override
  String get settingsCache => 'Depolama ve Önbellek';

  @override
  String get settingsCacheSubtitle =>
      'Boyutu görüntüle ve önbelleğe alınmış verileri temizle';

  @override
  String get libraryTitle => 'Yerel Kitaplık';

  @override
  String get libraryScanSettings => 'Tarama Ayarları';

  @override
  String get libraryEnableLocalLibrary => 'Yerel Kitaplığı Etkinleştir';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Mevcut müziğinizi tarayın ve takip edin';

  @override
  String get libraryFolder => 'Kitaplık Klasörü';

  @override
  String get libraryFolderHint => 'Klasör seçmek için dokunun';

  @override
  String get libraryShowDuplicateIndicator => 'Kopya Belirtecini Göster';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Mevcut parçalar aranırken göster';

  @override
  String get libraryAutoScan => 'Otomatik Tarama';

  @override
  String get libraryAutoScanSubtitle =>
      'Kitaplığınızı yeni dosyalar için otomatik olarak tarayın';

  @override
  String get libraryAutoScanOff => 'Kapalı';

  @override
  String get libraryAutoScanOnOpen => 'Her uygulama açılışında';

  @override
  String get libraryAutoScanDaily => 'Günlük';

  @override
  String get libraryAutoScanWeekly => 'Haftalık';

  @override
  String get libraryActions => 'Eylemler';

  @override
  String get libraryScan => 'Kitaplığı Tara';

  @override
  String get libraryScanSubtitle => 'Ses dosyaları için tara';

  @override
  String get libraryScanSelectFolderFirst => 'Önce bir klasör seçin';

  @override
  String get libraryCleanupMissingFiles => 'Eksik Dosyaları Temizle';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Eski dosya kalıntılarını temizleyin';

  @override
  String get libraryClear => 'Kitaplığı temizle';

  @override
  String get libraryClearSubtitle => 'Taranan tüm parçaları sil';

  @override
  String get libraryClearConfirmTitle => 'Kütüphaneyi temizle';

  @override
  String get libraryClearConfirmMessage =>
      'Bu işlem, kitaplığınızdaki tüm taranmış parçaları siler. Asıl müzik dosyalarınız silinmez.';

  @override
  String get libraryAbout => 'Yerel Kütüphane Hakkında';

  @override
  String get libraryAboutDescription =>
      'İndirme işlemi sırasında mevcut müzik koleksiyonunuzu tarayarak yinelenen dosyaları tespit eder. FLAC, M4A, MP3, Opus ve OGG formatlarını destekler. Varsa, meta veriler dosya etiketlerinden okunur.';

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
  String get libraryFilterTitle => 'Filtreler';

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
      'En sevdiğiniz müzikleri kayıpsız kalitede nasıl indirebileceğinizi öğrenelim. Bu kısa eğitim size temel bilgileri gösterecek.';

  @override
  String get tutorialWelcomeTip1 =>
      'Spotify, Deezer\'dan müzik indirin veya desteklenen herhangi bir URL\'yi yapıştırın';

  @override
  String get tutorialWelcomeTip2 =>
      'Tidal, Qobuz veya Deezer\'dan FLAC kalitesinde ses alın';

  @override
  String get tutorialWelcomeTip3 =>
      'Otomatik meta veri, kapak resmi ve şarkı sözü gömme';

  @override
  String get tutorialSearchTitle => 'Müzik Bulma';

  @override
  String get tutorialSearchDesc =>
      'İndirmek istediğiniz müziği bulmanın iki kolay yolu vardır.';

  @override
  String get tutorialDownloadTitle => 'Müzik İndirme';

  @override
  String get tutorialDownloadDesc =>
      'Müzik indirmek basit ve hızlıdır. İşte nasıl çalıştığı.';

  @override
  String get tutorialLibraryTitle => 'Kitaplığınız';

  @override
  String get tutorialLibraryDesc =>
      'İndirdiğiniz tüm müzikler Kitaplık sekmesinde düzenlenir.';

  @override
  String get tutorialLibraryTip1 =>
      'Kitaplık sekmesinden indirme ilerlemesini ve kuyruğu görüntüleyin';

  @override
  String get tutorialLibraryTip2 =>
      'Müzik çalarınızla oynatmak için herhangi bir parçaya dokunun';

  @override
  String get tutorialLibraryTip3 =>
      'Daha iyi göz atmak için liste ve ızgara görünümü arasında geçiş yapın';

  @override
  String get tutorialExtensionsTitle => 'Uzantılar';

  @override
  String get tutorialExtensionsDesc =>
      'Topluluk uzantılarıyla uygulamanın yeteneklerini artırın.';

  @override
  String get tutorialExtensionsTip1 =>
      'Faydalı uzantıları keşfetmek için Depo sekmesine göz atın';

  @override
  String get tutorialExtensionsTip2 =>
      'Yeni indirme sağlayıcıları veya arama kaynakları ekleyin';

  @override
  String get tutorialExtensionsTip3 =>
      'Şarkı sözleri, gelişmiş meta veriler ve daha fazla özellik edinin';

  @override
  String get tutorialSettingsTitle => 'Deneyiminizi Özelleştirin';

  @override
  String get tutorialSettingsDesc =>
      'Uygulamayı Ayarlar\'dan tercihlerinize göre kişiselleştirin.';

  @override
  String get tutorialSettingsTip1 =>
      'İndirme konumunu ve klasör düzenini değiştirin';

  @override
  String get tutorialSettingsTip2 =>
      'Varsayılan ses kalitesi ve format tercihlerini ayarlayın';

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
  String get trackSaveCoverArtSubtitle => 'Save album art as .jpg file';

  @override
  String get trackSaveLyrics => 'Save Lyrics (.lrc)';

  @override
  String get trackSaveLyricsSubtitle => 'Fetch and save lyrics as .lrc file';

  @override
  String get trackSaveLyricsProgress => 'Saving lyrics...';

  @override
  String get trackReEnrich => 'Re-enrich';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Search metadata online and embed into file';

  @override
  String get trackReEnrichFieldsTitle => 'Fields to update';

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
  String queueFlacFindingProgress(int current, int total) {
    return 'Finding FLAC matches... ($current/$total)';
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
  String get trackConvertFormatSubtitle =>
      'Convert to MP3, Opus, ALAC, or FLAC';

  @override
  String get trackConvertTitle => 'Convert Audio';

  @override
  String get trackConvertTargetFormat => 'Target Format';

  @override
  String get trackConvertBitrate => 'Bitrate';

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
  String get cueSplitSubtitle => 'Split CUE+FLAC into individual tracks';

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
  String get collectionPlaylists => 'Playlists';

  @override
  String get collectionPlaylist => 'Playlist';

  @override
  String get collectionAddToPlaylist => 'Add to playlist';

  @override
  String get collectionCreatePlaylist => 'Create playlist';

  @override
  String get collectionNoPlaylistsYet => 'No playlists yet';

  @override
  String get collectionNoPlaylistsSubtitle =>
      'Create a playlist to start categorizing tracks';

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
  String get collectionPlaylistCreated => 'Playlist created';

  @override
  String get collectionPlaylistNameHint => 'Playlist name';

  @override
  String get collectionPlaylistNameRequired => 'Playlist name is required';

  @override
  String get collectionRenamePlaylist => 'Rename playlist';

  @override
  String get collectionDeletePlaylist => 'Delete playlist';

  @override
  String collectionDeletePlaylistMessage(String playlistName) {
    return 'Delete \"$playlistName\" and all tracks inside it?';
  }

  @override
  String get collectionPlaylistDeleted => 'Playlist deleted';

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
  String collectionRemoved(String trackName) {
    return '\"$trackName\" removed';
  }

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
  String get trackOptionGoToAlbum => 'Go to Album';

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
  String selectionBatchConvertProgress(int current, int total) {
    return 'Converting $current of $total...';
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
      'Artist folders use Album Artist when available';

  @override
  String get downloadUseAlbumArtistForFoldersTrackSubtitle =>
      'Artist folders use Track Artist only';

  @override
  String get lyricsProvidersTitle => 'Lyrics Providers';

  @override
  String get lyricsProvidersDescription =>
      'Enable, disable and reorder lyrics sources. Providers are tried top-to-bottom until lyrics are found.';

  @override
  String get lyricsProvidersInfoText =>
      'Extension lyrics providers always run before built-in providers. At least one provider must remain enabled.';

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
  String get settingsDonate => 'Donate';

  @override
  String get settingsDonateSubtitle => 'Support SpotiFLAC-Mobile development';

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
      'Choose storage mode for downloaded files.';

  @override
  String get storageModeAppFolder => 'App folder (non-SAF)';

  @override
  String get storageModeAppFolderSubtitle => 'Use default Music/SpotiFLAC path';

  @override
  String get storageModeSaf => 'SAF folder';

  @override
  String get storageModeSafSubtitle =>
      'Pick folder via Android Storage Access Framework';

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
    return 'Customize how your files are named.';
  }

  @override
  String get downloadFilenameInsertTag => 'Tap to insert tag:';

  @override
  String get downloadSeparateSinglesEnabled => 'Albums/ and Singles/ folders';

  @override
  String get downloadSeparateSinglesDisabled => 'All files in same structure';

  @override
  String get downloadArtistNameFilters => 'Artist Name Filters';

  @override
  String get downloadCreatePlaylistSourceFolder =>
      'Create playlist source folder';

  @override
  String get downloadCreatePlaylistSourceFolderEnabled =>
      'Playlist downloads use Playlist/ plus your normal folder structure.';

  @override
  String get downloadCreatePlaylistSourceFolderDisabled =>
      'Playlist downloads use the normal folder structure only.';

  @override
  String get downloadCreatePlaylistSourceFolderRedundant =>
      'By Playlist already places downloads inside a playlist folder.';

  @override
  String get downloadSongLinkRegion => 'SongLink Region';

  @override
  String get downloadNetworkCompatibilityMode => 'Network compatibility mode';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Enabled: try HTTP + accept invalid TLS certificates (unsafe)';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Off: strict HTTPS certificate validation (recommended)';

  @override
  String get downloadSelectServiceToEnable =>
      'Select a built-in service to enable';

  @override
  String get downloadSelectTidalQobuz =>
      'Select Tidal or Qobuz above to configure quality';

  @override
  String get downloadEmbedLyricsDisabled =>
      'Disabled while Embed Metadata is turned off';

  @override
  String get downloadNeteaseIncludeTranslation =>
      'Netease: Include Translation';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Append translated lyrics when available';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Use original lyrics only';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease: Include Romanization';

  @override
  String get downloadNeteaseIncludeRomanizationEnabled =>
      'Append romanized lyrics when available';

  @override
  String get downloadNeteaseIncludeRomanizationDisabled => 'Disabled';

  @override
  String get downloadAppleQqMultiPerson => 'Apple/QQ Multi-Person Word-by-Word';

  @override
  String get downloadAppleQqMultiPersonEnabled =>
      'Enable v1/v2 speaker and [bg:] tags';

  @override
  String get downloadAppleQqMultiPersonDisabled =>
      'Simplified word-by-word formatting';

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
  String get downloadMusixmatchLanguageAuto => 'Auto (original)';

  @override
  String get downloadFilterContributing =>
      'Filter contributing artists in Album Artist';

  @override
  String get downloadFilterContributingEnabled =>
      'Album Artist metadata uses primary artist only';

  @override
  String get downloadFilterContributingDisabled =>
      'Keep full Album Artist metadata value';

  @override
  String get downloadProvidersNoneEnabled => 'None enabled';

  @override
  String get downloadMusixmatchLanguageCode => 'Language code';

  @override
  String get downloadMusixmatchLanguageHint => 'auto / en / es / ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Set preferred language code (example: en, es, ja). Leave empty for auto.';

  @override
  String get downloadMusixmatchAuto => 'Auto';

  @override
  String get downloadNetworkAnySubtitle => 'WiFi + Mobile Data';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Pause downloads on mobile data';

  @override
  String get downloadSongLinkRegionDesc =>
      'Used as userCountry for SongLink API lookup.';

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
  String get queueDownloadedHeader => 'Downloaded';

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
  String get audioAnalysisChannelStats => 'Per-channel Stats';

  @override
  String get audioAnalysisSamples => 'Samples';

  @override
  String get audioAnalysisRescan => 'Re-analyze';

  @override
  String get audioAnalysisRescanning => 'Re-analyzing audio...';

  @override
  String extensionsSearchWith(String providerName) {
    return 'Search with $providerName';
  }

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
  String get sortAlphaAsc => 'A-Z';

  @override
  String get sortAlphaDesc => 'Z-A';

  @override
  String get cancelDownloadTitle => 'Cancel download?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'This will cancel the active download for \"$trackName\".';
  }

  @override
  String get cancelDownloadKeep => 'Keep';

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
  String get errorLoadAlbum => 'Failed to load album';

  @override
  String get errorLoadPlaylist => 'Failed to load playlist';

  @override
  String get errorLoadArtist => 'Failed to load artist';

  @override
  String get notifChannelDownloadName => 'Download Progress';

  @override
  String get notifChannelDownloadDesc => 'Shows download progress for tracks';

  @override
  String get notifChannelLibraryScanName => 'Library Scan';

  @override
  String get notifChannelLibraryScanDesc => 'Shows local library scan progress';

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
  String get homeImportCsvTooltip => 'Import CSV';

  @override
  String get homeChangeSearchProviderTooltip => 'Change search provider';

  @override
  String get actionPaste => 'Paste';

  @override
  String get searchTracksHint => 'Search tracks...';

  @override
  String get searchTracksEmptyPrompt => 'Search for tracks';

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
  String get optionsMaxQualityCoverSubtitleDisabled =>
      'Disabled when metadata embedding is off';

  @override
  String downloadFilenameHintExample(Object artist, Object title) {
    return '$artist - $title';
  }

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
  String get actionStop => 'Stop';

  @override
  String get queueFinalizingDownload => 'Finalizing download';

  @override
  String get queueDownloadedFileMissing => 'Downloaded file missing';

  @override
  String get queueDownloadCompleted => 'Download completed';

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
  String get clickableLookingUpAlbum => 'Looking up album...';

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
  String get optionsDefaultSearchTabAlbums => 'Albums';

  @override
  String get optionsDefaultSearchTabTracks => 'Tracks';

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
  String get downloadDeduplicationDisabled =>
      'All tracks will be downloaded regardless of history';

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
      'Beta Android service worker for extension downloads';

  @override
  String get badgeBeta => 'BETA';

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
  String get errorCouldNotKeepFolderAccess =>
      'Could not keep access to the selected folder';

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
}
