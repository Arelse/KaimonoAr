import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/entry.dart';
import '../services/extension_manager.dart';
import 'webview_screen.dart';

enum _ReadMode { paged, webtoon }

const _panelBg = Color(0xE6141010); // near-opaque so it reads over white pages
const _purple = Color(0xFF7C5CFF);

String _fmtNum(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

class MangaReaderScreen extends ConsumerStatefulWidget {
  final String sourceId;
  final EntryChunk chunk;
  final List<EntryChunk> allChunks;

  const MangaReaderScreen({super.key, required this.sourceId, required this.chunk, required this.allChunks});

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen> {
  late EntryChunk _chunk;
  List<String> _pages = [];
  bool _loading = true;
  _ReadMode _mode = _ReadMode.paged;
  bool _controlsVisible = true;
  int _currentPage = 0;
  double _zoom = 1.0;
  bool _advancing = false;

  final PageController _pageController = PageController();
  final ScrollController _webtoonController = ScrollController();
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _chunk = widget.chunk;
    _webtoonController.addListener(_onWebtoonScroll);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _currentPage = 0;
      _advancing = false;
    });
    final source = ref.read(extensionManagerProvider)[widget.sourceId]!;
    final pages = await source.getPages(_chunk.id);
    setState(() {
      _pages = pages;
      _loading = false;
    });
  }

  bool get _hasNext {
    final i = widget.allChunks.indexWhere((c) => c.id == _chunk.id);
    return i >= 0 && i + 1 < widget.allChunks.length;
  }

  bool get _hasPrev {
    final i = widget.allChunks.indexWhere((c) => c.id == _chunk.id);
    return i > 0;
  }

  void _goToChunk(int offset) {
    final i = widget.allChunks.indexWhere((c) => c.id == _chunk.id);
    final target = i + offset;
    if (target < 0 || target >= widget.allChunks.length) return;
    setState(() => _chunk = widget.allChunks[target]);
    _load();
  }

  void _autoAdvance() {
    if (_advancing || !_hasNext) return;
    _advancing = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Loading next chapter…'), duration: Duration(milliseconds: 800)),
    );
    _goToChunk(1);
  }

  void _onWebtoonScroll() {
    if (_mode != _ReadMode.webtoon || !_webtoonController.hasClients) return;
    final pos = _webtoonController.position;
    if (pos.pixels >= pos.maxScrollExtent - 4 && pos.maxScrollExtent > 0) {
      _autoAdvance();
    }
  }

  Future<void> _openWebView() async {
    final source = ref.read(extensionManagerProvider)[widget.sourceId]!;
    final entry = await source.getEntryDetails(_chunk.entryId);
    if (!mounted) return;
    final url = entry.sourceUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This source has no webpage link for this entry.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SourceWebViewScreen(url: url, title: entry.title)),
    );
  }

  void _openChapterPicker() {
    String query = '';
    bool grid = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: _panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          final sorted = List<EntryChunk>.from(widget.allChunks)..sort((a, b) => a.number.compareTo(b.number));
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? sorted
              : sorted.where((c) => c.title.toLowerCase().contains(q) || _fmtNum(c.number).contains(q)).toList();

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: _purple, size: 22),
                      const SizedBox(width: 8),
                      const Text('Chapters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(12)),
                        child: Text('${sorted.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.download_outlined, color: Colors.white70),
                        tooltip: 'Download all',
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bulk downloads are coming soon.')),
                        ),
                      ),
                      // Distinct icon per state: a grid glyph vs a list glyph, not two near-identical grids.
                      IconButton(
                        icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white70),
                        tooltip: grid ? 'Switch to list' : 'Switch to grid',
                        onPressed: () => setSheetState(() => grid = !grid),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) => setSheetState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search chapters...',
                        hintStyle: TextStyle(color: Colors.white38),
                        prefixIcon: Icon(Icons.search, color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: grid
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.3,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final selected = c.id == _chunk.id;
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.pop(context);
                                if (!selected) {
                                  setState(() => _chunk = c);
                                  _load();
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: selected ? _purple.withOpacity(0.3) : Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: selected ? Border.all(color: _purple) : null,
                                ),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Ch. ${_fmtNum(c.number)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final selected = c.id == _chunk.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.pop(context);
                                  if (!selected) {
                                    setState(() => _chunk = c);
                                    _load();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: selected ? _purple.withOpacity(0.22) : Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(16),
                                    border: selected ? Border.all(color: _purple) : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: selected ? _purple : _purple.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('Ch. ${_fmtNum(c.number)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(c.title,
                                            style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.w600)),
                                      ),
                                      if (selected)
                                        const Icon(Icons.check_circle, color: Colors.white, size: 20)
                                      else if (c.read)
                                        const Icon(Icons.check_circle_outline, color: Colors.white38, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Reading mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SegmentedButton<_ReadMode>(
                segments: const [
                  ButtonSegment(value: _ReadMode.paged, label: Text('Paged'), icon: Icon(Icons.view_carousel_outlined)),
                  ButtonSegment(value: _ReadMode.webtoon, label: Text('Webtoon'), icon: Icon(Icons.view_agenda_outlined)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() => _mode = s.first);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoomBy(double delta) {
    if (_mode == _ReadMode.webtoon) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zoom is only available in paged mode for now.')),
      );
      return;
    }
    setState(() {
      _zoom = (_zoom + delta).clamp(1.0, 3.0);
      _transformCtrl.value = Matrix4.identity()..scale(_zoom);
    });
  }

  void _jumpToFraction(double fraction) {
    if (_pages.isEmpty) return;
    if (_mode == _ReadMode.paged) {
      final target = (fraction * (_pages.length - 1)).round().clamp(0, _pages.length - 1);
      _pageController.jumpToPage(target);
    } else if (_webtoonController.hasClients) {
      final max = _webtoonController.position.maxScrollExtent;
      _webtoonController.jumpTo((fraction * max).clamp(0, max));
    }
  }

  void _stepPage(int delta) {
    if (_pages.isEmpty) return;
    if (_mode == _ReadMode.paged) {
      final target = _currentPage + delta;
      if (target < 0) {
        if (_hasPrev) _goToChunk(-1);
      } else if (target >= _pages.length) {
        _autoAdvance();
      } else {
        _pageController.animateToPage(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } else if (_webtoonController.hasClients) {
      final step = MediaQuery.of(context).size.height * 0.4 * delta;
      _webtoonController.animateTo(
        (_webtoonController.offset + step).clamp(0, _webtoonController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_pages.isEmpty)
            const Center(child: Text('No pages found', style: TextStyle(color: Colors.white)))
          else
            _mode == _ReadMode.paged ? _pagedView() : _webtoonView(),
          _topBar(),
          if (_mode == _ReadMode.paged && _pages.isNotEmpty) _pageCounterPill(),
          if (!_loading && _pages.isNotEmpty) _rightSideControls(),
          if (!_loading) _bottomWebViewButton(),
        ],
      ),
    );
  }

  Widget _topBar() {
    final i = widget.allChunks.indexWhere((c) => c.id == _chunk.id);
    final subtitle = i >= 0 ? 'Ch. ${i + 1} · ${widget.allChunks.length} total' : '';
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _circleButton(Icons.arrow_back, () => Navigator.pop(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _openChapterPicker,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.circle_outlined, color: Colors.white70, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_chunk.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                if (subtitle.isNotEmpty)
                                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.expand_more, color: Colors.white60, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Distinct settings glyph — not the sliders icon, which reads as a hamburger at a glance.
                _circleButton(Icons.settings_outlined, _openSettings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _pageCounterPill() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 68),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(14)),
              child: Text('${_currentPage + 1} / ${_pages.length}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }

  /// Scrubber (top) and zoom controls (below it) — stacked as one column on
  /// the right edge, per the requested repositioning.
  Widget _rightSideControls() {
    final total = _pages.length;
    final current = _mode == _ReadMode.paged
        ? _currentPage
        : (_webtoonController.hasClients && _webtoonController.position.maxScrollExtent > 0
            ? ((_webtoonController.offset / _webtoonController.position.maxScrollExtent) * (total - 1)).round()
            : 0);

    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Wider, easier-to-grab scrubber track.
                  Container(
                    width: 48,
                    height: MediaQuery.of(context).size.height * 0.42,
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.bookmark_border, color: Colors.white70, size: 16),
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bookmarks are coming soon.')),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 18),
                          onPressed: () => _stepPage(-1),
                        ),
                        Text('${current + 1}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final fraction = total > 1 ? current / (total - 1) : 0.0;
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (details) {
                                  final f = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                                  _jumpToFraction(f);
                                },
                                onTapUp: (details) {
                                  final f = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                                  _jumpToFraction(f);
                                },
                                child: Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    Positioned(
                                      top: 2,
                                      bottom: 2,
                                      child: Container(
                                        width: 8,
                                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: List.generate(
                                        10,
                                        (i) => Container(
                                          width: 5,
                                          height: 5,
                                          decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: (constraints.maxHeight - 30) * fraction,
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 6)],
                                        ),
                                        child: const Icon(Icons.lock, color: Colors.white, size: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$total', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                          onPressed: () => _stepPage(1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Zoom cluster, now below the scrubber instead of overlapping it.
                  Container(
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.add, color: Colors.white, size: 20), onPressed: () => _zoomBy(0.25)),
                        IconButton(
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          tooltip: 'Skip to next chapter',
                          onPressed: () => _autoAdvance(),
                        ),
                        IconButton(icon: const Icon(Icons.remove, color: Colors.white, size: 20), onPressed: () => _zoomBy(-0.25)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomWebViewButton() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _openWebView,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.explore_outlined, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('WebView', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pagedView() {
    return NotificationListener<OverscrollNotification>(
      onNotification: (notification) {
        if (notification.overscroll > 0 && _currentPage == _pages.length - 1) {
          _autoAdvance();
        }
        return false;
      },
      child: GestureDetector(
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          final dx = details.globalPosition.dx;
          if (dx < width / 3) {
            if (_currentPage == 0) {
              if (_hasPrev) _goToChunk(-1);
            } else if (_pageController.hasClients) {
              _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          } else if (dx > width * 2 / 3) {
            if (_currentPage == _pages.length - 1) {
              _autoAdvance();
            } else if (_pageController.hasClients) {
              _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          } else {
            setState(() => _controlsVisible = !_controlsVisible);
          }
        },
        child: PageView.builder(
          controller: _pageController,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (context, i) => InteractiveViewer(
            transformationController: i == _currentPage ? _transformCtrl : null,
            maxScale: 4,
            child: CachedNetworkImage(
              imageUrl: _pages[i],
              fit: BoxFit.contain,
              width: double.infinity,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _webtoonView() {
    return GestureDetector(
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: ListView.builder(
        controller: _webtoonController,
        itemCount: _pages.length,
        itemBuilder: (context, i) => CachedNetworkImage(
          imageUrl: _pages[i],
          fit: BoxFit.fitWidth,
          width: double.infinity,
          placeholder: (_, __) => const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
          errorWidget: (_, __, ___) => const SizedBox(height: 100, child: Icon(Icons.broken_image, color: Colors.white38)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _webtoonController.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }
}
