import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spotiflac_android/services/app_remote_config_service.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/widgets/donate_icons.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

class DonatePage extends StatefulWidget {
  final AppRemoteConfigService? remoteConfigService;

  const DonatePage({super.key, this.remoteConfigService});

  @override
  State<DonatePage> createState() => _DonatePageState();
}

class _DonatePageState extends State<DonatePage> {
  DonateConfig _config = DonateConfig.fallback();
  bool _hasRequestedConfig = false;
  String? _activeRemoteJson;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasRequestedConfig) return;

    _hasRequestedConfig = true;
    unawaited(_loadConfig(Localizations.localeOf(context).toLanguageTag()));
  }

  Future<void> _loadConfig(String locale) async {
    final service = widget.remoteConfigService ?? AppRemoteConfigService();
    final cached = await service.readCachedConfig();
    if (!mounted) return;

    if (cached != null) {
      _applyRemoteConfig(cached);
    }

    final refreshed = await service.fetchConfigSnapshot(locale: locale);
    if (!mounted || refreshed == null) return;
    _applyRemoteConfig(refreshed);
  }

  void _applyRemoteConfig(RemoteConfigSnapshot snapshot) {
    if (_activeRemoteJson == snapshot.rawJson) return;

    setState(() {
      _activeRemoteJson = snapshot.rawJson;
      _config = snapshot.config.donate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: 'Donate'),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16 + wideListInset(context),
                16,
                16 + wideListInset(context),
                16,
              ),
              child: Column(
                children: [
                  _DonateLinksCard(colorScheme: colorScheme, config: _config),
                  const SizedBox(height: 24),
                  _RecentDonorsCard(
                    colorScheme: colorScheme,
                    supporters: _config.supporters,
                  ),
                  const SizedBox(height: 16),
                  _DonateNoticeCard(
                    colorScheme: colorScheme,
                    notices: _config.notices,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonateLinksCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final DonateConfig config;

  const _DonateLinksCard({required this.colorScheme, required this.config});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.04),
            colorScheme.surface,
          );

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          if (!config.enabled)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Donation links are currently unavailable.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var index = 0; index < config.methods.length; index++) ...[
              _DonateMethodItem(
                method: config.methods[index],
                colorScheme: colorScheme,
              ),
              if (index < config.methods.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 74,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
            ],
        ],
      ),
    );
  }
}

class _RecentDonorsCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final List<String> supporters;

  const _RecentDonorsCard({
    required this.colorScheme,
    required this.supporters,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.04),
            colorScheme.surface,
          );

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Recent Supporters',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Thank you for your generosity!',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (supporters.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        size: 32,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No supporters yet - be the first!',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supporters
                    .map(
                      (name) =>
                          _SupporterChip(name: name, colorScheme: colorScheme),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _DonateNoticeCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final List<String> notices;

  const _DonateNoticeCard({required this.colorScheme, required this.notices});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.volunteer_activism_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Good to Know',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < notices.length; index++) ...[
              _NoticeLine(
                icon: _noticeIcon(index),
                text: notices[index],
                colorScheme: colorScheme,
              ),
              if (index < notices.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _DonateMethodItem extends StatelessWidget {
  final DonateMethod method;
  final ColorScheme colorScheme;

  const _DonateMethodItem({required this.method, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final color = Color(method.color);

    return InkWell(
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: _methodIcon(method)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.subtitle.isEmpty
                        ? method.walletAddress ?? method.url ?? ''
                        : method.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: method.isWallet ? 11 : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              method.isWallet ? Icons.copy_rounded : Icons.open_in_new,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    if (method.isWallet) {
      await Clipboard.setData(ClipboardData(text: method.walletAddress!));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${method.title} address copied to clipboard'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final url = method.url;
    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _SupporterChip extends StatelessWidget {
  final String name;
  final ColorScheme colorScheme;

  const _SupporterChip({required this.name, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme colorScheme;

  const _NoticeLine({
    required this.icon,
    required this.text,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

Widget _methodIcon(DonateMethod method) {
  switch (method.icon.toLowerCase()) {
    case 'kofi':
    case 'ko-fi':
      return const KofiIcon(size: 22, color: Colors.white);
    case 'github':
    case 'github-sponsors':
      return const GitHubIcon(size: 22, color: Colors.white);
    case 'crypto':
    case 'wallet':
      return const Text(
        '\$',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      );
    case 'coffee':
      return const Icon(
        Icons.local_cafe_rounded,
        color: Colors.white,
        size: 22,
      );
    case 'heart':
    default:
      return const Icon(Icons.favorite_rounded, color: Colors.white, size: 22);
  }
}

IconData _noticeIcon(int index) {
  const icons = [
    Icons.block,
    Icons.build_outlined,
    Icons.favorite_border,
    Icons.history,
    Icons.update,
  ];
  return icons[index % icons.length];
}
