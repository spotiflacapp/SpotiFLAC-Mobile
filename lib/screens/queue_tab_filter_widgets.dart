part of 'queue_tab.dart';

extension _QueueTabFilterWidgets on _QueueTabState {
  /// Count text left, action buttons right, always on one line; on narrow
  /// widths the buttons scale down instead of truncating the count.
  Widget _countHeaderRow(
    BuildContext context,
    String countText,
    List<Widget> actions,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            countText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String filterMode,
    required String historyViewMode,
    required bool hasQueueItems,
    required _FilterContentData filterData,
    required LibraryCollectionsState collectionState,
    required bool hasMoreLibrary,
    required bool isPageLoading,
    required List<DownloadHistoryItem> inMemoryHistoryItems,
    double bottomInset = 0,
  }) {
    final historyItems = filterData.historyItems;
    final showFilteringIndicator = filterData.showFilteringIndicator;
    final filteredGroupedAlbums = filterData.filteredGroupedAlbums;
    final filteredGroupedLocalAlbums = filterData.filteredGroupedLocalAlbums;
    final unifiedItems = filterData.unifiedItems;
    final allFilteredUnifiedItems = filterData.filteredUnifiedItems;
    final totalTrackCount = filterData.totalTrackCount;
    final totalAlbumCount = filterData.totalAlbumCount;

    final activeDownloadIds = filterMode == 'albums'
        ? const <String>[]
        : ref
              .watch(
                downloadQueueLookupProvider.select((lookup) {
                  final ids = <String>[];
                  for (final id in lookup.itemIds) {
                    final entry = lookup.byItemId[id];
                    if (entry != null &&
                        entry.status != DownloadStatus.completed) {
                      ids.add(id);
                    }
                  }
                  return _QueueItemIdsSnapshot(ids);
                }),
              )
              .ids
              .reversed
              .toList(growable: false);

    final libIdSet = <String>{
      for (final item in allFilteredUnifiedItems) item.id,
    };
    final bridgeHistoryById = <String, DownloadHistoryItem?>{
      for (final entry in _completionBridge.entries)
        entry.key: _historyItemForCompletionBridge(
          entry.value,
          inMemoryHistoryItems,
        ),
    };
    List<String> bridgeIds = const [];
    if (filterMode != 'albums' && _completionBridge.isNotEmpty) {
      final now = DateTime.now();
      final stale = <String>[];
      final pending = <String>[];
      final hasActiveDownloads = activeDownloadIds.isNotEmpty;
      _completionBridge.forEach((id, _) {
        final historyId = bridgeHistoryById[id]?.id ?? id;
        final landed = libIdSet.contains('dl_$historyId');
        final addedAt = _completionBridgeAt[id];
        final expired =
            addedAt == null || now.difference(addedAt).inSeconds >= 6;
        if (activeDownloadIds.contains(id)) {
          // Re-queued (retry): the live row takes over from the bridge.
          stale.add(id);
        } else if (hasActiveDownloads) {
          // Keep just-completed tracks pinned in the lead zone while the
          // rest of the batch is still downloading, so they don't jump
          // below the remaining queue the moment they finish.
          pending.add(id);
        } else if (landed || expired) {
          stale.add(id);
        } else {
          pending.add(id);
        }
      });
      bridgeIds = pending;
      if (stale.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          var changed = false;
          for (final id in stale) {
            if (_completionBridge.remove(id) != null) changed = true;
            _completionBridgeAt.remove(id);
            _bridgePrecacheStarted.remove(id);
          }
          if (changed) _setState(() {});
        });
      }
      final toPrecache = pending
          .where((id) => !_bridgePrecacheStarted.contains(id))
          .toList(growable: false);
      if (toPrecache.isNotEmpty) {
        for (final id in toPrecache) {
          final historyItem = bridgeHistoryById[id];
          if (historyItem == null) continue;
          _bridgePrecacheStarted.add(id);
          final coverUrl = historyItem.coverUrl;
          final embeddedPath = _resolveDownloadedEmbeddedCoverPath(
            historyItem.filePath,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              // Decode at the same 200px extent the grid cell renders with
              // (queue_tab_item_widgets cacheSize) so the precache shares the
              // cell's cache entry; embedded covers can be 3000x3000 and a
              // full-res decode evicts the whole low-RAM image cache.
              const targetSize = 200;
              if (embeddedPath != null) {
                precacheImage(
                  ResizeImage(
                    FileImage(File(embeddedPath)),
                    width: targetSize,
                    height: targetSize,
                  ),
                  context,
                );
              }
              if (coverUrl != null && coverUrl.isNotEmpty) {
                precacheImage(
                  ResizeImage(
                    CachedNetworkImageProvider(
                      coverUrl,
                      cacheManager: CoverCacheManager.instance,
                    ),
                    width: targetSize,
                    height: targetSize,
                  ),
                  context,
                );
              }
            } catch (_) {}
          });
        }
      }
    }

    // Tracks pinned as completion-bridge cells render in the lead zone;
    // hide their history rows so they don't appear twice.
    List<UnifiedLibraryItem> filteredUnifiedItems = allFilteredUnifiedItems;
    if (bridgeIds.isNotEmpty) {
      final pinnedHistoryIds = <String>{
        for (final id in bridgeIds) 'dl_${bridgeHistoryById[id]?.id ?? id}',
      };
      filteredUnifiedItems = allFilteredUnifiedItems
          .where((item) => !pinnedHistoryIds.contains(item.id))
          .toList(growable: false);
    }

    final downloadedNavigationItems = <DownloadHistoryItem>[];
    final downloadedNavigationIndexByUnifiedId = <String, int>{};
    final localNavigationItems = <LocalLibraryItem>[];
    final localNavigationIndexByUnifiedId = <String, int>{};

    for (final item in filteredUnifiedItems) {
      final historyItem = item.historyItem;
      if (historyItem != null) {
        downloadedNavigationIndexByUnifiedId[item.id] =
            downloadedNavigationItems.length;
        downloadedNavigationItems.add(historyItem);
      }

      final localItem = item.localItem;
      if (localItem != null) {
        localNavigationIndexByUnifiedId[item.id] = localNavigationItems.length;
        localNavigationItems.add(localItem);
      }
    }

    // Completion-bridge tracks are hidden from filteredUnifiedItems, so weave
    // them into the front of the swipe-navigation list (matching their pinned
    // lead-zone position) — otherwise a just-downloaded track opens with no
    // swipe navigation at all until its row lands in the library query.
    final bridgeNavigationIndexById = <String, int>{};
    if (bridgeIds.isNotEmpty) {
      final bridgeHistoryItems = <DownloadHistoryItem>[];
      for (final id in bridgeIds) {
        final historyItem = bridgeHistoryById[id];
        if (historyItem == null) continue;
        bridgeNavigationIndexById[id] = bridgeHistoryItems.length;
        bridgeHistoryItems.add(historyItem);
      }
      if (bridgeHistoryItems.isNotEmpty) {
        downloadedNavigationItems.insertAll(0, bridgeHistoryItems);
        downloadedNavigationIndexByUnifiedId.updateAll(
          (_, index) => index + bridgeHistoryItems.length,
        );
      }
    }

    final leadCount = activeDownloadIds.length + bridgeIds.length;
    final collectionEntries = filterMode == 'all'
        ? _getVisibleCollectionEntries(collectionState)
        : const <_CollectionEntry>[];
    final collectionCount = collectionEntries.length;

    // Indexes into collectionState.playlists, name-filtered by the search
    // query, for the 'playlists' view.
    final playlistIndexes = <int>[];
    if (filterMode == 'playlists') {
      final query = _searchQuery.trim().toLowerCase();
      for (var i = 0; i < collectionState.playlists.length; i++) {
        if (query.isEmpty ||
            collectionState.playlists[i].name.toLowerCase().contains(query)) {
          playlistIndexes.add(i);
        }
      }
    }

    Widget leadGridCell(int index) {
      if (index < activeDownloadIds.length) {
        final id = activeDownloadIds[index];
        return _QueueItemSliverRow(
          key: ValueKey('dlgrid_$id'),
          itemId: id,
          colorScheme: colorScheme,
          itemBuilder: _buildDownloadGridItem,
        );
      }
      final bridgeId = bridgeIds[index - activeDownloadIds.length];
      return KeyedSubtree(
        key: ValueKey('dlgrid_bridge_$bridgeId'),
        child: _buildBridgeGridItem(
          context,
          _completionBridge[bridgeId]!,
          colorScheme,
          bridgeHistoryById[bridgeId],
          navigationItems: downloadedNavigationItems,
          navigationIndex: bridgeNavigationIndexById[bridgeId],
        ),
      );
    }

    Widget leadListCell(int index) {
      if (index < activeDownloadIds.length) {
        final id = activeDownloadIds[index];
        return _QueueItemSliverRow(
          key: ValueKey('dllist_$id'),
          itemId: id,
          colorScheme: colorScheme,
          itemBuilder: _buildQueueItem,
        );
      }
      final bridgeId = bridgeIds[index - activeDownloadIds.length];
      return KeyedSubtree(
        key: ValueKey('dllist_bridge_$bridgeId'),
        child: _buildBridgeListItem(
          context,
          _completionBridge[bridgeId]!,
          colorScheme,
          bridgeHistoryById[bridgeId],
          navigationItems: downloadedNavigationItems,
          navigationIndex: bridgeNavigationIndexById[bridgeId],
        ),
      );
    }

    final content = CustomScrollView(
      slivers: [
        if (totalTrackCount > 0 && filterMode == 'all')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueTrackCount(totalTrackCount),
              [
                if (!_isSelectionMode)
                  _buildFilterButton(context, unifiedItems),
                if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

        if ((filteredGroupedAlbums.isNotEmpty ||
                filteredGroupedLocalAlbums.isNotEmpty) &&
            filterMode == 'albums')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueAlbumCount(totalAlbumCount),
              [_buildFilterButton(context, unifiedItems)],
            ),
          ),

        if (filteredGroupedAlbums.isEmpty &&
            filteredGroupedLocalAlbums.isEmpty &&
            filterMode == 'albums' &&
            (historyItems.isNotEmpty || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (filterMode == 'all' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (filterMode == 'singles' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (showFilteringIndicator)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.queueFilteringIndicator,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (filterMode == 'all') _buildQueueHeaderSliver(context, colorScheme),

        if (filterMode == 'albums' &&
            (filteredGroupedAlbums.isNotEmpty ||
                filteredGroupedLocalAlbums.isNotEmpty))
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _AnimatedLibrarySliverGrid(
              maxCrossAxisExtent: _libraryAlbumGridExtent,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index < filteredGroupedAlbums.length) {
                    final album = filteredGroupedAlbums[index];
                    return KeyedSubtree(
                      key: ValueKey(album.key),
                      child: _buildAlbumGridItem(context, album, colorScheme),
                    );
                  } else {
                    final localIndex = index - filteredGroupedAlbums.length;
                    final album = filteredGroupedLocalAlbums[localIndex];
                    return KeyedSubtree(
                      key: ValueKey('local_${album.key}'),
                      child: _buildLocalAlbumGridItem(
                        context,
                        album,
                        colorScheme,
                      ),
                    );
                  }
                },
                childCount:
                    filteredGroupedAlbums.length +
                    filteredGroupedLocalAlbums.length,
              ),
            ),
          ),

        if (filterMode == 'playlists' && playlistIndexes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queuePlaylistCount(playlistIndexes.length),
              [
                if (!_isPlaylistSelectionMode)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _AnimatedLibrarySliverGrid(
              maxCrossAxisExtent: _libraryAlbumGridExtent,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlistIndex = playlistIndexes[index];
                return KeyedSubtree(
                  key: ValueKey(
                    'plgrid_${collectionState.playlists[playlistIndex].id}',
                  ),
                  child: _buildAllTabGridCollectionItem(
                    context: context,
                    colorScheme: colorScheme,
                    entry: _CollectionEntry.playlist(playlistIndex),
                    collectionState: collectionState,
                  ),
                );
              }, childCount: playlistIndexes.length),
            ),
          ),
        ],

        if (filterMode == 'all') ...[
          if (historyViewMode == 'grid')
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _AnimatedLibrarySliverGrid(
                maxCrossAxisExtent: _libraryGridExtent,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.66,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < collectionCount) {
                      return _buildAllTabGridCollectionItem(
                        context: context,
                        colorScheme: colorScheme,
                        entry: collectionEntries[index],
                        collectionState: collectionState,
                        filteredUnifiedItems: filteredUnifiedItems,
                      );
                    }
                    final afterCollections = index - collectionCount;
                    if (afterCollections < leadCount) {
                      return leadGridCell(afterCollections);
                    }
                    final trackIndex = afterCollections - leadCount;
                    if (trackIndex < filteredUnifiedItems.length) {
                      final item = filteredUnifiedItems[trackIndex];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: LongPressDraggable<UnifiedLibraryItem>(
                          data: item,
                          feedback: _buildDragFeedback(
                            context,
                            item,
                            colorScheme,
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: _buildUnifiedGridItem(
                              context,
                              item,
                              colorScheme,
                              downloadedNavigationItems:
                                  downloadedNavigationItems,
                              downloadedNavigationIndex:
                                  downloadedNavigationIndexByUnifiedId[item.id],
                              localNavigationItems: localNavigationItems,
                              localNavigationIndex:
                                  localNavigationIndexByUnifiedId[item.id],
                              libraryItems: filteredUnifiedItems,
                            ),
                          ),
                          child: _buildUnifiedGridItem(
                            context,
                            item,
                            colorScheme,
                            downloadedNavigationItems:
                                downloadedNavigationItems,
                            downloadedNavigationIndex:
                                downloadedNavigationIndexByUnifiedId[item.id],
                            localNavigationItems: localNavigationItems,
                            localNavigationIndex:
                                localNavigationIndexByUnifiedId[item.id],
                            libraryItems: filteredUnifiedItems,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  childCount:
                      leadCount + collectionCount + filteredUnifiedItems.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < collectionCount) {
                      return _buildAllTabListCollectionItem(
                        context: context,
                        colorScheme: colorScheme,
                        entry: collectionEntries[index],
                        collectionState: collectionState,
                        filteredUnifiedItems: filteredUnifiedItems,
                      );
                    }
                    final afterCollections = index - collectionCount;
                    if (afterCollections < leadCount) {
                      return leadListCell(afterCollections);
                    }
                    final trackIndex = afterCollections - leadCount;
                    if (trackIndex < filteredUnifiedItems.length) {
                      final item = filteredUnifiedItems[trackIndex];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: LongPressDraggable<UnifiedLibraryItem>(
                          data: item,
                          feedback: _buildDragFeedback(
                            context,
                            item,
                            colorScheme,
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: _buildUnifiedLibraryItem(
                              context,
                              item,
                              colorScheme,
                              downloadedNavigationItems:
                                  downloadedNavigationItems,
                              downloadedNavigationIndex:
                                  downloadedNavigationIndexByUnifiedId[item.id],
                              localNavigationItems: localNavigationItems,
                              localNavigationIndex:
                                  localNavigationIndexByUnifiedId[item.id],
                              libraryItems: filteredUnifiedItems,
                            ),
                          ),
                          child: _buildUnifiedLibraryItem(
                            context,
                            item,
                            colorScheme,
                            downloadedNavigationItems:
                                downloadedNavigationItems,
                            downloadedNavigationIndex:
                                downloadedNavigationIndexByUnifiedId[item.id],
                            localNavigationItems: localNavigationItems,
                            localNavigationIndex:
                                localNavigationIndexByUnifiedId[item.id],
                            libraryItems: filteredUnifiedItems,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  childCount:
                      leadCount + collectionCount + filteredUnifiedItems.length,
                ),
              ),
            ),
        ],

        if (filterMode == 'singles')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueTrackCount(totalTrackCount),
              [
                if (!_isSelectionMode)
                  _buildFilterButton(context, unifiedItems),
                if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

        if (filterMode == 'singles')
          _buildQueueHeaderSliver(context, colorScheme),

        if ((filteredUnifiedItems.isNotEmpty || leadCount > 0) &&
            filterMode == 'singles')
          historyViewMode == 'grid'
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _AnimatedLibrarySliverGrid(
                    maxCrossAxisExtent: _libraryGridExtent,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.66,
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index < leadCount) {
                        return leadGridCell(index);
                      }
                      final item = filteredUnifiedItems[index - leadCount];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: _buildUnifiedGridItem(
                          context,
                          item,
                          colorScheme,
                          downloadedNavigationItems: downloadedNavigationItems,
                          downloadedNavigationIndex:
                              downloadedNavigationIndexByUnifiedId[item.id],
                          localNavigationItems: localNavigationItems,
                          localNavigationIndex:
                              localNavigationIndexByUnifiedId[item.id],
                          libraryItems: filteredUnifiedItems,
                        ),
                      );
                    }, childCount: leadCount + filteredUnifiedItems.length),
                  ),
                )
              : SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wideListInset(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index < leadCount) {
                        return leadListCell(index);
                      }
                      final item = filteredUnifiedItems[index - leadCount];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: _buildUnifiedLibraryItem(
                          context,
                          item,
                          colorScheme,
                          downloadedNavigationItems: downloadedNavigationItems,
                          downloadedNavigationIndex:
                              downloadedNavigationIndexByUnifiedId[item.id],
                          localNavigationItems: localNavigationItems,
                          localNavigationIndex:
                              localNavigationIndexByUnifiedId[item.id],
                          libraryItems: filteredUnifiedItems,
                        ),
                      );
                    }, childCount: leadCount + filteredUnifiedItems.length),
                  ),
                ),

        if (!hasQueueItems &&
            totalTrackCount == 0 &&
            (filterMode != 'albums' ||
                (filteredGroupedAlbums.isEmpty &&
                    filteredGroupedLocalAlbums.isEmpty)) &&
            (filterMode != 'playlists' || playlistIndexes.isEmpty) &&
            !showFilteringIndicator &&
            !isPageLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, colorScheme, filterMode),
          )
        else if (isPageLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),

        if (hasQueueItems ||
            totalTrackCount > 0 ||
            (filterMode == 'albums' &&
                (filteredGroupedAlbums.isNotEmpty ||
                    filteredGroupedLocalAlbums.isNotEmpty)) ||
            (filterMode == 'playlists' && playlistIndexes.isNotEmpty))
          SliverToBoxAdapter(
            child: SizedBox(height: _isSelectionMode ? 100 : 16),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
      ],
    );

    final scrollAwareContent = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _handleLibraryScrollNotification(
        notification: notification,
        filterMode: filterMode,
        hasMoreLibrary: hasMoreLibrary,
        isPageLoading: isPageLoading,
      ),
      child: content,
    );

    if (historyViewMode != 'grid') return scrollAwareContent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: _handleLibraryGridScaleStart,
      onScaleUpdate: _handleLibraryGridScaleUpdate,
      onScaleEnd: _handleLibraryGridScaleEnd,
      child: scrollAwareContent,
    );
  }

  Future<void> _showClearAllDialog(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.queueClearAll),
        content: Text(context.l10n.queueClearAllMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(context.l10n.dialogClear),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ref.read(downloadQueueProvider.notifier).clearAll();
    }
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    String filterMode,
  ) {
    String message;
    String subtitle;
    IconData icon;

    switch (filterMode) {
      case 'albums':
        message = context.l10n.queueEmptyAlbums;
        subtitle = context.l10n.queueEmptyAlbumsSubtitle;
        icon = Icons.album;
        break;
      case 'singles':
        message = context.l10n.queueEmptySingles;
        subtitle = context.l10n.queueEmptySinglesSubtitle;
        icon = Icons.music_note;
        break;
      case 'playlists':
        message = context.l10n.collectionNoPlaylistsYet;
        subtitle = context.l10n.queueEmptyPlaylistsSubtitle;
        icon = Icons.queue_music;
        break;
      default:
        message = context.l10n.queueEmptyHistory;
        subtitle = context.l10n.queueEmptyHistorySubtitle;
        icon = Icons.history;
    }

    return EmptyState(
      icon: icon,
      title: message,
      message: subtitle,
      // Every empty branch here means "you have not downloaded anything of
      // this kind yet", so the way forward is always search.
      action: FilledButton.icon(
        onPressed: () => ShellNavigationService.requestTab(ShellTab.home),
        icon: const Icon(Icons.search),
        label: Text(context.l10n.navHome),
      ),
    );
  }

  Widget _buildAlbumGridItem(
    BuildContext context,
    _GroupedAlbum album,
    ColorScheme colorScheme,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: _embeddedCoverVersion,
      builder: (context, _, child) {
        final embeddedCoverPath = _resolveDownloadedEmbeddedCoverPath(
          album.sampleFilePath,
        );
        return _buildAlbumGridItemCore(
          context: context,
          albumName: album.albumName,
          artistName: album.artistName,
          trackCount: album.displayTrackCount,
          colorScheme: colorScheme,
          coverWidget: embeddedCoverPath != null
              ? Image.file(
                  File(embeddedCoverPath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 300,
                  cacheHeight: 300,
                  errorBuilder: (context, error, stackTrace) =>
                      _albumPlaceholder(colorScheme),
                )
              : album.coverUrl != null
              ? CachedCoverImage(
                  imageUrl: album.coverUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: 300,
                  memCacheHeight: 300,
                )
              : null,
          badgeColor: colorScheme.primaryContainer,
          badgeTextColor: colorScheme.onPrimaryContainer,
          badgeIcon: Icons.music_note,
          coverUrl: album.coverUrl,
          onTap: () => _navigateToDownloadedAlbum(album),
        );
      },
    );
  }

  Widget _buildLocalAlbumGridItem(
    BuildContext context,
    _GroupedLocalAlbum album,
    ColorScheme colorScheme,
  ) {
    return _buildAlbumGridItemCore(
      context: context,
      albumName: album.albumName,
      artistName: album.artistName,
      trackCount: album.displayTrackCount,
      colorScheme: colorScheme,
      coverWidget: album.coverPath != null
          ? Image.file(
              File(album.coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 300,
              cacheHeight: 300,
              errorBuilder: (context, error, stackTrace) =>
                  _albumPlaceholder(colorScheme),
            )
          : null,
      badgeColor: colorScheme.tertiaryContainer,
      badgeTextColor: colorScheme.onTertiaryContainer,
      badgeIcon: Icons.folder,
      onTap: () => _navigateToLocalAlbum(album),
    );
  }

  Widget _albumPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 48),
      ),
    );
  }

  Widget _buildAlbumGridItemCore({
    required BuildContext context,
    required String albumName,
    required String artistName,
    required int trackCount,
    required ColorScheme colorScheme,
    required Widget? coverWidget,
    required Color badgeColor,
    required Color badgeTextColor,
    required IconData badgeIcon,
    required VoidCallback onTap,
    String? coverUrl,
  }) {
    return Semantics(
      button: true,
      label: context.l10n.a11yOpenAlbumByArtistTrackCount(
        albumName,
        artistName,
        trackCount,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverWidget ?? _albumPlaceholder(colorScheme),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeTextColor),
                          const SizedBox(width: 4),
                          Text(
                            '$trackCount',
                            style: TextStyle(
                              color: badgeTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ClickableArtistName(
              artistName: artistName,
              coverUrl: coverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<UnifiedLibraryItem> _selectedItemsFromAll(
    List<UnifiedLibraryItem> allItems,
  ) {
    final itemsById = {for (final item in allItems) item.id: item};
    return _selectedIds
        .map((id) => itemsById[id])
        .whereType<UnifiedLibraryItem>()
        .toList(growable: false);
  }

  bool _isLocalOnlySelection(List<UnifiedLibraryItem> allItems) {
    final selectedItems = _selectedItemsFromAll(allItems);
    return selectedItems.isNotEmpty &&
        selectedItems.every((item) => item.localItem != null);
  }
}
