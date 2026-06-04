// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appName => 'SpotiFLAC Mobile';

  @override
  String get navHome => 'Головна';

  @override
  String get navLibrary => 'Бібліотека';

  @override
  String get navSettings => 'Налаштування';

  @override
  String get navStore => 'Репозиторій';

  @override
  String get homeTitle => 'Головна';

  @override
  String get homeSubtitle =>
      'Вставте URL-адресу яка підтримується, або виконайте пошук за назвою';

  @override
  String get homeEmptyTitle => 'No search providers yet';

  @override
  String get homeEmptySubtitle => 'Install an extension to continue.';

  @override
  String get homeSupports =>
      'Підтримує: URL-адреси треків, альбомів, списків відтворення, виконавців';

  @override
  String get homeRecent => 'Нещодавні';

  @override
  String get historyFilterAll => 'Усі';

  @override
  String get historyFilterAlbums => 'Альбоми';

  @override
  String get historyFilterSingles => 'Сингли';

  @override
  String get historySearchHint => 'Історія пошуку...';

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String get settingsDownload => 'Завантаження';

  @override
  String get settingsAppearance => 'Зовнішній вигляд';

  @override
  String get settingsOptions => 'Опції';

  @override
  String get settingsExtensions => 'Розширення';

  @override
  String get settingsAbout => 'Про додаток';

  @override
  String get downloadTitle => 'Завантажити';

  @override
  String get downloadAskQualitySubtitle =>
      'Показувати вікно вибору якості для кожного завантаження';

  @override
  String get downloadFilenameFormat => 'Формат імені файлу';

  @override
  String get downloadSingleFilenameFormat => 'Формат імені одного файлу';

  @override
  String get downloadSingleFilenameFormatDescription =>
      'Шаблон назви файлу для синглів та міні-альбомів. Використовує ті самі теги, що й формат альбому.';

  @override
  String get downloadFolderOrganization => 'Організація папок';

  @override
  String get appearanceTitle => 'Зовнішній вигляд';

  @override
  String get appearanceThemeSystem => 'Системний';

  @override
  String get appearanceThemeLight => 'Світлий';

  @override
  String get appearanceThemeDark => 'Темний';

  @override
  String get appearanceDynamicColor => 'Динамічний колір';

  @override
  String get appearanceDynamicColorSubtitle =>
      'Використати кольори зі своїх шпалер';

  @override
  String get appearanceHistoryView => 'Історія переглядів';

  @override
  String get appearanceHistoryViewList => 'Список';

  @override
  String get appearanceHistoryViewGrid => 'Сітка';

  @override
  String get optionsTitle => 'Опції';

  @override
  String get optionsPrimaryProvider => 'Основний постачальник';

  @override
  String get optionsPrimaryProviderSubtitle =>
      'Service used for searching by track or album name';

  @override
  String optionsUsingExtension(String extensionName) {
    return 'Використання розширення: $extensionName';
  }

  @override
  String get optionsDefaultSearchTab => 'Вкладка пошуку за замовчуванням';

  @override
  String get optionsDefaultSearchTabSubtitle =>
      'Виберіть, яка вкладка відкриється першою для нових результатів пошуку.';

  @override
  String get optionsSwitchBack =>
      'Натисніть Deezer або Spotify, щоб повернутися до розширення';

  @override
  String get optionsAutoFallback => 'Автоматичний резервний варіант';

  @override
  String get optionsAutoFallbackSubtitle =>
      'Спробувати інші сервіси, якщо завантаження не вдається';

  @override
  String get optionsUseExtensionProviders =>
      'Використати постачальників розширень';

  @override
  String get optionsUseExtensionProvidersOn =>
      'Розширення будуть випробувані першими';

  @override
  String get optionsUseExtensionProvidersOff =>
      'Використати лише вбудованих постачальників';

  @override
  String get optionsEmbedLyrics => 'Вбудований текст пісні';

  @override
  String get optionsEmbedLyricsSubtitle =>
      'Save synced lyrics alongside your downloaded tracks';

  @override
  String get optionsMaxQualityCover => 'Максимальна якість обкладинки';

  @override
  String get optionsMaxQualityCoverSubtitle =>
      'Завантажити обкладинку з найвищою роздільною здатністю';

  @override
  String get optionsReplayGain => 'Нормалізація звуку';

  @override
  String get optionsReplayGainSubtitleOn =>
      'Сканування гучності та вбудовування тегів нормалізації звуку (EBU R128)';

  @override
  String get optionsReplayGainSubtitleOff =>
      'Вимкнено: немає тегів нормалізації гучності';

  @override
  String get optionsArtistTagMode => 'Режим тегу виконавця';

  @override
  String get optionsArtistTagModeDescription =>
      'Виберіть, як будуть записуватися кілька виконавців у вбудовані теги.';

  @override
  String get optionsArtistTagModeJoined => 'Одне об\'єднане значення';

  @override
  String get optionsArtistTagModeJoinedSubtitle =>
      'Для максимальної сумісності програвача напишіть одне значення ARTIST, наприклад, «Виконавець A, Виконавець B».';

  @override
  String get optionsArtistTagModeSplitVorbis => 'Розділені теги для FLAC/Opus';

  @override
  String get optionsArtistTagModeSplitVorbisSubtitle =>
      'Для FLAC та Opus на кожного виконавця додати окремий тег виконавця; MP3 та M4A залишаються об’єднаними.';

  @override
  String get optionsConcurrentDownloads => 'Кількість одночасних завантажень';

  @override
  String get optionsConcurrentSequential => 'Послідовно (по одному за раз)';

  @override
  String optionsConcurrentParallel(int count) {
    return '$count паралельних завантажень';
  }

  @override
  String get optionsConcurrentWarning =>
      'Паралельні завантаження можуть призвести до обмеження швидкості';

  @override
  String get optionsExtensionStore => 'Репозиторій розширень';

  @override
  String get optionsExtensionStoreSubtitle =>
      'Показати вкладку «Репозиторій» у навігації';

  @override
  String get optionsCheckUpdates => 'Перевірити наявність оновлень';

  @override
  String get optionsCheckUpdatesSubtitle =>
      'Повідомити, коли буде доступна нова версія';

  @override
  String get optionsUpdateChannel => 'Канал оновлень';

  @override
  String get optionsUpdateChannelStable => 'Тільки стабільні релізи';

  @override
  String get optionsUpdateChannelPreview => 'Отримати попередні релізи';

  @override
  String get optionsUpdateChannelWarning =>
      'Тестовий реліз може містити помилки або неповні функції';

  @override
  String get optionsClearHistory => 'Очистити історію завантажень';

  @override
  String get optionsClearHistorySubtitle =>
      'Видалити всі завантажені треки з історії';

  @override
  String get optionsDetailedLogging => 'Детальне журналювання';

  @override
  String get optionsDetailedLoggingOn => 'Ведеться детальний журнал';

  @override
  String get optionsDetailedLoggingOff => 'Увімкнути для звітів про помилки';

  @override
  String get optionsSpotifyCredentials => 'Облікові дані Spotify';

  @override
  String optionsSpotifyCredentialsConfigured(String clientId) {
    return 'Ідентифікатор клієнта: $clientId...';
  }

  @override
  String get optionsSpotifyCredentialsRequired =>
      'Обов\'язковий – торкніться, щоб налаштувати';

  @override
  String get optionsSpotifyWarning =>
      'Spotify вимагає ваших власних облікових даних API. Отримайте їх безкоштовно на сайті developer.spotify.com';

  @override
  String get optionsSpotifyDeprecationWarning =>
      'Пошук Spotify буде припинено 3 березня 2026 року через зміни в API Spotify. Будь ласка, перейдіть на Deezer.';

  @override
  String get extensionsTitle => 'Розширення';

  @override
  String get extensionsDisabled => 'Вимкнені';

  @override
  String extensionsVersion(String version) {
    return 'Версія $version';
  }

  @override
  String extensionsAuthor(String author) {
    return 'від $author';
  }

  @override
  String get extensionsUninstall => 'Видалити';

  @override
  String get storeTitle => 'Репозиторій розширень';

  @override
  String get storeSearch => 'Розширення пошуку...';

  @override
  String get storeInstall => 'Встановити';

  @override
  String get storeInstalled => 'Встановлені';

  @override
  String get storeUpdate => 'Оновлені';

  @override
  String get aboutTitle => 'Про нас';

  @override
  String get aboutContributors => 'Автори';

  @override
  String get aboutMobileDeveloper => 'Розробник мобільної версії';

  @override
  String get aboutOriginalCreator => 'Творець оригінального SpotiFLAC';

  @override
  String get aboutLogoArtist =>
      'Талановитий художник, який створив чудовий логотип нашого додатку!';

  @override
  String get aboutTranslators => 'Перекладачі';

  @override
  String get aboutSpecialThanks => 'Особлива подяка';

  @override
  String get aboutLinks => 'Посилання';

  @override
  String get aboutMobileSource => 'Мобільний вихідний код';

  @override
  String get aboutPCSource => 'Вихідний код для ПК';

  @override
  String get aboutKeepAndroidOpen => 'Keep Android Open';

  @override
  String get aboutReportIssue => 'Повідомити про проблему';

  @override
  String get aboutReportIssueSubtitle =>
      'Повідомити про будь-які проблеми, з якими ви зіткнулися';

  @override
  String get aboutFeatureRequest => 'Запит на функцію';

  @override
  String get aboutFeatureRequestSubtitle =>
      'Запропонувати нові функції для програми';

  @override
  String get aboutTelegramChannel => 'Телеграм-канал';

  @override
  String get aboutTelegramChannelSubtitle => 'Оголошення та оновлення';

  @override
  String get aboutTelegramChat => 'Telegram Спільнота';

  @override
  String get aboutTelegramChatSubtitle => 'Спілкуватися з іншими користувачами';

  @override
  String get aboutSocial => 'Соціальні мережі';

  @override
  String get aboutApp => 'Додаток';

  @override
  String get aboutVersion => 'Версія';

  @override
  String get aboutBinimumDesc =>
      'Творець QQDL та HiFi API. Без цього API завантажень Tidal\'а не існувало б!';

  @override
  String get aboutSachinsenalDesc =>
      'Оригінальний творець HiFi-проектів. Основа інтеграції Tidal!';

  @override
  String get aboutSjdonadoDesc =>
      'Творець I Don\'t Have Spotify (IDHS). Резервний розв\'язувач посилань, який рятує становище!';

  @override
  String get aboutAppDescription =>
      'Search music metadata, manage extensions, and organize your library.';

  @override
  String get artistAlbums => 'Альбоми';

  @override
  String get artistSingles => 'Сингли та міні-альбоми';

  @override
  String get artistCompilations => 'Збірники';

  @override
  String get artistPopular => 'Популярні';

  @override
  String artistMonthlyListeners(String count) {
    return '$count слухачів щомісяця';
  }

  @override
  String get trackMetadataService => 'Сервіс';

  @override
  String get trackMetadataPlay => 'Прослухати';

  @override
  String get trackMetadataShare => 'Поділитися';

  @override
  String get trackMetadataDelete => 'Видалити';

  @override
  String get setupGrantPermission => 'Надати дозвіл';

  @override
  String get setupSkip => 'Пропустити поки що';

  @override
  String get setupStorageAccessRequired => 'Потрібен доступ до сховища';

  @override
  String get setupStorageAccessMessageAndroid11 =>
      'Для збереження файлів у вибрану папку завантажень для Android 11+ потрібен дозвіл «Доступ до всіх файлів».';

  @override
  String get setupOpenSettings => 'Відкрити налаштування';

  @override
  String get setupPermissionDeniedMessage =>
      'Дозвіл відхилено. Будь ласка, надайте всі дозволи, щоб продовжити.';

  @override
  String setupPermissionRequired(String permissionType) {
    return '$permissionType Потрібен дозвіл';
  }

  @override
  String setupPermissionRequiredMessage(String permissionType) {
    return '$permissionType Для найкращого досвіду потрібен дозвіл. Ви можете змінити це пізніше в налаштуваннях.';
  }

  @override
  String get setupUseDefaultFolder => 'Використати папку за замовчуванням?';

  @override
  String get setupNoFolderSelected =>
      'Папку не вибрано. Бажаєте використовувати папку «Музика» за замовчуванням?';

  @override
  String get setupUseDefault => 'Використовувати за замовчуванням';

  @override
  String get setupDownloadLocationTitle => 'Розташування завантаження';

  @override
  String get setupDownloadLocationIosMessage =>
      'На iOS завантаження зберігаються в папці «Документи» програми. Ви можете отримати до них доступ через програму «Файли».';

  @override
  String get setupAppDocumentsFolder => 'Папка з документами програми';

  @override
  String get setupAppDocumentsFolderSubtitle =>
      'Рекомендація – доступно через додаток Файли';

  @override
  String get setupChooseFromFiles => 'Вибрати з файлів';

  @override
  String get setupChooseFromFilesSubtitle =>
      'Виберіть iCloud або інше місцезнаходження';

  @override
  String get setupIosEmptyFolderWarning =>
      'Обмеження iOS: Не можна вибрати порожні папки. Виберіть папку, яка містить принаймні один файл.';

  @override
  String get setupIcloudNotSupported =>
      'iCloud Drive не підтримується. Будь ласка, скористайтеся папкою «Документи» програми.';

  @override
  String get setupDownloadInFlac => 'Завантажити треки Spotify у форматі FLAC';

  @override
  String get setupStorageGranted => 'Дозвіл на зберігання надано!';

  @override
  String get setupStorageRequired => 'Потрібен дозвіл на збереження файлів';

  @override
  String get setupStorageDescription =>
      'SpotiFLAC потребує дозволу на збереження, щоб зберегти завантажені музичні файли.';

  @override
  String get setupNotificationGranted => 'Дозвіл на сповіщення надано!';

  @override
  String get setupNotificationEnable => 'Увімкнути сповіщення';

  @override
  String get setupFolderChoose => 'Виберати папку для завантаження';

  @override
  String get setupFolderDescription =>
      'Виберіть папку, де буде збережено завантажену музику.';

  @override
  String get setupSelectFolder => 'Вибрати папку';

  @override
  String get setupEnableNotifications => 'Увімкнути сповіщення';

  @override
  String get setupNotificationBackgroundDescription =>
      'Отримуйте сповіщення про прогрес та завершення завантаження. Це допомагає відстежувати завантаження, коли програма працює у фоновому режимі.';

  @override
  String get setupSkipForNow => 'Пропустити поки що';

  @override
  String get setupNext => 'Далі';

  @override
  String get setupGetStarted => 'Почати';

  @override
  String get setupAllowAccessToManageFiles =>
      'Будь ласка, увімкніть опцію «Дозволити доступ для керування всіма файлами» на наступному екрані.';

  @override
  String get setupLanguageTitle => 'Choose Language';

  @override
  String get setupLanguageDescription =>
      'Select your preferred language for the app. You can change this later in Settings.';

  @override
  String get setupLanguageSystemDefault => 'System Default';

  @override
  String get dialogCancel => 'Скасувати';

  @override
  String get dialogSave => 'Зберегти';

  @override
  String get dialogDelete => 'Видалити';

  @override
  String get dialogRetry => 'Повторити спробу';

  @override
  String get dialogClear => 'Очистити';

  @override
  String get dialogDone => 'Готово';

  @override
  String get dialogImport => 'Імпорт';

  @override
  String get dialogDownload => 'Завантажити';

  @override
  String get dialogDiscard => 'Відхилити';

  @override
  String get dialogRemove => 'Видалити';

  @override
  String get dialogUninstall => 'Деінсталювати';

  @override
  String get dialogDiscardChanges => 'Відхилити зміни?';

  @override
  String get dialogUnsavedChanges =>
      'У вас є незбережені зміни. Ви хочете їх скасувати?';

  @override
  String get dialogClearAll => 'Очистити все';

  @override
  String get dialogRemoveExtension => 'Видалити розширення';

  @override
  String get dialogRemoveExtensionMessage =>
      'Ви впевнені, що хочете видалити це розширення? Цю дію неможливо скасувати.';

  @override
  String get dialogUninstallExtension => 'Видалити розширення?';

  @override
  String dialogUninstallExtensionMessage(String extensionName) {
    return 'Ви впевнені, що хочете видалити $extensionName?';
  }

  @override
  String get dialogClearHistoryTitle => 'Очистити історію';

  @override
  String get dialogClearHistoryMessage =>
      'Ви впевнені, що хочете очистити всю історію завантажень? Цю дію неможливо скасувати.';

  @override
  String get dialogDeleteSelectedTitle => 'Видалити вибране';

  @override
  String dialogDeleteSelectedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Видалити $count $_temp0 з історії?\n\nЦе також видалить файли з пам\'яті.';
  }

  @override
  String get dialogImportPlaylistTitle => 'Імпорт списку відтворення';

  @override
  String dialogImportPlaylistMessage(int count) {
    return 'Знайдено $count треків у CSV. Додати їх до черги завантаження?';
  }

  @override
  String csvImportTracks(int count) {
    return '$count треків з CSV';
  }

  @override
  String snackbarAddedToQueue(String trackName) {
    return 'Додано \"$trackName\" до черги';
  }

  @override
  String snackbarAddedTracksToQueue(int count) {
    return 'Додано $count треків до черги';
  }

  @override
  String snackbarAlreadyDownloaded(String trackName) {
    return '\"$trackName\" вже завантажено';
  }

  @override
  String snackbarAlreadyInLibrary(String trackName) {
    return '\"$trackName\" вже є у вашій бібліотеці';
  }

  @override
  String get snackbarHistoryCleared => 'Історія очищена';

  @override
  String get snackbarCredentialsSaved => 'Облікові дані збережено';

  @override
  String get snackbarCredentialsCleared => 'Облікові дані очищено';

  @override
  String snackbarDeletedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Видалено $count $_temp0';
  }

  @override
  String snackbarCannotOpenFile(String error) {
    return 'Не вдається відкрити файл: $error';
  }

  @override
  String get snackbarFillAllFields => 'Будь ласка, заповніть усі поля';

  @override
  String get snackbarViewQueue => 'Переглянути чергу';

  @override
  String snackbarUrlCopied(String platform) {
    return '$platform URL-адреса скопійована в буфер обміну';
  }

  @override
  String get snackbarFileNotFound => 'Файл не знайдено';

  @override
  String get snackbarSelectExtFile =>
      'Будь ласка, виберіть файл .spotiflac-ext';

  @override
  String get snackbarProviderPrioritySaved =>
      'Пріоритет постачальника збережено';

  @override
  String get snackbarMetadataProviderSaved =>
      'Пріоритет постачальника метаданих збережено';

  @override
  String snackbarExtensionInstalled(String extensionName) {
    return 'Розширення $extensionName встановлено.';
  }

  @override
  String snackbarExtensionUpdated(String extensionName) {
    return '$extensionName оновлено.';
  }

  @override
  String get snackbarFailedToInstall => 'Не вдалося встановити розширення';

  @override
  String get snackbarFailedToUpdate => 'Не вдалося оновити розширення';

  @override
  String get errorRateLimited => 'Обмежений тариф';

  @override
  String get errorRateLimitedMessage =>
      'Забагато запитів. Будь ласка, зачекайте хвилинку, перш ніж шукати знову.';

  @override
  String get errorNoTracksFound => 'Треків не знайдено';

  @override
  String get searchEmptyResultSubtitle => 'Try another keyword';

  @override
  String get errorUrlNotRecognized => 'Посилання не розпізнано';

  @override
  String get errorUrlNotRecognizedMessage =>
      'Це посилання не підтримується. Переконайтеся, що URL-адреса правильна та встановлено сумісне розширення.';

  @override
  String get errorUrlFetchFailed =>
      'Не вдалося завантажити вміст за цим посиланням. Спробуйте ще раз.';

  @override
  String errorMissingExtensionSource(String item) {
    return 'Не вдається завантажити $item: відсутній вихідний код розширення';
  }

  @override
  String get actionPause => 'Пауза';

  @override
  String get actionResume => 'Відновити';

  @override
  String get actionCancel => 'Скасувати';

  @override
  String get actionSelectAll => 'Вибрати все';

  @override
  String get actionDeselect => 'Скасувати вибір';

  @override
  String get actionRemoveCredentials => 'Видалити облікові дані';

  @override
  String get actionSaveCredentials => 'Зберегти облікові дані';

  @override
  String selectionSelected(int count) {
    return 'Вибрано $count';
  }

  @override
  String get selectionAllSelected => 'Усі треки вибрано';

  @override
  String get selectionSelectToDelete => 'Виберіть треки для видалення';

  @override
  String progressFetchingMetadata(int current, int total) {
    return 'Отримання метаданих... $current/$total';
  }

  @override
  String get progressReadingCsv => 'Читання CSV-файлу...';

  @override
  String get searchSongs => 'Пісні';

  @override
  String get searchArtists => 'Виконавці';

  @override
  String get searchAlbums => 'Альбоми';

  @override
  String get searchPlaylists => 'Списки відтворення';

  @override
  String get searchSortTitle => 'Сортувати результати';

  @override
  String get searchSortDefault => 'За замовчуванням';

  @override
  String get searchSortTitleAZ => 'Назва (А-Я)';

  @override
  String get searchSortTitleZA => 'Назва (Я-А)';

  @override
  String get searchSortArtistAZ => 'Виконавець (А-Я)';

  @override
  String get searchSortArtistZA => 'Виконавець (Я-А)';

  @override
  String get searchSortDurationShort => 'Тривалість (найкоротша)';

  @override
  String get searchSortDurationLong => 'Тривалість (найдовша)';

  @override
  String get searchSortDateOldest => 'Дата випуску (найстаріша)';

  @override
  String get searchSortDateNewest => 'Дата випуску (найновіша)';

  @override
  String get tooltipPlay => 'Відтворити';

  @override
  String get filenameFormat => 'Формат імені файлу';

  @override
  String get filenameShowAdvancedTags => 'Показати розширені теги';

  @override
  String get filenameShowAdvancedTagsDescription =>
      'Увімкнути відформатовані теги для доповнення доріжок і шаблонів дати';

  @override
  String get folderOrganizationNone => 'Жодної організації';

  @override
  String get folderOrganizationByPlaylist => 'За списком відтворення';

  @override
  String get folderOrganizationByPlaylistSubtitle =>
      'Окрема папка для кожного списку відтворення';

  @override
  String get folderOrganizationByArtist => 'За виконавцем';

  @override
  String get folderOrganizationByAlbum => 'За альбомом';

  @override
  String get folderOrganizationByArtistAlbum => 'Виконавець/Альбом';

  @override
  String get folderOrganizationDescription =>
      'Упорядкувати завантажені файли в папки';

  @override
  String get folderOrganizationNoneSubtitle => 'Усі файли в папці завантажень';

  @override
  String get folderOrganizationByArtistSubtitle =>
      'Окрема папка для кожного виконавця';

  @override
  String get folderOrganizationByAlbumSubtitle =>
      'Окрема папка для кожного альбому';

  @override
  String get folderOrganizationByArtistAlbumSubtitle =>
      'Вкладені папки для виконавця та альбому';

  @override
  String get updateAvailable => 'Доступне оновлення';

  @override
  String get updateLater => 'Пізніше';

  @override
  String get updateStartingDownload => 'Початок завантаження...';

  @override
  String get updateDownloadFailed => 'Не вдалося завантажити';

  @override
  String get updateFailedMessage => 'Не вдалося завантажити оновлення';

  @override
  String get updateNewVersionReady => 'Доступна нова версія';

  @override
  String get updateCurrent => 'Поточна';

  @override
  String get updateNew => 'Нова';

  @override
  String get updateDownloading => 'Завантаження...';

  @override
  String get updateWhatsNew => 'Що нового';

  @override
  String get updateDownloadInstall => 'Завантажити та встановити';

  @override
  String get updateDontRemind => 'Не нагадувати';

  @override
  String get providerPriorityTitle => 'Пріоритет постачальника';

  @override
  String get providerPriorityDescription =>
      'Перетягніть, щоб змінити порядок постачальників завантажень. Під час завантаження треків програма використовуватиме постачальників зверху вниз.';

  @override
  String get providerPriorityInfo =>
      'Якщо трек недоступний у першого провайдера, додаток автоматично спробує наступного.';

  @override
  String get providerPriorityFallbackExtensionsTitle => 'Резервне розширення';

  @override
  String get providerPriorityFallbackExtensionsDescription =>
      'Choose which installed download extensions can be used during automatic fallback.';

  @override
  String get providerPriorityFallbackExtensionsHint =>
      'Тут перелічені лише ввімкнені розширення з можливістю завантаження через постачальника послуг.';

  @override
  String get providerBuiltIn => 'Вбудований';

  @override
  String get providerExtension => 'Розширення';

  @override
  String get metadataProviderPriorityTitle => 'Пріоритет метаданих';

  @override
  String get metadataProviderPriorityDescription =>
      'Перетягніть, щоб змінити порядок постачальників метаданих. Додаток шукатиме постачальників зверху вниз під час пошуку треків та отримання метаданих.';

  @override
  String get metadataProviderPriorityInfo =>
      'Deezer не має обмежень за швидкістю та рекомендований як основний сервіс. Spotify може обмежувати швидкість після великої кількості запитів.';

  @override
  String get metadataNoRateLimits => 'Без обмежень щодо швидкості';

  @override
  String get metadataMayRateLimit => 'Травневе обмеження ставок';

  @override
  String get logTitle => 'Журнали';

  @override
  String get logCopied => 'Журнали скопійовано в буфер обміну';

  @override
  String get logSearchHint => 'Пошук журналів...';

  @override
  String get logFilterLevel => 'Рівень';

  @override
  String get logFilterSection => 'Фільтр';

  @override
  String get logShareLogs => 'Журнали обміну';

  @override
  String get logClearLogs => 'Очистити журнали';

  @override
  String get logClearLogsTitle => 'Очистити Журнали';

  @override
  String get logClearLogsMessage =>
      'Ви впевнені, що хочете очистити всі журнали?';

  @override
  String get logFilterBySeverity => 'Фільтрувати журнали за рівнем серйозності';

  @override
  String get logNoLogsYet => 'Журналів поки що немає';

  @override
  String get logNoLogsYetSubtitle =>
      'Журнали відображатимуться тут під час використання програми';

  @override
  String logEntriesFiltered(int count) {
    return 'Записи ($count filtered)';
  }

  @override
  String logEntries(int count) {
    return 'Записи ($count)';
  }

  @override
  String get credentialsTitle => 'Облікові дані Spotify';

  @override
  String get credentialsDescription =>
      'Введіть свій ідентифікатор клієнта та секретний код, щоб використовувати власну квоту програми Spotify.';

  @override
  String get credentialsClientId => 'Ідентифікатор клієнта';

  @override
  String get credentialsClientIdHint => 'Вставити ідентифікатор клієнта';

  @override
  String get credentialsClientSecret => 'Секретний код клієнта';

  @override
  String get credentialsClientSecretHint => 'Вставити секретний код клієнта';

  @override
  String get channelStable => 'Стабільний';

  @override
  String get channelPreview => 'Бета';

  @override
  String get sectionSearchSource => 'Джерело пошуку';

  @override
  String get sectionDownload => 'Завантажити';

  @override
  String get sectionPerformance => 'Продуктивність';

  @override
  String get sectionApp => 'Додаток';

  @override
  String get sectionData => 'Дані';

  @override
  String get sectionDebug => 'Налагодження';

  @override
  String get sectionService => 'Сервіс';

  @override
  String get sectionAudioQuality => 'Якість звуку';

  @override
  String get sectionFileSettings => 'Налаштування файлу';

  @override
  String get sectionLyrics => 'Тексти пісень';

  @override
  String get lyricsMode => 'Режим тексту пісні';

  @override
  String get lyricsModeDescription =>
      'Виберіть, як тексти пісень зберігатимуться разом із завантаженнями пісень.';

  @override
  String get lyricsModeEmbed => 'Вбудувати у файл';

  @override
  String get lyricsModeEmbedSubtitle =>
      'Тексти пісень зберігаються в метаданих FLAC';

  @override
  String get lyricsModeExternal => 'Зовнішній файл .lrc';

  @override
  String get lyricsModeExternalSubtitle =>
      'Окремий файл .lrc для плеєрів, таких як Samsung Music';

  @override
  String get lyricsModeBoth => 'Обидва';

  @override
  String get lyricsModeBothSubtitle => 'Вбудувати та зберегти файл .lrc';

  @override
  String get sectionColor => 'Колір';

  @override
  String get sectionTheme => 'Тема';

  @override
  String get sectionLayout => 'Макет';

  @override
  String get sectionLanguage => 'Мова';

  @override
  String get appearanceLanguage => 'Мова програми';

  @override
  String get settingsAppearanceSubtitle => 'Тема, кольори, дисплей';

  @override
  String get settingsDownloadSubtitle => 'Service, quality, fallback';

  @override
  String get settingsOptionsSubtitle => 'Fallback, metadata, lyrics, cover art';

  @override
  String get settingsExtensionsSubtitle =>
      'Керування постачальниками послуг завантаження';

  @override
  String get settingsLogsSubtitle =>
      'Перегляд журналів програми для налагодження';

  @override
  String get loadingSharedLink => 'Завантаження спільного посилання...';

  @override
  String get pressBackAgainToExit =>
      'Натисніть кнопку «Назад» ще раз, щоб вийти';

  @override
  String downloadAllCount(int count) {
    return 'Завантажити все ($count)';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треків',
      one: '1 трек',
    );
    return '$_temp0';
  }

  @override
  String get trackCopyFilePath => 'Копіювати шлях до файлу';

  @override
  String get trackRemoveFromDevice => 'Видалити з пристрою';

  @override
  String get trackLoadLyrics => 'Завантажити текст пісні';

  @override
  String get trackMetadata => 'Метадані';

  @override
  String get trackFileInfo => 'Інформація про файл';

  @override
  String get trackLyrics => 'Тексти пісень';

  @override
  String get trackFileNotFound => 'Файл не знайдено';

  @override
  String get trackOpenInDeezer => 'Відкрити в Deezer';

  @override
  String get trackOpenInSpotify => 'Відкрити в Spotify';

  @override
  String get trackTrackName => 'Назва треку';

  @override
  String get trackArtist => 'Артист';

  @override
  String get trackAlbumArtist => 'Виконавець альбому';

  @override
  String get trackAlbum => 'Альбом';

  @override
  String get trackTrackNumber => 'Номер треку';

  @override
  String get trackDiscNumber => 'Номер диска';

  @override
  String get trackDuration => 'Тривалість';

  @override
  String get trackAudioQuality => 'Якість звуку';

  @override
  String get trackReleaseDate => 'Дата випуску';

  @override
  String get trackGenre => 'Жанр';

  @override
  String get trackLabel => 'Лейбл';

  @override
  String get trackCopyright => 'Авторське право';

  @override
  String get trackDownloaded => 'Завантажено';

  @override
  String get trackCopyLyrics => 'Скопіювати тексти пісень';

  @override
  String trackLyricsSource(String source) {
    return 'Source: $source';
  }

  @override
  String get trackLyricsNotAvailable =>
      'Текст пісні для цього треку недоступний';

  @override
  String get trackLyricsNotInFile => 'У цьому файлі не знайдено текстів пісень';

  @override
  String get trackFetchOnlineLyrics => 'Отримати з Інтернету';

  @override
  String get trackLyricsTimeout =>
      'Час очікування запиту минув. Спробуйте ще раз пізніше.';

  @override
  String get trackLyricsLoadFailed => 'Не вдалося завантажити текст пісні';

  @override
  String get trackEmbedLyrics => 'Вбудувати текст пісні';

  @override
  String get trackLyricsEmbedded => 'Текст пісні успішно вбудовано в пісню';

  @override
  String get trackInstrumental => 'Інструментальний трек';

  @override
  String get trackCopiedToClipboard => 'Скопійовано в буфер обміну';

  @override
  String get trackDeleteConfirmTitle => 'Видалити з пристрою?';

  @override
  String get trackDeleteConfirmMessage =>
      'Це назавжди видалить завантажений файл і вилучить його з вашої історії.';

  @override
  String get dateToday => 'Сьогодні';

  @override
  String get dateYesterday => 'Вчора';

  @override
  String dateDaysAgo(int count) {
    return '$count днів тому';
  }

  @override
  String dateWeeksAgo(int count) {
    return '$count тижнів тому';
  }

  @override
  String dateMonthsAgo(int count) {
    return '$count місяців тому';
  }

  @override
  String get storeFilterAll => 'Усі';

  @override
  String get storeFilterMetadata => 'Метадані';

  @override
  String get storeFilterDownload => 'Завантажити';

  @override
  String get storeFilterUtility => 'Утиліта';

  @override
  String get storeFilterLyrics => 'Тексти пісень';

  @override
  String get storeFilterIntegration => 'Інтеграція';

  @override
  String get storeClearFilters => 'Очистити фільтри';

  @override
  String get storeAddRepoTitle => 'Додати репозиторій розширень';

  @override
  String get storeAddRepoDescription =>
      'Введіть URL-адресу репозиторію GitHub, яка містить файл registry.json, для перегляду та встановлення розширень.';

  @override
  String get storeRepoUrlLabel => 'URL-адреса репозиторію';

  @override
  String get storeRepoUrlHint => 'https://github.com/user/repo';

  @override
  String get storeRepoUrlHelper =>
      'наприклад https://github.com/user/extensions-repo';

  @override
  String get storeAddRepoButton => 'Додати репозиторій';

  @override
  String get storeChangeRepoTooltip => 'Змінити репозиторій';

  @override
  String get storeRepoDialogTitle => 'Репозиторій розширень';

  @override
  String get storeRepoDialogCurrent => 'Поточний репозиторій:';

  @override
  String get storeNewRepoUrlLabel => 'Нова URL-адреса репозиторію';

  @override
  String get storeLoadError => 'Не вдалося завантажити репозиторій';

  @override
  String get storeEmptyNoExtensions => 'Розширень немає';

  @override
  String get storeEmptyNoResults => 'Розширень не знайдено';

  @override
  String get extensionDefaultProvider => 'За замовчуванням (Deezer)';

  @override
  String get extensionDefaultProviderSubtitle => 'Використати вбудований пошук';

  @override
  String get extensionAuthor => 'Автор';

  @override
  String get extensionId => 'Ідентифікатор';

  @override
  String get extensionError => 'Помилка';

  @override
  String get extensionCapabilities => 'Можливості';

  @override
  String get extensionMetadataProvider => 'Постачальник метаданих';

  @override
  String get extensionDownloadProvider => 'Постачальник завантажень';

  @override
  String get extensionLyricsProvider => 'Постачальник текстів пісень';

  @override
  String get extensionUrlHandler => 'Обробник URL-адрес';

  @override
  String get extensionQualityOptions => 'Варіанти якості';

  @override
  String get extensionPostProcessingHooks => 'Хуки пост-обробки';

  @override
  String get extensionPermissions => 'Дозволи';

  @override
  String get extensionSettings => 'Налаштування';

  @override
  String get extensionRemoveButton => 'Видалити розширення';

  @override
  String get extensionUpdated => 'Оновлено';

  @override
  String get extensionMinAppVersion => 'Мінімальна версія програми';

  @override
  String get extensionCustomTrackMatching => 'Підбір користувацьких треків';

  @override
  String get extensionPostProcessing => 'Післяобробка';

  @override
  String extensionHooksAvailable(int count) {
    return '$count доступних хуків';
  }

  @override
  String extensionPatternsCount(int count) {
    return '$count шаблон(ів)';
  }

  @override
  String extensionStrategy(String strategy) {
    return 'Стратегія: $strategy';
  }

  @override
  String get extensionsProviderPrioritySection => 'Пріоритет постачальника';

  @override
  String get extensionsInstalledSection => 'Встановлені розширення';

  @override
  String get extensionsNoExtensions => 'Розширень не встановлено';

  @override
  String get extensionsNoExtensionsSubtitle =>
      'Встановіть файли .spotiflac-ext, щоб додати нових провайдерів';

  @override
  String get extensionsInstallButton => 'Встановити розширення';

  @override
  String get extensionsInfoTip =>
      'Розширення можуть додавати нові метадані та завантажувати постачальників. Встановлюйте розширення лише з перевірених джерел.';

  @override
  String get extensionsInstalledSuccess => 'Розширення успішно встановлено';

  @override
  String extensionsInstalledCount(int count) {
    return '$count extensions installed successfully';
  }

  @override
  String extensionsInstallPartialSuccess(int installed, int attempted) {
    return 'Installed $installed of $attempted extensions';
  }

  @override
  String get extensionsDownloadPriority => 'Пріоритет завантаження';

  @override
  String get extensionsDownloadPrioritySubtitle =>
      'Встановити порядок завантаження';

  @override
  String get extensionsFallbackTitle => 'Резервні розширення';

  @override
  String get extensionsFallbackSubtitle =>
      'Виберіть, які встановлені розширення для завантаження можна використовувати як резервні';

  @override
  String get extensionsNoDownloadProvider =>
      'Без розширень із постачальником завантажень';

  @override
  String get extensionsMetadataPriority => 'Пріоритет метаданих';

  @override
  String get extensionsMetadataPrioritySubtitle =>
      'Встановити порядок пошуку та джерел метаданих';

  @override
  String get extensionsNoMetadataProvider =>
      'Без розширень із постачальником метаданих';

  @override
  String get extensionsSearchProvider => 'Постачальник пошуку';

  @override
  String get extensionsNoCustomSearch =>
      'Без розширень із користувацьким пошуком';

  @override
  String get extensionsSearchProviderDescription =>
      'Виберіть, який сервіс використовувати для пошуку треків';

  @override
  String get extensionsCustomSearch => 'Користувацький пошук';

  @override
  String get extensionsErrorLoading => 'Помилка завантаження розширення';

  @override
  String get qualityFlacLossless => 'FLAC без втрат';

  @override
  String get qualityFlacLosslessSubtitle => '16 біт / 44,1 кГц';

  @override
  String get qualityHiResFlac => 'FLAC високої роздільної здатності';

  @override
  String get qualityHiResFlacSubtitle => '24-біт / до 96 кГц';

  @override
  String get qualityHiResFlacMax => 'FLAC Max з високою роздільною здатністю';

  @override
  String get qualityHiResFlacMaxSubtitle => '24-біт / до 192 кГц';

  @override
  String get downloadLossy320 => 'Lossy (із втратами) 320 кбіт/с';

  @override
  String get downloadLossyFormat => 'Формат із втратами';

  @override
  String get downloadLossy320Format => 'Формат із втратами 320 кбіт/с';

  @override
  String get downloadLossy320FormatDesc =>
      'Виберіть вихідний формат для завантажень Tidal 320 кбіт/с із втратами. Оригінальний потік AAC буде конвертовано у вибраний вами формат.';

  @override
  String get downloadLossyMp3 => 'MP3 320 кбіт/с';

  @override
  String get downloadLossyMp3Subtitle =>
      'Найкраща сумісність, ~10 МБ на доріжку';

  @override
  String get downloadLossyAac => 'AAC/M4A 320kbps';

  @override
  String get downloadLossyAacSubtitle =>
      'Best mobile compatibility, M4A container';

  @override
  String get downloadLossyOpus256 => 'Opus 256 кбіт/с';

  @override
  String get downloadLossyOpus256Subtitle =>
      'Opus найкращої якості, ~8 МБ на трек';

  @override
  String get downloadLossyOpus128 => 'Opus 128 кбіт/с';

  @override
  String get downloadLossyOpus128Subtitle =>
      'Найменший розмір, ~4 МБ на доріжку';

  @override
  String get qualityNote =>
      'Фактична якість залежить від наявності треку в сервісі';

  @override
  String get downloadAskBeforeDownload => 'Запитувати перед завантаженням';

  @override
  String get downloadDirectory => 'Каталог завантажень';

  @override
  String get downloadSeparateSinglesFolder => 'Окрема папка для синглів';

  @override
  String get downloadAlbumFolderStructure => 'Структура папок альбому';

  @override
  String get downloadUseAlbumArtistForFolders =>
      'Використовувати виконавця альбому для папок';

  @override
  String get downloadUsePrimaryArtistOnly =>
      'Тільки основний виконавець для папок';

  @override
  String get downloadUsePrimaryArtistOnlyEnabled =>
      'Вибраних виконавців видалити з назви папки (наприклад, Джастін Бібер, Quavo → Джастін Бібер)';

  @override
  String get downloadUsePrimaryArtistOnlyDisabled =>
      'Повний рядок виконавця, що використовується для назви папки';

  @override
  String get downloadSelectQuality => 'Вибрати якість';

  @override
  String get downloadFrom => 'Завантажити з';

  @override
  String get appearanceAmoledDark => 'Темний AMOLED';

  @override
  String get appearanceAmoledDarkSubtitle => 'Чисто чорний фон';

  @override
  String get queueClearAll => 'Усі';

  @override
  String get queueClearAllMessage =>
      'Ви впевнені, що хочете очистити всі завантаження?';

  @override
  String get settingsAutoExportFailed =>
      'Автоматичний експорт невдалих завантажень';

  @override
  String get settingsAutoExportFailedSubtitle =>
      'Автоматично зберігати невдалі завантаження у файл TXT';

  @override
  String get settingsDownloadNetwork => 'Мережа для завантаження';

  @override
  String get settingsDownloadNetworkAny => 'Wi-Fi + мобільний інтернет';

  @override
  String get settingsDownloadNetworkWifiOnly => 'Тільки Wi-Fi';

  @override
  String get settingsDownloadNetworkSubtitle =>
      'Вибрати мережу для завантажень. Якщо встановлено значення «Тільки Wi-Fi», завантаження призупиняться через мобільні дані.';

  @override
  String get albumFolderArtistAlbum => 'Артист / Альбом';

  @override
  String get albumFolderArtistAlbumSubtitle =>
      'Альбоми/Ім\'я артиста/Назва альбому/';

  @override
  String get albumFolderArtistYearAlbum => 'Артист / [Рік] Альбом';

  @override
  String get albumFolderArtistYearAlbumSubtitle =>
      'Альбоми/Ім\'я Виконавця/[2005] Назва альбому/';

  @override
  String get albumFolderAlbumOnly => 'Тільки альбом';

  @override
  String get albumFolderAlbumOnlySubtitle => 'Альбоми/Назва Альбому/';

  @override
  String get albumFolderYearAlbum => '[Рік] Альбом';

  @override
  String get albumFolderYearAlbumSubtitle => 'Альбоми/[2005] Назва Альбому/';

  @override
  String get albumFolderArtistAlbumSingles => 'Виконавець / Альбом + Сингли';

  @override
  String get albumFolderArtistAlbumSinglesSubtitle =>
      'Виконавець/Альбом/ та Виконавець/Сингли/';

  @override
  String get albumFolderArtistAlbumFlat =>
      'Виконавець / Альбом (сингли без альбомів)';

  @override
  String get albumFolderArtistAlbumFlatSubtitle =>
      'Виконавець/Альбом/ та Виконавець/пісня.flac';

  @override
  String get downloadedAlbumDeleteSelected => 'Видалити вибране';

  @override
  String downloadedAlbumDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Видалити $count $_temp0 з цього альбому?\n\nЦе також призведе до видалення файлів зі сховища.';
  }

  @override
  String downloadedAlbumSelectedCount(int count) {
    return 'Вибрано $count';
  }

  @override
  String get downloadedAlbumAllSelected => 'Усі треки вибрано';

  @override
  String get downloadedAlbumTapToSelect => 'Натисніть на треки, щоб вибрати';

  @override
  String downloadedAlbumDeleteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Видалити $count $_temp0';
  }

  @override
  String get downloadedAlbumSelectToDelete => 'Виберіть треки для видалення';

  @override
  String downloadedAlbumDiscHeader(int discNumber) {
    return 'Диск $discNumber';
  }

  @override
  String get recentTypeArtist => 'Артист';

  @override
  String get recentTypeAlbum => 'Альбом';

  @override
  String get recentTypeSong => 'Пісня';

  @override
  String get recentTypePlaylist => 'Список відтворення';

  @override
  String get recentEmpty => 'Поки що немає нещодавніх записів';

  @override
  String get recentShowAllDownloads => 'Показати всі завантаження';

  @override
  String recentPlaylistInfo(String name) {
    return 'Список відтворення: $name';
  }

  @override
  String get discographyDownload => 'Завантажити дискографію';

  @override
  String get discographyDownloadAll => 'Завантажити все';

  @override
  String discographyDownloadAllSubtitle(int count, int albumCount) {
    return '$count треків з $albumCount релізів';
  }

  @override
  String get discographyAlbumsOnly => 'Тільки альбоми';

  @override
  String discographyAlbumsOnlySubtitle(int count, int albumCount) {
    return '$count треків з $albumCount альбомів';
  }

  @override
  String get discographySinglesOnly => 'Тільки сингли та міні-альбоми';

  @override
  String discographySinglesOnlySubtitle(int count, int albumCount) {
    return '$count треків з $albumCount синглів';
  }

  @override
  String get discographySelectAlbums => 'Вибрати альбоми...';

  @override
  String get discographySelectAlbumsSubtitle =>
      'Виберіть конкретні альбоми або сингли';

  @override
  String get discographyFetchingTracks => 'Отримання треків...';

  @override
  String discographyFetchingAlbum(int current, int total) {
    return 'Отримання $current з $total...';
  }

  @override
  String discographySelectedCount(int count) {
    return '$count вибрано';
  }

  @override
  String get discographyDownloadSelected => 'Завантажити вибране';

  @override
  String discographyAddedToQueue(int count) {
    return 'Додано $count треків до черги';
  }

  @override
  String discographySkippedDownloaded(int added, int skipped) {
    return '$added додано, $skipped вже завантажено';
  }

  @override
  String get discographyNoAlbums => 'Немає доступних альбомів';

  @override
  String get discographyFailedToFetch => 'Не вдалося отримати деякі альбоми';

  @override
  String get sectionStorageAccess => 'Доступ до сховища';

  @override
  String get allFilesAccess => 'Доступ до всіх файлів';

  @override
  String get allFilesAccessEnabledSubtitle =>
      'Можна записувати в будь-яку папку';

  @override
  String get allFilesAccessDisabledSubtitle => 'Обмежено лише медіа-папками';

  @override
  String get allFilesAccessDescription =>
      'Увімкніть цю опцію, якщо під час збереження у власні папки виникають помилки запису. Android 13+ за замовчуванням обмежує доступ до певних каталогів.';

  @override
  String get allFilesAccessDeniedMessage =>
      'У дозволі відмовлено. Будь ласка, увімкніть «Доступ до всіх файлів» вручну в налаштуваннях системи.';

  @override
  String get allFilesAccessDisabledMessage =>
      'У дозволі відмовлено. Будь ласка, увімкніть «Доступ до всіх файлів» вручну в налаштуваннях системи.';

  @override
  String get settingsLocalLibrary => 'Локальна бібліотека';

  @override
  String get settingsLocalLibrarySubtitle =>
      'Сканування музики та виявлення дублікатів';

  @override
  String get settingsCache => 'Сховище та Кеш';

  @override
  String get settingsCacheSubtitle =>
      'Переглянути розмір і очистити кешовані дані';

  @override
  String get libraryTitle => 'Локальна бібліотека';

  @override
  String get libraryScanSettings => 'Налаштування сканування';

  @override
  String get libraryEnableLocalLibrary => 'Увімкнути локальну бібліотеку';

  @override
  String get libraryEnableLocalLibrarySubtitle =>
      'Скануати та відстежити свою існуючу музику';

  @override
  String get libraryFolder => 'Папка бібліотеки';

  @override
  String get libraryFolderHint => 'Натисніть, щоб вибрати папку';

  @override
  String get libraryShowDuplicateIndicator => 'Показати індикатор дублікатів';

  @override
  String get libraryShowDuplicateIndicatorSubtitle =>
      'Показувати під час пошуку існуючих треків';

  @override
  String get libraryAutoScan => 'Автоматичне сканування';

  @override
  String get libraryAutoScanSubtitle =>
      'Автоматичне сканування бібліотеки на наявність нових файлів';

  @override
  String get libraryAutoScanOff => 'Вимкнено';

  @override
  String get libraryAutoScanOnOpen => 'Кожного разу коли додаток відкривається';

  @override
  String get libraryAutoScanDaily => 'Щоденно';

  @override
  String get libraryAutoScanWeekly => 'Щотижнево';

  @override
  String get libraryActions => 'Дії';

  @override
  String get libraryScan => 'Сканувати бібліотеку';

  @override
  String get libraryScanSubtitle => 'Сканувати для аудіофайлів';

  @override
  String get libraryScanSelectFolderFirst => 'Спочатку виберіть папку';

  @override
  String get libraryCleanupMissingFiles => 'Очищення відсутніх файлів';

  @override
  String get libraryCleanupMissingFilesSubtitle =>
      'Видалити записи для файлів, яких більше не існує';

  @override
  String get libraryClear => 'Очистити бібліотеку';

  @override
  String get libraryClearSubtitle => 'Видалити всі скановані треки';

  @override
  String get libraryClearConfirmTitle => 'Очистити бібліотеку';

  @override
  String get libraryClearConfirmMessage =>
      'Це видалить усі скановані треки з вашої бібліотеки. Ваші фактичні музичні файли не будуть видалені.';

  @override
  String get libraryAbout => 'Про локальну бібліотеку';

  @override
  String get libraryAboutDescription =>
      'Сканує вашу існуючу музичну колекцію для виявлення дублікатів під час завантаження. Підтримує формати FLAC, M4A, MP3, Opus та OGG. Метадані зчитуються з тегів файлів, коли вони доступні.';

  @override
  String libraryTracksUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return '$_temp0';
  }

  @override
  String libraryFilesUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'файлів',
      one: 'file',
    );
    return '$_temp0';
  }

  @override
  String libraryLastScanned(String time) {
    return 'Останнє сканування: $time';
  }

  @override
  String get libraryLastScannedNever => 'Ніколи';

  @override
  String get libraryScanning => 'Сканування...';

  @override
  String get libraryScanFinalizing => 'Завершення роботи з бібліотекою...';

  @override
  String libraryScanProgress(String progress, int total) {
    return '$progress% від $total файлів';
  }

  @override
  String get libraryInLibrary => 'У бібліотеці';

  @override
  String libraryRemovedMissingFiles(int count) {
    return 'Видалено $count відсутніх файлів з бібліотеки';
  }

  @override
  String get libraryCleared => 'Бібліотека очищена';

  @override
  String get libraryStorageAccessRequired => 'Потрібен доступ до сховища';

  @override
  String get libraryStorageAccessMessage =>
      'SpotiFLAC потрібен доступ до сховища для сканування вашої музичної бібліотеки. Надайте дозвіл у налаштуваннях.';

  @override
  String get libraryFolderNotExist => 'Вибрана папка не існує';

  @override
  String get librarySourceDownloaded => 'Завантажені';

  @override
  String get librarySourceLocal => 'Локальні';

  @override
  String get libraryFilterAll => 'Усі';

  @override
  String get libraryFilterDownloaded => 'Завантажені';

  @override
  String get libraryFilterLocal => 'Локальні';

  @override
  String get libraryFilterTitle => 'Фільтри';

  @override
  String get libraryFilterReset => 'Скинути';

  @override
  String get libraryFilterApply => 'Застосувати';

  @override
  String get libraryFilterSource => 'Джерело';

  @override
  String get libraryFilterQuality => 'Якість';

  @override
  String get libraryFilterQualityHiRes =>
      'Висока роздільна здатність (24 біти)';

  @override
  String get libraryFilterQualityCD => 'CD (16-бітний)';

  @override
  String get libraryFilterQualityLossy => 'Із втратами (lossy)';

  @override
  String get libraryFilterFormat => 'Формат';

  @override
  String get libraryFilterMetadata => 'Метадані';

  @override
  String get libraryFilterMetadataComplete => 'Повні метадані';

  @override
  String get libraryFilterMetadataMissingAny => 'будь-які метадані';

  @override
  String get libraryFilterMetadataMissingYear => 'Відсутній рік';

  @override
  String get libraryFilterMetadataMissingGenre => 'Відсутній жанр';

  @override
  String get libraryFilterMetadataMissingAlbumArtist =>
      'Відсутній виконавець альбому';

  @override
  String get libraryFilterSort => 'Сортувати';

  @override
  String get libraryFilterSortLatest => 'Найновіші';

  @override
  String get libraryFilterSortOldest => 'Найстаріші';

  @override
  String get libraryFilterSortAlbumAsc => 'Альбом (А-Я)';

  @override
  String get libraryFilterSortAlbumDesc => 'Альбом (Я-А)';

  @override
  String get libraryFilterSortGenreAsc => 'Жанр (А-Я)';

  @override
  String get libraryFilterSortGenreDesc => 'Жанр (Я-А)';

  @override
  String get timeJustNow => 'Щойно';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хвилин тому',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count годин тому',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get tutorialWelcomeTitle => 'Ласкаво просимо до SpotiFLAC!';

  @override
  String get tutorialWelcomeDesc =>
      'Давайте дізнаємося, як завантажувати улюблену музику в якості без втрат. Цей короткий посібник покаже вам основи.';

  @override
  String get tutorialWelcomeTip1 =>
      'Завантажуйте музику зі Spotify, Deezer або вставляйте будь-яку підтримувану URL-адресу';

  @override
  String get tutorialWelcomeTip2 =>
      'Отримуйте аудіо у якості FLAC з Tidal, Qobuz або Deezer';

  @override
  String get tutorialWelcomeTip3 =>
      'Автоматичне додавання метаданих, обкладинки та текстів пісень';

  @override
  String get tutorialSearchTitle => 'Пошук музики';

  @override
  String get tutorialSearchDesc =>
      'Існує два простих способи знайти музику, яку ви хочете завантажити.';

  @override
  String get tutorialDownloadTitle => 'Завантаження музики';

  @override
  String get tutorialDownloadDesc =>
      'Завантаження музики просте та швидке. Ось як це працює.';

  @override
  String get tutorialLibraryTitle => 'Ваша бібліотека';

  @override
  String get tutorialLibraryDesc =>
      'Вся завантажена музика організована на вкладці «Бібліотека».';

  @override
  String get tutorialLibraryTip1 =>
      'Перегляд стану завантаження та черги на вкладці «Бібліотека»';

  @override
  String get tutorialLibraryTip2 =>
      'Торкніться будь-якої композиції, щоб відтворити її за допомогою музичного плеєра';

  @override
  String get tutorialLibraryTip3 =>
      'Перемикання між списком та сіткою для кращого перегляду';

  @override
  String get tutorialExtensionsTitle => 'Розширення';

  @override
  String get tutorialExtensionsDesc =>
      'Розширте можливості програми за допомогою розширень спільноти.';

  @override
  String get tutorialExtensionsTip1 =>
      'Перегляньте вкладку «Репозиторій», щоб знайти корисні розширення';

  @override
  String get tutorialExtensionsTip2 =>
      'Додавайте нових постачальників послуг завантаження або джерела пошуку';

  @override
  String get tutorialExtensionsTip3 =>
      'Отримайте тексти пісень, розширені метадані та інші функції';

  @override
  String get tutorialSettingsTitle => 'Налаштуйте свій досвід';

  @override
  String get tutorialSettingsDesc =>
      'Персоналізуйте програму в налаштуваннях відповідно до ваших уподобань.';

  @override
  String get tutorialSettingsTip1 =>
      'Змініть місце завантаження та організації папок';

  @override
  String get tutorialSettingsTip2 =>
      'Встановіть параметри якості звуку та формату за замовчуванням';

  @override
  String get tutorialSettingsTip3 =>
      'Налаштуйте тему та зовнішній вигляд програми';

  @override
  String get tutorialReadyMessage =>
      'Готово! Почніть завантажувати свою улюблену музику прямо зараз.';

  @override
  String get libraryForceFullScan => 'Примусове повне сканування';

  @override
  String get libraryForceFullScanSubtitle =>
      'Пересканувати всі файли, ігноруючи кеш';

  @override
  String get cleanupOrphanedDownloads => 'Очищення застарілих завантажень';

  @override
  String get cleanupOrphanedDownloadsSubtitle =>
      'Видалити записи історії для файлів, яких більше не існує';

  @override
  String cleanupOrphanedDownloadsResult(int count) {
    return 'Видалено $count утрачених записів з історії';
  }

  @override
  String get cleanupOrphanedDownloadsNone => 'Не знайдено утрачених записів';

  @override
  String get cacheTitle => 'Зберігання та кеш';

  @override
  String get cacheSummaryTitle => 'Огляд кешу';

  @override
  String get cacheSummarySubtitle =>
      'Очищення кешу не призведе до видалення завантажених музичних файлів.';

  @override
  String cacheEstimatedTotal(String size) {
    return 'Орієнтовне використання кешу: $size';
  }

  @override
  String get cacheSectionStorage => 'Кешовані дані';

  @override
  String get cacheSectionMaintenance => 'Технічне обслуговування';

  @override
  String get cacheAppDirectory => 'Каталог кешу додатка';

  @override
  String get cacheAppDirectoryDesc =>
      'HTTP-відповіді, дані WebView та інші тимчасові дані додатків.';

  @override
  String get cacheTempDirectory => 'Тимчасовий каталог';

  @override
  String get cacheTempDirectoryDesc =>
      'Тимчасові файли із завантажень та конвертації аудіо.';

  @override
  String get cacheCoverImage => 'Кеш зображень обкладинок';

  @override
  String get cacheCoverImageDesc =>
      'Завантажено обкладинку альбому та треку. Завантаження відбудеться повторно після перегляду.';

  @override
  String get cacheLibraryCover => 'Кеш бібліотеки обкладинок';

  @override
  String get cacheLibraryCoverDesc =>
      'Обкладинку витягнуто з локальних музичних файлів. Буде повторно витягнуто під час наступного сканування.';

  @override
  String get cacheExploreFeed => 'Огляд кешу стрічки';

  @override
  String get cacheExploreFeedDesc =>
      'Переглянути вміст вкладки (нові випуски, тренди). Оновиться під час наступного відвідування.';

  @override
  String get cacheTrackLookup => 'Відстеження кешу пошуку';

  @override
  String get cacheTrackLookupDesc =>
      'Пошук ідентифікаторів треків Spotify/Deezer. Очищення може уповільнити наступні кілька пошуків.';

  @override
  String get cacheCleanupUnusedDesc =>
      'Видалити історію втрачених завантажень та записи бібліотеки для відсутніх файлів.';

  @override
  String get cacheNoData => 'Кешованих даних немає';

  @override
  String cacheSizeWithFiles(String size, int count) {
    return '$size у $count файлах';
  }

  @override
  String cacheSizeOnly(String size) {
    return '$size';
  }

  @override
  String cacheEntries(int count) {
    return '$count записів';
  }

  @override
  String cacheClearSuccess(String target) {
    return 'Очищено: $target';
  }

  @override
  String get cacheClearConfirmTitle => 'Очистити кеш?';

  @override
  String cacheClearConfirmMessage(String target) {
    return 'Це очистить кешовані дані для $target. Завантажені музичні файли не будуть видалені.';
  }

  @override
  String get cacheClearAllConfirmTitle => 'Очистити увесь кеш?';

  @override
  String get cacheClearAllConfirmMessage =>
      'Це очистить усі категорії кешу на цій сторінці. Завантажені музичні файли не будуть видалені.';

  @override
  String get cacheClearAll => 'Очистити весь кеш';

  @override
  String get cacheCleanupUnused => 'Очищення невикористаних даних';

  @override
  String get cacheCleanupUnusedSubtitle =>
      'Видалити історію утрачених завантажень файлів та відсутні записи бібліотеки';

  @override
  String cacheCleanupResult(int downloadCount, int libraryCount) {
    return 'Очищення завершено: $downloadCount утрачених завантажень, $libraryCount відсутніх записів бібліотеки';
  }

  @override
  String get cacheRefreshStats => 'Оновити статистику';

  @override
  String get trackSaveCoverArt => 'Зберегти обкладинку';

  @override
  String get trackSaveCoverArtSubtitle =>
      'Зберегти обкладинку альбому як файл .jpg';

  @override
  String get trackSaveLyrics => 'Зберегти текст пісні (.lrc)';

  @override
  String get trackSaveLyricsSubtitle =>
      'Отримати та зберегти текст пісні у форматі .lrc';

  @override
  String get trackSaveLyricsProgress => 'Збереження тексту пісні...';

  @override
  String get trackReEnrich => 'Перезбагачувати';

  @override
  String get trackReEnrichOnlineSubtitle =>
      'Пошук метаданих в Інтернеті та вбудовування у файл';

  @override
  String get trackReEnrichFieldsTitle => 'Поля для оновлення';

  @override
  String get trackReEnrichFieldCover => 'Обкладинка';

  @override
  String get trackReEnrichFieldLyrics => 'Тексти пісень';

  @override
  String get trackReEnrichFieldBasicTags => 'Альбом, Виконавець альбому';

  @override
  String get trackReEnrichFieldTrackInfo => 'Номер треку та диска';

  @override
  String get trackReEnrichFieldReleaseInfo => 'Дата та ISRC';

  @override
  String get trackReEnrichFieldExtra => 'Жанр, Лейбл, Авторське право';

  @override
  String get trackReEnrichSelectAll => 'Вибрати все';

  @override
  String get trackEditMetadata => 'Редагувати метадані';

  @override
  String trackCoverSaved(String fileName) {
    return 'Обкладинку збережено до $fileName';
  }

  @override
  String get trackCoverNoSource => 'Джерело обкладинки недоступне';

  @override
  String trackLyricsSaved(String fileName) {
    return 'Текст пісні збережено в $fileName';
  }

  @override
  String get trackReEnrichProgress => 'Повторне збагачення метаданих...';

  @override
  String get trackReEnrichSearching => 'Пошук метаданих в Інтернеті...';

  @override
  String get trackReEnrichSuccess => 'Метадані повторно збагачені успішно';

  @override
  String get trackReEnrichFfmpegFailed =>
      'Не вдалося вбудувати метадані FFmpeg';

  @override
  String get queueFlacAction => 'Черга FLAC';

  @override
  String queueFlacConfirmMessage(int count) {
    return 'Пошук онлайн-збігів для вибраних треків та додавання завантажень FLAC до черги.\n\nІснуючі файли не будуть змінені або видалені.\n\nАвтоматично додаються до черги лише збіги з високою достовірністю.\n\n$count вибрано';
  }

  @override
  String queueFlacFindingProgress(int current, int total) {
    return 'Пошук FLAC-збігів... ($current/$total)';
  }

  @override
  String get queueFlacNoReliableMatches =>
      'Не знайдено надійних онлайн-відповідей для вибраного запиту';

  @override
  String queueFlacQueuedWithSkipped(int addedCount, int skippedCount) {
    return 'Додано $addedCount треків до черги, пропущено $skippedCount';
  }

  @override
  String trackSaveFailed(String error) {
    return 'Не вдалося: $error';
  }

  @override
  String get trackConvertFormat => 'Конвертувати формат';

  @override
  String get trackConvertFormatSubtitle =>
      'Convert to AAC/M4A, MP3, Opus, ALAC, or FLAC';

  @override
  String get trackConvertTitle => 'Конвертувати аудіо';

  @override
  String get trackConvertTargetFormat => 'Цільовий формат';

  @override
  String get trackConvertBitrate => 'Бітрейт';

  @override
  String get trackConvertConfirmTitle => 'Підтвердити конверсію';

  @override
  String trackConvertConfirmMessage(
    String sourceFormat,
    String targetFormat,
    String bitrate,
  ) {
    return 'Конвертувати з $sourceFormat в $targetFormat із бітрейтом $bitrate?\n\nОригінальний файл буде видалено після конвертації.';
  }

  @override
  String trackConvertConfirmMessageLossless(
    String sourceFormat,
    String targetFormat,
  ) {
    return 'Конвертувати з $sourceFormat у $targetFormat? (Lossless — без втрати якості)\n\nОригінальний файл буде видалено після конвертації.';
  }

  @override
  String get trackConvertLosslessHint =>
      'Lossless конвертація — без втрати якості';

  @override
  String get trackConvertConverting => 'Конвертування аудіо...';

  @override
  String trackConvertSuccess(String format) {
    return 'Конвертовано в $format успішно';
  }

  @override
  String get trackConvertFailed => 'Конвертація не вдалася';

  @override
  String get cueSplitTitle => 'Розділений аркуш CUE';

  @override
  String get cueSplitSubtitle => 'Розділення CUE+FLAC на окремі треки';

  @override
  String cueSplitAlbum(String album) {
    return 'Альбом: $album';
  }

  @override
  String cueSplitArtist(String artist) {
    return 'Артист: $artist';
  }

  @override
  String cueSplitTrackCount(int count) {
    return '$count треків';
  }

  @override
  String get cueSplitConfirmTitle => 'Розділений альбом CUE';

  @override
  String cueSplitConfirmMessage(String album, int count) {
    return 'Розділити \"$album\" на $count окремих FLAC-файлів?\n\nФайли будуть збережені в одному каталозі.';
  }

  @override
  String cueSplitSplitting(int current, int total) {
    return 'Розділення аркуша CUE... ($current/$total)';
  }

  @override
  String cueSplitSuccess(int count) {
    return 'Розділено на $count треків успішно';
  }

  @override
  String get cueSplitFailed => 'Розділення CUE не вдалося';

  @override
  String get cueSplitNoAudioFile =>
      'Аудіофайл для цього аркуша CUE не знайдено';

  @override
  String get cueSplitButton => 'Розділити на треки';

  @override
  String get actionCreate => 'Створити';

  @override
  String get collectionFoldersTitle => 'Мої папки';

  @override
  String get collectionWishlist => 'Список бажань';

  @override
  String get collectionLoved => 'Вподобані';

  @override
  String get collectionFavoriteArtists => 'Favorite Artists';

  @override
  String get collectionPlaylists => 'Списки відтворення';

  @override
  String get collectionPlaylist => 'Список відтворення';

  @override
  String get collectionAddToPlaylist => 'Додати до списку відтворення';

  @override
  String get collectionCreatePlaylist => 'Створити плейлист';

  @override
  String get collectionNoPlaylistsYet => 'Поки що немає списків відтворення';

  @override
  String get collectionNoPlaylistsSubtitle =>
      'Створіть список відтворення, щоб розпочати категоризацію треків';

  @override
  String collectionPlaylistTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треків',
      one: '1 трек',
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
    return 'Додано до \"$playlistName\"';
  }

  @override
  String collectionAlreadyInPlaylist(String playlistName) {
    return 'Вже у списку відтворення \"$playlistName\"';
  }

  @override
  String get collectionPlaylistCreated => 'Список відтворення створено';

  @override
  String get collectionPlaylistNameHint => 'Назва списку відтворення';

  @override
  String get collectionPlaylistNameRequired =>
      'Потрібно вказати назву списку відтворення';

  @override
  String get collectionRenamePlaylist => 'Перейменувати список відтворення';

  @override
  String get collectionDeletePlaylist => 'Видалити список відтворення';

  @override
  String collectionDeletePlaylistMessage(String playlistName) {
    return 'Видалити \"$playlistName\" та всі треки в ньому?';
  }

  @override
  String get collectionPlaylistDeleted => 'Список відтворення видалено';

  @override
  String get collectionPlaylistRenamed => 'Список відтворення перейменовано';

  @override
  String get collectionWishlistEmptyTitle => 'Список бажань порожній';

  @override
  String get collectionWishlistEmptySubtitle =>
      'Натисніть + на треках, щоб зберегти те, що ви хочете завантажити пізніше';

  @override
  String get collectionLovedEmptyTitle => 'Папка \"Улюблені\" порожня';

  @override
  String get collectionLovedEmptySubtitle =>
      'Натисніть «Подобається» на треках, щоб зберегти у свої улюблені';

  @override
  String get collectionFavoriteArtistsEmptyTitle => 'No favorite artists yet';

  @override
  String get collectionFavoriteArtistsEmptySubtitle =>
      'Tap the heart on an artist page to keep them here';

  @override
  String get collectionPlaylistEmptyTitle => 'Список відтворення порожній';

  @override
  String get collectionPlaylistEmptySubtitle =>
      'Тривале натискання + на будь-якій доріжці додасть її сюди';

  @override
  String get collectionRemoveFromPlaylist => 'Видалити зі списку відтворення';

  @override
  String get collectionRemoveFromFolder => 'Видалити з папки';

  @override
  String collectionRemoved(String trackName) {
    return '\"$trackName\" видалено';
  }

  @override
  String collectionAddedToLoved(String trackName) {
    return '\"$trackName\" додано до списку улюблених';
  }

  @override
  String collectionRemovedFromLoved(String trackName) {
    return '\"$trackName\" видалено з уподобань';
  }

  @override
  String collectionAddedToWishlist(String trackName) {
    return '\"$trackName\" додано до списку бажань';
  }

  @override
  String collectionRemovedFromWishlist(String trackName) {
    return '\"$trackName\" видалено зі списку бажань';
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
  String get trackOptionAddToLoved => 'Додати до улюблених';

  @override
  String get trackOptionRemoveFromLoved => 'Видалити з улюблених';

  @override
  String get trackOptionAddToWishlist => 'Додати до списку бажань';

  @override
  String get trackOptionRemoveFromWishlist => 'Видалити зі списку бажань';

  @override
  String get artistOptionAddToFavorites => 'Add to Favorite Artists';

  @override
  String get artistOptionRemoveFromFavorites => 'Remove from Favorite Artists';

  @override
  String get collectionPlaylistChangeCover => 'Змінити зображення обкладинки';

  @override
  String get collectionPlaylistRemoveCover => 'Видалити зображення обкладинки';

  @override
  String selectionShareCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Поділитися $count $_temp0';
  }

  @override
  String get selectionShareNoFiles =>
      'Файлів для спільного доступу не знайдено';

  @override
  String selectionConvertCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Конвертувати $count $_temp0';
  }

  @override
  String get selectionConvertNoConvertible =>
      'Трансформованих треків не вибрано';

  @override
  String get selectionBatchConvertConfirmTitle => 'Пакетне конвертування';

  @override
  String selectionBatchConvertConfirmMessage(
    int count,
    String format,
    String bitrate,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Конвертувати $count $_temp0 у $format з бітрейтом $bitrate?\n\nОригінальні файли будуть видалені після конвертації.';
  }

  @override
  String selectionBatchConvertConfirmMessageLossless(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    return 'Конвертувати $count $_temp0 у $format? (Lossless — без втрати якості)\n\nОригінальні файли будуть видалені після конвертації.';
  }

  @override
  String selectionBatchConvertProgress(int current, int total) {
    return 'Конвертування $current з $total...';
  }

  @override
  String selectionBatchConvertSuccess(int success, int total, String format) {
    return 'Конвертовано $success з $total треків у $format';
  }

  @override
  String downloadedAlbumDownloadedCount(int count) {
    return '$count завантажено';
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
      'Увімкнення, вимкнення та зміна порядку джерел текстів пісень. Постачальники перевірятимуть зверху вниз, доки не буде знайдено текст пісні.';

  @override
  String get lyricsProvidersInfoText =>
      'Постачальники розширених текстів пісень завжди запускаються перед вбудованими постачальниками. Принаймні один постачальник має залишатися ввімкненим.';

  @override
  String lyricsProvidersEnabledSection(int count) {
    return 'Увімкнено ($count)';
  }

  @override
  String lyricsProvidersDisabledSection(int count) {
    return 'Вимкнено ($count)';
  }

  @override
  String get lyricsProvidersAtLeastOne =>
      'Принаймні один постачальник має залишатися ввімкненим';

  @override
  String get lyricsProvidersSaved =>
      'Пріоритет постачальника текстів пісень збережено';

  @override
  String get lyricsProvidersDiscardContent =>
      'У вас є незбережені зміни, які буде втрачено.';

  @override
  String get lyricsProviderLrclibDesc =>
      'Синхронізована база даних текстів пісень з відкритим кодом';

  @override
  String get lyricsProviderNeteaseDesc =>
      'NetEase Cloud Music (добре підходить для азійських пісень)';

  @override
  String get lyricsProviderMusixmatchDesc =>
      'Найбільша база даних текстів пісень (багатомовна)';

  @override
  String get lyricsProviderAppleMusicDesc =>
      'Синхронізовані тексти пісень слово за словом (через проксі)';

  @override
  String get lyricsProviderQqMusicDesc =>
      'QQ Music (добре для китайських пісень, через проксі)';

  @override
  String get lyricsProviderExtensionDesc => 'Постачальник розширень';

  @override
  String get safMigrationTitle => 'Потрібне оновлення сховища';

  @override
  String get safMigrationMessage1 =>
      'SpotiFLAC тепер використовує Android Storage Access Framework (SAF) для завантажень. Це виправляє помилки «відмовлено в доступі» на Android 10+.';

  @override
  String get safMigrationMessage2 =>
      'Будь ласка, виберіть папку завантажень ще раз, щоб перейти до нової системи зберігання.';

  @override
  String get safMigrationSuccess => 'Папку завантажень оновлено до режиму SAF';

  @override
  String get settingsDonate => 'Support Development';

  @override
  String get settingsDonateSubtitle => 'Buy the developer a coffee';

  @override
  String get tooltipLoveAll => 'Уподобати всіх';

  @override
  String get tooltipAddToPlaylist => 'Додати до списку відтворення';

  @override
  String snackbarRemovedTracksFromLoved(int count) {
    return 'Видалено $count треків з уподобань';
  }

  @override
  String snackbarAddedTracksToLoved(int count) {
    return 'Додано $count треків до списку \"Улюблені\"';
  }

  @override
  String get dialogDownloadAllTitle => 'Завантажити все';

  @override
  String dialogDownloadAllMessage(int count) {
    return 'Завантажити $count треків?';
  }

  @override
  String get homeSkipAlreadyDownloaded => 'Пропустити вже завантажені пісні';

  @override
  String get homeGoToAlbum => 'Перейти до альбому';

  @override
  String get homeAlbumInfoUnavailable => 'Інформація про альбом недоступна';

  @override
  String get snackbarLoadingCueSheet => 'Завантаження аркуша CUE...';

  @override
  String get snackbarMetadataSaved => 'Метадані успішно збережено';

  @override
  String get snackbarFailedToEmbedLyrics => 'Не вдалося вставити текст пісні';

  @override
  String get snackbarFailedToWriteStorage =>
      'Не вдалося перезаписати у сховище';

  @override
  String snackbarError(String error) {
    return 'Помилка: $error';
  }

  @override
  String get snackbarNoActionDefined =>
      'Для цієї кнопки не визначено жодної дії';

  @override
  String get noTracksFoundForAlbum =>
      'Для цього альбому не знайдено жодних треків';

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
  String get downloadFilenameInsertTag => 'Натисніть, щоб вставити тег:';

  @override
  String get downloadSeparateSinglesEnabled =>
      'Singles and EPs saved in a separate folder';

  @override
  String get downloadSeparateSinglesDisabled =>
      'Singles and albums saved in the same folder';

  @override
  String get downloadArtistNameFilters => 'Фільтри імені виконавця';

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
  String get downloadSongLinkRegion => 'Регіон SongLink';

  @override
  String get downloadNetworkCompatibilityMode => 'Network Compatibility Mode';

  @override
  String get downloadNetworkCompatibilityModeEnabled =>
      'Using legacy TLS settings for older networks';

  @override
  String get downloadNetworkCompatibilityModeDisabled =>
      'Using standard network settings';

  @override
  String get downloadSelectServiceToEnable =>
      'Select Tidal or Qobuz to enable this option';

  @override
  String get downloadSelectTidalQobuz =>
      'Select Tidal or Qobuz to choose audio quality';

  @override
  String get downloadEmbedLyricsDisabled => 'Enable metadata embedding first';

  @override
  String get downloadNeteaseIncludeTranslation => 'Netease: Включити переклад';

  @override
  String get downloadNeteaseIncludeTranslationEnabled =>
      'Chinese translation lines included';

  @override
  String get downloadNeteaseIncludeTranslationDisabled =>
      'Original lyrics only';

  @override
  String get downloadNeteaseIncludeRomanization =>
      'Netease: Включити романізацію';

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
  String get downloadMusixmatchLanguage => 'Мова Musixmatch';

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
  String get downloadMusixmatchLanguageCode => 'Код мови';

  @override
  String get downloadMusixmatchLanguageHint => 'e.g. en, de, ja';

  @override
  String get downloadMusixmatchLanguageDesc =>
      'Enter a BCP-47 language code (e.g. en, de, ja) to request translated lyrics from Musixmatch.';

  @override
  String get downloadMusixmatchAuto => 'Авто';

  @override
  String get downloadNetworkAnySubtitle => 'Use WiFi or mobile data';

  @override
  String get downloadNetworkWifiOnlySubtitle =>
      'Downloads pause when on mobile data';

  @override
  String get downloadSongLinkRegionDesc =>
      'Region used when resolving track links via SongLink. Choose the country where your streaming services are available.';

  @override
  String get snackbarUnsupportedAudioFormat => 'Непідтримуваний аудіоформат';

  @override
  String get cacheRefresh => 'Оновити';

  @override
  String dialogDownloadPlaylistsMessage(int trackCount, int playlistCount) {
    String _temp0 = intl.Intl.pluralLogic(
      trackCount,
      locale: localeName,
      other: 'треків',
      one: 'трек',
    );
    String _temp1 = intl.Intl.pluralLogic(
      playlistCount,
      locale: localeName,
      other: 'плейлистів',
      one: 'плейлист',
    );
    return 'Завантажити $trackCount $_temp0 з $playlistCount $_temp1?';
  }

  @override
  String bulkDownloadPlaylistsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'плейлистів',
      one: 'плейлист',
    );
    return 'Завантажити $count $_temp0';
  }

  @override
  String get bulkDownloadSelectPlaylists =>
      'Вибрати списки відтворення для завантаження';

  @override
  String get snackbarSelectedPlaylistsEmpty =>
      'Вибрані списки відтворення не містять треків';

  @override
  String playlistsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count плейлистів',
      one: '1 плейлист',
    );
    return '$_temp0';
  }

  @override
  String get editMetadataAutoFill => 'Автоматичне заповнення з онлайн-ресурсів';

  @override
  String get editMetadataAutoFillDesc =>
      'Виберіть поля для автоматичного заповнення з онлайн-метаданих';

  @override
  String get editMetadataAutoFillFetch => 'Отримання та заповнення';

  @override
  String get editMetadataAutoFillSearching => 'Пошук в Інтернеті...';

  @override
  String get editMetadataAutoFillNoResults =>
      'Відповідних метаданих в Інтернеті не знайдено';

  @override
  String editMetadataAutoFillDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'полей',
      one: 'поле',
    );
    return 'Заповнено $count $_temp0 з онлайн-метаданих';
  }

  @override
  String get editMetadataAutoFillNoneSelected =>
      'Виберіть принаймні одне поле для автоматичного заповнення';

  @override
  String get editMetadataFieldTitle => 'Назва';

  @override
  String get editMetadataFieldArtist => 'Виконавець';

  @override
  String get editMetadataFieldAlbum => 'Альбом';

  @override
  String get editMetadataFieldAlbumArtist => 'Виконавець альбому';

  @override
  String get editMetadataFieldDate => 'Дата';

  @override
  String get editMetadataFieldTrackNum => 'Номер треку';

  @override
  String get editMetadataFieldDiscNum => 'Номер диска';

  @override
  String get editMetadataFieldGenre => 'Жанр';

  @override
  String get editMetadataFieldIsrc => 'ISRC';

  @override
  String get editMetadataFieldLabel => 'Лейбл';

  @override
  String get editMetadataFieldCopyright => 'Авторське право';

  @override
  String get editMetadataFieldCover => 'Обкладинка';

  @override
  String get editMetadataSelectAll => 'Усі';

  @override
  String get editMetadataSelectEmpty => 'Порожні (без мета даних)';

  @override
  String queueDownloadingCount(int count) {
    return 'Завантаження ($count)';
  }

  @override
  String get queueDownloadedHeader => 'Завантажено';

  @override
  String get queueFilteringIndicator => 'Фільтрування...';

  @override
  String queueTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треків',
      one: '1 трек',
    );
    return '$_temp0';
  }

  @override
  String queueAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count альбомів',
      one: '1 альбом',
    );
    return '$_temp0';
  }

  @override
  String get queueEmptyAlbums => 'Немає завантажень альбомів';

  @override
  String get queueEmptyAlbumsSubtitle =>
      'Завантажте кілька треків з альбому, щоб переглянути їх тут';

  @override
  String get queueEmptySingles => 'Без окремих завантажень';

  @override
  String get queueEmptySinglesSubtitle =>
      'Завантаження окремих треків з’являться тут';

  @override
  String get queueEmptyHistory => 'Немає історії завантажень';

  @override
  String get queueEmptyHistorySubtitle => 'Завантажені треки з’являться тут';

  @override
  String get selectionAllPlaylistsSelected => 'Вибрано всі списки відтворення';

  @override
  String get selectionTapPlaylistsToSelect =>
      'Торкніться списків відтворення, щоб вибрати';

  @override
  String get selectionSelectPlaylistsToDelete =>
      'Вибрати списки відтворення для видалення';

  @override
  String get audioAnalysisTitle => 'Аналіз якості звуку';

  @override
  String get audioAnalysisDescription =>
      'Перевірити якість без втрат за допомогою спектрального аналізу';

  @override
  String get audioAnalysisAnalyzing => 'Аналіз аудіо...';

  @override
  String get audioAnalysisSampleRate => 'Частота дискретизації';

  @override
  String get audioAnalysisCodec => 'Codec';

  @override
  String get audioAnalysisContainer => 'Container';

  @override
  String get audioAnalysisDecodedFormat => 'Decoded Format';

  @override
  String get audioAnalysisBitDepth => 'Глибина бітів';

  @override
  String get audioAnalysisChannels => 'Канали';

  @override
  String get audioAnalysisDuration => 'Тривалість';

  @override
  String get audioAnalysisNyquist => 'Частота Найквіста';

  @override
  String get audioAnalysisFileSize => 'Розмір';

  @override
  String get audioAnalysisDynamicRange => 'Динамічний діапазон';

  @override
  String get audioAnalysisPeak => 'Пік';

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
  String get audioAnalysisSamples => 'Семпли';

  @override
  String get audioAnalysisRescan => 'Re-analyze';

  @override
  String get audioAnalysisRescanning => 'Re-analyzing audio...';

  @override
  String extensionsSearchWith(String providerName) {
    return 'Пошук за допомогою$providerName';
  }

  @override
  String get extensionsHomeFeedProvider =>
      'Постачальник оновлень домашньої стрічки';

  @override
  String get extensionsHomeFeedDescription =>
      'Виберіть, яке розширення відображатиме домашню стрічку на головному екрані';

  @override
  String get extensionsHomeFeedAuto => 'Авто';

  @override
  String get extensionsHomeFeedAutoSubtitle =>
      'Автоматично вибирати найкращий доступний';

  @override
  String get extensionsHomeFeedOff => 'Off';

  @override
  String get extensionsHomeFeedOffSubtitle =>
      'Do not show the home feed on the main screen';

  @override
  String extensionsHomeFeedUse(String extensionName) {
    return 'Використовувати $extensionName головну стрічку';
  }

  @override
  String get extensionsNoHomeFeedExtensions =>
      'Без розширень із домашньою стрічкою';

  @override
  String get sortAlphaAsc => 'А-Я';

  @override
  String get sortAlphaDesc => 'Я-А';

  @override
  String get cancelDownloadTitle => 'Скасувати завантаження?';

  @override
  String cancelDownloadContent(String trackName) {
    return 'Це скасує активне завантаження треку \"$trackName\".';
  }

  @override
  String get cancelDownloadKeep => 'Зберегти';

  @override
  String get metadataSaveFailedFfmpeg =>
      'Не вдалося зберегти метадані через FFmpeg';

  @override
  String get metadataSaveFailedStorage =>
      'Не вдалося записати метадані назад у сховище';

  @override
  String snackbarFolderPickerFailed(String error) {
    return 'Не вдалося відкрити засіб вибору папок: $error';
  }

  @override
  String get errorLoadAlbum => 'Не вдалося завантажити альбом';

  @override
  String get errorLoadPlaylist => 'Не вдалося завантажити список відтворення';

  @override
  String get errorLoadArtist => 'Не вдалося завантажити артиста';

  @override
  String get notifChannelDownloadName => 'Прогрес завантаження';

  @override
  String get notifChannelDownloadDesc => 'Показує прогрес завантаження треків';

  @override
  String get notifChannelLibraryScanName => 'Сканування бібліотеки';

  @override
  String get notifChannelLibraryScanDesc =>
      'Показує перебіг сканування локальної бібліотеки';

  @override
  String notifDownloadingTrack(String trackName) {
    return 'Завантаження $trackName';
  }

  @override
  String notifFinalizingTrack(String trackName) {
    return 'Фіналізація $trackName';
  }

  @override
  String get notifEmbeddingMetadata => 'Вбудовування метаданих...';

  @override
  String notifAlreadyInLibraryCount(int completed, int total) {
    return 'Вже в бібліотеці ($completed/$total)';
  }

  @override
  String get notifAlreadyInLibrary => 'Вже в бібліотеці';

  @override
  String notifDownloadCompleteCount(int completed, int total) {
    return 'Завантаження завершено ($completed/$total)';
  }

  @override
  String get notifDownloadComplete => 'Завантаження завершено';

  @override
  String notifDownloadsFinished(int completed, int failed) {
    return 'Завантаження завершено ($completed завершено, $failed не вдалося)';
  }

  @override
  String get notifAllDownloadsComplete => 'Усі завантаження завершено';

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
  String get notifScanningLibrary => 'Сканування локальної бібліотеки';

  @override
  String notifLibraryScanProgressWithTotal(
    int scanned,
    int total,
    int percentage,
  ) {
    return '$scanned/$total файлів • $percentage%';
  }

  @override
  String notifLibraryScanProgressNoTotal(int scanned, int percentage) {
    return '$scanned файлів скановано • $percentage%';
  }

  @override
  String get notifLibraryScanComplete => 'Сканування бібліотеки завершено';

  @override
  String notifLibraryScanCompleteBody(int count) {
    return '$count треків індексовано';
  }

  @override
  String notifLibraryScanExcluded(int count) {
    return '$count виключені';
  }

  @override
  String notifLibraryScanErrors(int count) {
    return '$count помилок';
  }

  @override
  String get notifLibraryScanFailed => 'Не вдалося сканувати бібліотеку';

  @override
  String get notifLibraryScanCancelled => 'Сканування бібліотеки скасовано';

  @override
  String get notifLibraryScanStopped => 'Сканування зупинено до завершення.';

  @override
  String notifDownloadingUpdate(String version) {
    return 'Downloading SpotiFLAC Mobile v$version';
  }

  @override
  String notifUpdateProgress(String received, String total, int percentage) {
    return '$received / $total МБ • $percentage%';
  }

  @override
  String get notifUpdateReady => 'Оновлення готове';

  @override
  String notifUpdateReadyBody(String version) {
    return 'SpotiFLAC Mobile v$version downloaded. Tap to install.';
  }

  @override
  String get notifUpdateFailed => 'Не вдалося оновити';

  @override
  String get notifUpdateFailedBody =>
      'Не вдалося завантажити оновлення. Спробуйте пізніше.';

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
