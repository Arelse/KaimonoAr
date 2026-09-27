import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/content_type.dart';
import '../models/entry.dart';
import '../services/category_manager.dart';
import '../services/extension_manager.dart';
import '../services/library_manager.dart';
import 'manga_reader_screen.dart';
import 'novel_reader_screen.dart';
import 'player_screen.dart';
import 'webview_screen.dart';

const _bgDetail = Color(0xFF0E0909);
const _bgList = Color(0xFF120406);
const _statsBg = Color(0xFF1A1D24);
const _statLabel = Color(0xFF828797);
const _gold = Color(0xFFFBBF24);
const _libraryBg = Color(0xFF232135);
const _libraryFg = Color(0xFF8B7FF9);
const _defaultBtnBg = Color(0xFF201C1E);
const _defaultBtnFg = Color(0xFFA19D9E);
const _trackerBg = Color(0xFF2C1C21);
const _trackerFg = Color(0xFFFF7B7B);
const _tagBg = Color(0xFF291717);
const _tagFg = Color(0xFFD88787);
const _gray400 = Color(0xFF9CA3AF);
const _gray500 = Color(0xFF6B7280);
const _accent = Color(0xFFFF7B7B);
const _readDim = Color(0xFF7A6468);

String _fmtNum(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _stripHtml(String s) {
  var t = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#8217;', "'");
  return t.trim();
}

class EntryDetailScreen extends ConsumerStatefulWidget {
  final String sourceId;
  final Entry entry;
  const EntryDetailScreen({super.key, required this.sourceId, required this.entry});

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  Entry? _details;
  List<EntryChunk> _chunks = [];
  bool _loading = true;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final source = ref.read(extensionManagerProvider)[widget.sourceId]!;
    final details = await source.getEntryDetails(widget.entry.id);
    final chunks = await source.getChunks(widget.entry.id);
    setState(() {
      _details = details;
      _chunks = chunks;
      _loading = false;
    });
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming soon.')),
    );
  }

  void _openChunk(EntryChunk chunk) {
    final type = widget.entry.type;
    if (type == ContentType.manga) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MangaReaderScreen(sourceId: widget.sourceId, chunk: chunk, allChunks: _chunks),
        ),
      );
    } else if (type == ContentType.novel) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NovelReaderScreen(sourceId: widget.sourceId, chunk: chunk, allChunks: _chunks),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(sourceId: widget.sourceId, chunk: chunk, allChunks: _chunks),
        ),
      );
    }
  }

  void _openWebView(Entry e) {
    final url = e.sourceUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This source has no webpage link for this entry.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SourceWebViewScreen(url: url, title: e.title)),
    );
  }

  void _openChapterList(Entry e) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChapterListScreen(
          title: e.title,
          isAnime: e.type == ContentType.anime,
          chunks: _chunks,
          onOpen: _openChunk,
          onRefresh: _load,
        ),
      ),
    );
  }

  void _openCategoryPicker() {
    final catState = ref.read(categoryManagerProvider);
    final catManager = ref.read(categoryManagerProvider.notifier);
    if (catState.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No categories yet — create one from Settings → Categories.')),
      );
      return;
    }
    final current = catManager.getAssignments(widget.sourceId, widget.entry.id).toSet();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set categories'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: catState.categories
                  .map((c) => CheckboxListTile(
                        title: Text(c.name),
                        value: current.contains(c.id),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            current.add(c.id);
                          } else {
                            current.remove(c.id);
                          }
                        }),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                catManager.setAssignments(widget.sourceId, widget.entry.id, current.toList());
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLine(Entry e) {
    final parts = <String>[];
    if (e.status != EntryStatus.unknown) {
      final n = e.status.name;
      parts.add(n[0].toUpperCase() + n.substring(1));
    }
    parts.add(widget.sourceId);
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bgDetail,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    final e = _details!;
    final desc = e.description == null ? '' : _stripHtml(e.description!);
    final hasStats = e.rank != null || e.rating != null || e.saves != null;

    return Scaffold(
      backgroundColor: _bgDetail,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Top nav
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined, color: Color(0xFFD4D4D8)),
                  onPressed: () => _comingSoon('Downloads'),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_alt_outlined, color: Color(0xFFD4D4D8)),
                  onPressed: () => _openChapterList(e),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Color(0xFFD4D4D8)),
                  onSelected: (value) {
                    if (value == 'refresh') _load();
                    if (value == 'categories') _openCategoryPicker();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                    PopupMenuItem(value: 'categories', child: Text('Set categories')),
                  ],
                ),
              ],
            ),
          ),
          // Header: cover + details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 115,
                  height: 160,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: e.coverUrl != null
                      ? CachedNetworkImage(imageUrl: e.coverUrl!, fit: BoxFit.cover)
                      : Container(color: const Color(0xFF1F2937)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (e.author != null && e.author!.isNotEmpty)
                          _metaRow(Icons.person_outline, e.author!),
                        if (e.artist != null && e.artist!.isNotEmpty)
                          _metaRow(Icons.edit_outlined, e.artist!),
                        _metaRow(Icons.schedule, _statusLine(e)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Stats box
          if (hasStats)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: _statsBg, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _stat('RANK', Text(_rankText(e), style: _statValueStyle)),
                  _statDivider(),
                  _stat(
                    'RATING',
                    e.rating == null
                        ? const Text('—', style: _statValueStyle)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: _gold, size: 14),
                              const SizedBox(width: 4),
                              Text(e.rating!.toStringAsFixed(2),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _gold)),
                            ],
                          ),
                  ),
                  _statDivider(),
                  _stat('SAVES', Text(e.saves ?? '—', style: _statValueStyle)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          // Action buttons
          Consumer(
            builder: (context, ref, _) {
              final library = ref.watch(libraryManagerProvider.notifier);
              ref.watch(libraryManagerProvider);
              final fav = library.isFavorite(widget.sourceId, widget.entry.id);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _actionButton(
                      icon: Icons.menu_book_outlined,
                      label: fav ? 'In Library' : 'Add to Library',
                      fg: fav ? _libraryFg : _defaultBtnFg,
                      bg: fav ? _libraryBg : _defaultBtnBg,
                      onTap: () => library.toggle(e),
                    ),
                    _actionButton(
                      icon: null,
                      customIcon: _soonIcon(_defaultBtnFg),
                      label: 'Soon',
                      fg: _defaultBtnFg,
                      bg: _defaultBtnBg,
                      onTap: () => _comingSoon('This'),
                    ),
                    _actionButton(
                      icon: Icons.check_circle_outline,
                      label: 'Trackers',
                      fg: _trackerFg,
                      bg: _trackerBg,
                      onTap: () => _comingSoon('Trackers'),
                    ),
                    _actionButton(
                      icon: Icons.explore_outlined,
                      label: 'WebView',
                      fg: _defaultBtnFg,
                      bg: _defaultBtnBg,
                      onTap: () => _openWebView(e),
                    ),
                    _actionButton(
                      icon: Icons.merge_type,
                      label: 'Merge',
                      fg: _defaultBtnFg,
                      bg: _defaultBtnBg,
                      onTap: () => _comingSoon('Merge'),
                    ),
                  ],
                ),
              );
            },
          ),
          // Synopsis
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: InkWell(
                onTap: () => setState(() => _descExpanded = !_descExpanded),
                child: Column(
                  children: [
                    Text(
                      desc,
                      maxLines: _descExpanded ? null : 2,
                      overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: _gray400, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      _descExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: _gray500,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          // Tags row
          if (e.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 38,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: e.genres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _tagBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(e.genres[i], style: const TextStyle(color: _tagFg, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _rankText(Entry e) {
    if (e.rank == null || e.rank!.isEmpty) return '—';
    return e.rank!.startsWith('#') ? e.rank! : '#${e.rank}';
  }

  static const _statValueStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white);

  Widget _stat(String label, Widget value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: _statLabel)),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 40, color: Colors.white10);

  Widget _metaRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _gray500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _gray400),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _soonIcon(Color color) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.calendar_today_outlined, color: color, size: 24),
        Positioned(
          bottom: -3,
          right: -3,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: _defaultBtnBg, shape: BoxShape.circle),
            child: Icon(Icons.watch_later_outlined, color: color, size: 13),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required Color fg,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(19)),
            child: customIcon ?? Icon(icon, color: fg, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Chapter list screen matching the "Premium Chapter List" design: sticky
/// header, unread red edge-bar indicator, dimmed read rows, glass download
/// buttons, and a squarcle play FAB that resumes at the first unread chapter.
class _ChapterListScreen extends StatefulWidget {
  final String title;
  final bool isAnime;
  final List<EntryChunk> chunks;
  final void Function(EntryChunk) onOpen;
  final Future<void> Function() onRefresh;

  const _ChapterListScreen({
    required this.title,
    required this.isAnime,
    required this.chunks,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  State<_ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<_ChapterListScreen> {
  bool _newestFirst = true;

  List<EntryChunk> get _sortedAsc {
    final list = List<EntryChunk>.from(widget.chunks);
    list.sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  List<EntryChunk> get _visible {
    final list = _sortedAsc;
    return _newestFirst ? list.reversed.toList() : list;
  }

  void _resume() {
    final asc = _sortedAsc;
    if (asc.isEmpty) return;
    final unread = asc.where((c) => !c.read);
    widget.onOpen(unread.isNotEmpty ? unread.first : asc.last);
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final word = widget.isAnime ? 'episodes' : 'chapters';
    return Scaffold(
      backgroundColor: _bgList,
      body: Column(
        children: [
          // Sticky header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: _bgList,
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
             children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFFD4D4D8), size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined, color: Color(0xFFD4D4D8), size: 22),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Downloads are not available yet.')),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_alt_outlined, color: Color(0xFFD4D4D8), size: 22),
                  tooltip: _newestFirst ? 'Newest first' : 'Oldest first',
                  onPressed: () => setState(() => _newestFirst = !_newestFirst),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Color(0xFFD4D4D8), size: 22),
                  onSelected: (v) {
                    if (v == 'refresh') widget.onRefresh();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  ],
                ),
              ],
            ),
          ),
          // Count bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: _bgList,
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                children: [
                  TextSpan(text: '${widget.chunks.length} $word '),
                  const TextSpan(
                    text: '(Total)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _gray500),
                  ),
                ],
              ),
            ),
          ),
          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 112),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final c = items[i];
                final unread = !c.read;
                final textColor = unread ? Colors.white : _readDim;
                final dateColor = unread ? const Color(0xFF71717A) : _readDim.withOpacity(0.8);
                return InkWell(
                  onTap: () => widget.onOpen(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white10)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (unread)
                          Positioned(
                            left: -20,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _accent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                                  boxShadow: [BoxShadow(color: _accent.withOpacity(0.7), blurRadius: 10)],
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, right: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                          color: textColor,
                                        ),
                                        children: [TextSpan(text: c.title)],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (c.uploadDate != null)
                                      Text(_fmtDate(c.uploadDate!),
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: dateColor)),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.file_download_outlined,
                                    color: unread ? const Color(0xFFD4D4D8) : _readDim, size: 20),
                                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Downloads are not available yet.')),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: _accent.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: widget.chunks.isEmpty ? null : _resume,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.play_arrow_rounded, color: Color(0xFF120406), size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
