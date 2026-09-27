import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/entry.dart';
import '../services/extension_manager.dart';

enum _ReadMode { paged, webtoon }

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

  void _openChapterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161010),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final sorted = List<EntryChunk>.from(widget.allChunks)..sort((a, b) => a.number.compareTo(b.number));
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final c = sorted[i];
                final selected = c.id == _chunk.id;
                return ListTile(
                  leading: Icon(
                    selected ? Icons.play_circle_fill : (c.read ? Icons.check_circle : Icons.circle_outlined),
                    color: selected ? Colors.redAccent : Colors.white54,
                  ),
                  title: Text(c.title, style: TextStyle(color: selected ? Colors.white : Colors.white70)),
                  onTap: () {
                    Navigator.pop(context);
                    if (!selected) {
                      setState(() => _chunk = c);
                      _load();
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161010),
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
          if (!_loading && _pages.isNotEmpty) _rightZoomCapsule(),
          if (!_loading && _pages.isNotEmpty) _rightScrubber(),
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
                        color: Colors.white.withOpacity(0.08),
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
                                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.expand_more, color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _circleButton(Icons.tune, _openSettings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.08),
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
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
              child: Text('${_currentPage + 1} / ${_pages.length}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightZoomCapsule() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 64, bottom: 120),
            child: Container(
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.add, color: Colors.white, size: 20), onPressed: () => _zoomBy(0.25)),
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    onPressed: () => _autoAdvance(),
                    tooltip: 'Skip to next chapter',
                  ),
                  IconButton(icon: const Icon(Icons.remove, color: Colors.white, size: 20), onPressed: () => _zoomBy(-0.25)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightScrubber() {
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
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              width: 40,
              height: MediaQuery.of(context).size.height * 0.55,
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
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
                                child: Container(width: 3, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: List.generate(
                                  10,
                                  (i) => Container(
                                    width: 3,
                                    height: 3,
                                    decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: (constraints.maxHeight - 22) * fraction,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 6)],
                                  ),
                                  child: const Icon(Icons.lock, color: Colors.white, size: 12),
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
