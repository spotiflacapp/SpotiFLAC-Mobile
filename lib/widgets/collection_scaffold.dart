import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';

/// Shared shell for every track-collection screen: album, playlist, local
/// album, downloaded album and library folders.
///
/// Before this existed each of those screens built its own `Scaffold` +
/// `PopScope` + selection plumbing, which is why the same four screens had three
/// different selection-bar mechanisms and why the playlist screen ended up with
/// none at all. Screens now supply their header, their content slivers and the
/// bar contents; everything else is shared:
///
/// * back gesture exits selection mode instead of popping the route,
/// * the selection bar is mounted in the root overlay so it floats above the
///   shell navigation bar,
/// * trailing space is reserved so the last row stays reachable while the bar
///   is up.
class CollectionScaffold extends StatefulWidget {
  const CollectionScaffold({
    super.key,
    required this.scrollController,
    required this.isSelectionMode,
    required this.onExitSelectionMode,
    required this.appBar,
    required this.slivers,
    required this.bottomInset,
    this.selectionBar,
    this.backgroundColor,
  });

  final ScrollController scrollController;
  final bool isSelectionMode;
  final VoidCallback onExitSelectionMode;

  /// The collapsing header sliver.
  final Widget appBar;

  /// Content slivers below the header (track list, error card, footer, ...).
  final List<Widget> slivers;

  /// Bottom inset needed to clear the shell navigation bar.
  final double bottomInset;

  /// Rebuilt by the caller each frame; shown only while [isSelectionMode] is
  /// true. Null means the screen has no multi-select.
  final Widget? selectionBar;

  final Color? backgroundColor;

  @override
  State<CollectionScaffold> createState() => _CollectionScaffoldState();
}

class _CollectionScaffoldState extends State<CollectionScaffold> {
  final SelectionOverlayController _selectionOverlay =
      SelectionOverlayController();
  final GlobalKey _selectionBarKey = GlobalKey();

  // Used for the first frame only. Once the overlay has laid out, the spacer
  // tracks its real height so multi-row actions and large text cannot cover the
  // final collection rows.
  double _selectionBarHeight = 160;

  @override
  void dispose() {
    _selectionOverlay.dispose();
    super.dispose();
  }

  void _syncSelectionOverlay() {
    if (!mounted) return;
    final bar = widget.selectionBar;
    if (!widget.isSelectionMode || bar == null) {
      _selectionOverlay.hide();
      return;
    }
    _selectionOverlay.show(
      context,
      (_) => KeyedSubtree(key: _selectionBarKey, child: bar),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isSelectionMode) return;
      final height = _selectionBarKey.currentContext?.size?.height;
      if (height == null || height <= 0) return;
      if ((height - _selectionBarHeight).abs() < 0.5) return;
      setState(() => _selectionBarHeight = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSelectionMode || _selectionOverlay.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncSelectionOverlay(),
      );
    }

    return PopScope(
      canPop: !widget.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isSelectionMode) {
          widget.onExitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        body: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            widget.appBar,
            ...widget.slivers,
            SliverToBoxAdapter(
              child: SizedBox(
                key: const ValueKey('collection-selection-spacer'),
                height: widget.isSelectionMode ? _selectionBarHeight : 32,
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
          ],
        ),
      ),
    );
  }
}
