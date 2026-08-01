import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bottom sheet listing every streaming platform song.link resolves for a
/// track. Data-driven from the generic platform-link map so the app core
/// stays service-agnostic; tapping a row opens the link externally.
class OpenOnPlatformSheet extends StatelessWidget {
  final String spotifyId;
  final String isrc;

  const OpenOnPlatformSheet({super.key, this.spotifyId = '', this.isrc = ''});

  static Future<void> show(
    BuildContext context, {
    String spotifyId = '',
    String isrc = '',
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showAppBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: context.l10n.trackOpenOn,
      maxHeightFactor: 0.7,
      builder: (_) => OpenOnPlatformSheet(spotifyId: spotifyId, isrc: isrc),
    );
  }

  static const Map<String, String> _platformNames = {
    'spotify': 'Spotify',
    'appleMusic': 'Apple Music',
    'itunes': 'iTunes',
    'youtube': 'YouTube',
    'youtubeMusic': 'YouTube Music',
    'deezer': 'Deezer',
    'tidal': 'TIDAL',
    'amazonMusic': 'Amazon Music',
    'amazonStore': 'Amazon Store',
    'qobuz': 'Qobuz',
    'soundcloud': 'SoundCloud',
    'pandora': 'Pandora',
    'napster': 'Napster',
    'yandex': 'Yandex Music',
    'audiomack': 'Audiomack',
    'anghami': 'Anghami',
    'boomplay': 'Boomplay',
  };

  static String _displayName(String platformId) {
    final known = _platformNames[platformId];
    if (known != null) return known;
    // Humanize unknown camelCase IDs ("someNewService" -> "Some New Service").
    final spaced = platformId.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return spaced.isEmpty
        ? platformId
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  Future<void> _openLink(BuildContext context, String url) async {
    HapticFeedback.selectionClick();
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarCannotOpenFile(url))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, String>>(
      future: PlatformBridge.getTrackPlatformLinks(
        spotifyId: spotifyId,
        isrc: isrc,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final links = snapshot.data ?? const <String, String>{};
        if (links.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text(
              context.l10n.trackOpenOnNoLinks,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final entries = links.entries.toList()
          ..sort((a, b) => _displayName(a.key).compareTo(_displayName(b.key)));
        return SingleChildScrollView(
          child: Column(
            children: [
              SettingsGroup(
                children: [
                  for (final entry in entries)
                    ListTile(
                      title: Text(_displayName(entry.key)),
                      trailing: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => _openLink(context, entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
