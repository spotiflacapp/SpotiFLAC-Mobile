part of 'track_metadata_screen.dart';

const _trackMetadataHeroScheme = ColorScheme.dark(
  surface: Colors.black,
  onSurface: Colors.white,
  onSurfaceVariant: Colors.white70,
);

extension _TrackMetadataCards on _TrackMetadataScreenState {
  Widget _buildAnimatedTrackContent(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    final currentKey = ValueKey<String>('metadata_content_$_itemId');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        if (_metadataTransitionDirection == 0) {
          return child;
        }
        final isIncoming = child.key == currentKey;
        final direction = _metadataTransitionDirection.toDouble();
        final begin = Offset(
          isIncoming ? 0.18 * direction : -0.18 * direction,
          0,
        );
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Padding(
        key: currentKey,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetadataCard(context, colorScheme, _fileSize),

            const SizedBox(height: 16),

            _buildFileInfoCard(context, colorScheme, _fileExists, _fileSize),

            const SizedBox(height: 16),

            _buildLyricsCard(context, colorScheme),

            if (_fileExists) ...[
              const SizedBox(height: 16),
              AudioAnalysisCard(
                filePath: _filePath,
                codecHint: _storedAudioFormat,
              ),
            ],

            const SizedBox(height: 24),

            _buildActionButtons(context, ref, colorScheme, _fileExists),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBackground(
    BuildContext context,
    ColorScheme colorScheme,
    double expandedHeight,
    bool showContent,
  ) {
    final cacheWidth = coverCacheWidthForViewport(context);
    Widget coverImage() => _hasPath(_embeddedCoverPreviewPath)
        ? Image.file(
            File(_embeddedCoverPreviewPath!),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : _coverUrl != null
        ? CachedCoverImage(
            imageUrl: _coverUrl!,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            placeholder: (_, _) => Container(color: colorScheme.surface),
            errorWidget: (_, _, _) => Container(color: colorScheme.surface),
          )
        : _localCoverPath != null && _localCoverPath!.isNotEmpty
        ? Image.file(
            File(_localCoverPath!),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.music_note,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    // Centered square cover over a blurred backdrop (same layout as the album
    // header) so the Hero flight from a list thumbnail keeps its square shape.
    final coverSize = (MediaQuery.sizeOf(context).width * 0.5)
        .clamp(150.0, 210.0)
        .toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: coverImage(),
        ),
        Container(color: Colors.black.withValues(alpha: 0.35)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: expandedHeight * 0.65,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 40,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: showContent ? 1.0 : 0.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: _coverHeroTag,
                  child: Container(
                    width: coverSize,
                    height: coverSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: coverSize,
                        height: coverSize,
                        child: coverImage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  trackName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  artistName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  albumName,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                HeaderPalette(
                  scheme: _trackMetadataHeroScheme,
                  child: HeaderMetaRow(
                    items: [
                      if (_displayAudioQuality != null &&
                          _displayAudioQuality!.isNotEmpty)
                        HeaderMetaItem(_displayAudioQuality!),
                      if (duration != null)
                        HeaderMetaItem(formatClock(duration!)),
                      if (_service != 'local')
                        HeaderMetaItem(
                          _service[0].toUpperCase() + _service.substring(1),
                        )
                      else
                        HeaderMetaItem(
                          context.l10n.librarySourceLocal,
                          icon: Icons.folder,
                        ),
                      if (_hasCheckedFile && !_fileExists)
                        HeaderMetaItem(
                          context.l10n.trackFileNotFound,
                          icon: Icons.warning_rounded,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  RoundedRectangleBorder _sectionCardShape(ColorScheme colorScheme) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildMetadataCard(
    BuildContext context,
    ColorScheme colorScheme,
    int? fileSize,
  ) {
    return Card(
      elevation: 0,
      color: settingsGroupColor(context),
      shape: _sectionCardShape(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackMetadata,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildMetadataGrid(context, colorScheme),

            if (_spotifyId != null && _spotifyId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final openService = _serviceForTrackId(
                    _spotifyId!,
                    fallbackService: _service.toLowerCase(),
                  );
                  String buttonLabel;
                  if (openService == MusicServices.deezer) {
                    buttonLabel = context.l10n.trackOpenInDeezer;
                  } else if (openService == MusicServices.amazon) {
                    buttonLabel = context.l10n.trackOpenInService(
                      'Amazon Music',
                    );
                  } else if (openService == MusicServices.tidal) {
                    buttonLabel = context.l10n.trackOpenInService('Tidal');
                  } else if (openService == MusicServices.qobuz) {
                    buttonLabel = context.l10n.trackOpenInService('Qobuz');
                  } else {
                    buttonLabel = context.l10n.trackOpenInSpotify;
                  }
                  return OutlinedButton.icon(
                    onPressed: () => _openServiceUrl(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(buttonLabel),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openServiceUrl(BuildContext context) async {
    if (_spotifyId == null) return;

    final openService = _serviceForTrackId(
      _spotifyId!,
      fallbackService: _service.toLowerCase(),
    );
    final rawId = _displayServiceTrackId(_spotifyId!);

    String webUrl;
    Uri? appUri;
    String serviceName;

    if (openService == MusicServices.deezer) {
      webUrl = 'https://www.deezer.com/track/$rawId';
      appUri = Uri.parse('deezer://www.deezer.com/track/$rawId');
      serviceName = 'Deezer';
    } else if (openService == MusicServices.amazon) {
      webUrl = 'https://music.amazon.com/search/$rawId';
      appUri = Uri.parse('amznm://search/$rawId');
      serviceName = 'Amazon Music';
    } else if (openService == MusicServices.tidal) {
      webUrl = 'https://listen.tidal.com/track/$rawId';
      appUri = Uri.parse('tidal://track/$rawId');
      serviceName = 'Tidal';
    } else if (openService == MusicServices.qobuz) {
      webUrl = 'https://play.qobuz.com/track/$rawId';
      appUri = Uri.parse('qobuz://track/$rawId');
      serviceName = 'Qobuz';
    } else {
      webUrl = 'https://open.spotify.com/track/$rawId';
      appUri = Uri.parse('spotify:track:$rawId');
      serviceName = 'Spotify';
    }

    try {
      final launched = await launchUrl(
        appUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      try {
        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        if (context.mounted) {
          _copyToClipboard(context, webUrl);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.snackbarUrlCopied(serviceName)),
            ),
          );
        }
      }
    }
  }

  Widget _buildMetadataGrid(BuildContext context, ColorScheme colorScheme) {
    final audioQualityStr = _displayAudioQuality;

    final items = <_MetadataItem>[
      _MetadataItem(context.l10n.trackTrackName, trackName),
      _MetadataItem(context.l10n.trackArtist, artistName),
      if (albumArtist != null && albumArtist != artistName)
        _MetadataItem(context.l10n.trackAlbumArtist, albumArtist!),
      _MetadataItem(context.l10n.trackAlbum, albumName),
      if (trackNumber != null && trackNumber! > 0)
        _MetadataItem(context.l10n.trackTrackNumber, trackNumber.toString()),
      if (totalTracks != null && totalTracks! > 0)
        _MetadataItem(
          context.l10n.editMetadataFieldTrackTotal,
          totalTracks.toString(),
        ),
      if (discNumber != null && discNumber! > 0)
        _MetadataItem(context.l10n.trackDiscNumber, discNumber.toString()),
      if (totalDiscs != null && totalDiscs! > 0)
        _MetadataItem(
          context.l10n.editMetadataFieldDiscTotal,
          totalDiscs.toString(),
        ),
      if (duration != null)
        _MetadataItem(context.l10n.trackDuration, formatClock(duration!)),
      if (audioQualityStr != null)
        _MetadataItem(context.l10n.trackAudioQuality, audioQualityStr),
      if (releaseDate != null && releaseDate!.isNotEmpty)
        _MetadataItem(context.l10n.trackReleaseDate, releaseDate!),
      if (genre != null && genre!.isNotEmpty)
        _MetadataItem(context.l10n.trackGenre, genre!),
      if (label != null && label!.isNotEmpty)
        _MetadataItem(context.l10n.trackLabel, label!),
      if (copyright != null && copyright!.isNotEmpty)
        _MetadataItem(context.l10n.trackCopyright, copyright!),
      if (composer != null && composer!.isNotEmpty)
        _MetadataItem(context.l10n.editMetadataFieldComposer, composer!),
      if (isrc != null && isrc!.isNotEmpty) _MetadataItem('ISRC', isrc!),
    ];

    if (!_isLocalItem && _spotifyId != null && _spotifyId!.isNotEmpty) {
      final idService = _serviceForTrackId(
        _spotifyId!,
        fallbackService: _service.toLowerCase(),
      );
      final cleanId = _displayServiceTrackId(_spotifyId!);
      String idLabel;
      switch (idService) {
        case MusicServices.deezer:
          idLabel = 'Deezer ID';
        case MusicServices.amazon:
          idLabel = 'Amazon ASIN';
        case MusicServices.tidal:
          idLabel = 'Tidal ID';
        case MusicServices.qobuz:
          idLabel = 'Qobuz ID';
        default:
          idLabel = 'Spotify ID';
      }
      items.add(_MetadataItem(idLabel, cleanId));
    }

    items.add(
      _MetadataItem(context.l10n.trackMetadataService, _service.toUpperCase()),
    );
    items.add(
      _MetadataItem(context.l10n.trackDownloaded, _formatFullDate(_addedAt)),
    );

    return Column(
      children: items.map((metadata) {
        final isCopyable =
            metadata.label == 'ISRC' ||
            metadata.label == 'Spotify ID' ||
            metadata.label == 'Deezer ID' ||
            metadata.label == 'Amazon ASIN' ||
            metadata.label == 'Tidal ID' ||
            metadata.label == 'Qobuz ID';
        return InkWell(
          onTap: isCopyable
              ? () => _copyToClipboard(context, metadata.value)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    metadata.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    metadata.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isCopyable)
                  Icon(
                    Icons.copy,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatLabelForRaw(String raw) {
    final normalized = raw.toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'flac' => 'FLAC',
      'alac' => 'ALAC',
      'wav' || 'wave' => 'WAV',
      'aiff' || 'aif' || 'aifc' => 'AIFF',
      'eac3' || 'ec_3' => 'EAC3',
      'ac3' || 'ac_3' => 'AC3',
      'ac4' || 'ac_4' => 'AC4',
      'aac' || 'mp4a' => 'AAC',
      'm4a' || 'mp4' => 'M4A',
      'mp3' => 'MP3',
      'opus' => 'Opus',
      'ogg' => 'OGG',
      _ => raw.toUpperCase(),
    };
  }

  String _displayFormatLabelForFile(String fileName) {
    final storedFormat = normalizeOptionalString(_storedAudioFormat);
    final raw =
        storedFormat ??
        (fileName.contains('.') ? fileName.split('.').last : 'Unknown');
    return _formatLabelForRaw(raw);
  }

  bool _isBitrateFormatLabel(String label) {
    return const {
      'MP3',
      'OPUS',
      'OGG',
      'M4A',
      'AAC',
      'EAC3',
      'AC3',
      'AC4',
    }.contains(label.toUpperCase());
  }

  Widget _buildFileInfoCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool fileExists,
    int? fileSize,
  ) {
    final displayFilePath = _formatPathForDisplay(rawFilePath);
    final fileName = _extractFileNameFromPathOrUri(rawFilePath);
    final fileExtension = _displayFormatLabelForFile(fileName);
    final resolvedQuality = _displayAudioQuality;
    final lossyBitrateLabel = _extractLossyBitrateLabel(resolvedQuality);

    return Card(
      elevation: 0,
      color: settingsGroupColor(context),
      shape: _sectionCardShape(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackFileInfo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    fileExtension,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (fileSize != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      formatBytes(fileSize),
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_isBitrateFormatLabel(fileExtension) &&
                    lossyBitrateLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lossyBitrateLabel,
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (_audioBitrate != null &&
                    _audioBitrate! > 0 &&
                    _isBitrateFormatLabel(fileExtension))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_audioBitrate}kbps',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (bitDepth != null &&
                    bitDepth! > 0 &&
                    sampleRate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      buildDisplayAudioQuality(
                            bitDepth: bitDepth,
                            sampleRate: sampleRate,
                          ) ??
                          '',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (!_isBitrateFormatLabel(fileExtension) &&
                    _audioBitrate != null &&
                    _audioBitrate! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_audioBitrate}kbps',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getServiceColor(_service, colorScheme),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getServiceIcon(_service),
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _service.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            InkWell(
              onTap: () => _copyToClipboard(context, cleanFilePath),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayFilePath,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
