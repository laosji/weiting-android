import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_page.dart';
import 'api.dart';
import 'models.dart';
import 'recommended.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.showmyapps.weiting_android.audio',
      androidNotificationChannelName: '微听播放',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    );
  } catch (e) {
    // 后台服务初始化失败时降级到普通播放，避免直接白屏
    debugPrint('JustAudioBackground init failed: $e');
  }
  runApp(const WeitingApp());
}

class WeitingApp extends StatelessWidget {
  const WeitingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xfffbfaf7);
    const text = Color(0xff242520);
    const accent = Color(0xffd9574b);

    return MaterialApp(
      title: '微听',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: const Color(0xfffffefa),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: text,
          displayColor: text,
          fontFamily: 'Roboto',
        ),
      ),
      home: const PlaylistImportPage(),
    );
  }
}

class PlaylistImportPage extends StatefulWidget {
  const PlaylistImportPage({super.key});

  @override
  State<PlaylistImportPage> createState() => _PlaylistImportPageState();
}

class _PlaylistImportPageState extends State<PlaylistImportPage> {
  final _nameController = TextEditingController(text: '我的节目');
  final _linksController = TextEditingController();
  final _api = WeitingApi();
  final _player = AudioPlayer();
  final _importingNotifier = ValueNotifier(false);
  final _statusNotifier = ValueNotifier('');
  final _random = Random();

  List<Playlist> _playlists = [];
  bool _loading = true;
  bool _importing = false;
  String _status = '';
  String _activeUrl = '';
  String _busyUrl = '';
  bool _isPlaying = false;
  bool _importSheetOpen = false;
  bool _serviceDown = false;
  // 当前曲目用 ValueNotifier 承载，使已打开的播放页在 FM 自动续播换歌时也能实时刷新。
  final ValueNotifier<PlaylistItem?> _currentItemNotifier =
      ValueNotifier<PlaylistItem?>(null);
  PlaylistItem? get _currentItem => _currentItemNotifier.value;
  set _currentItem(PlaylistItem? value) => _currentItemNotifier.value = value;
  CancelToken? _importCancel;

  final Set<String> _expandedPlaylistIds = <String>{};

  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool _hadConnectivity = true;
  bool _autoRetrying = false;
  // 系统 FM 连续随机播放：非 null 表示正处于该分类的 FM 模式，
  // 一首播完会自动从同分类再随机取一首；用户从"我的列表"点播即退出。
  String? _fmCategory;
  bool _advancingFm = false;
  // 防止媒体地址永久失效时无限重试打爆 API / 耗电：
  // 每首歌最多自动重试 _maxAutoRetries 次，且两次之间至少间隔 _retryCooldown。
  static const int _maxAutoRetries = 2;
  static const Duration _retryCooldown = Duration(seconds: 5);
  String _retryUrl = '';
  int _retryCount = 0;
  DateTime _lastRetryAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();

    _playerSub = _player.playerStateStream.listen((playerState) {
      if (!mounted) return;
      // 正常进入 ready 且在播放，说明（重试后）已恢复，清零重试计数，
      // 这样长音频几小时后再次 URL 过期仍能重新自动恢复。
      if (playerState.processingState == ProcessingState.ready &&
          playerState.playing) {
        _retryCount = 0;
      }
      // 一首播完：若处于系统 FM 模式，自动随机续播下一首。
      if (playerState.processingState == ProcessingState.completed &&
          _fmCategory != null) {
        _advanceFm();
      }
      setState(() => _isPlaying = playerState.playing);
    });

    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace st) {
        debugPrint('player error: $error');
        _handlePlaybackError();
      },
    );

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (!_hadConnectivity && hasNet) {
        // 网络从无到有，尝试恢复播放
        _maybeResume();
      }
      _hadConnectivity = hasNet;
    });

    _load();
    _checkServiceHealth();
  }

  @override
  void dispose() {
    _importCancel?.cancel();
    _nameController.dispose();
    _linksController.dispose();
    _importingNotifier.dispose();
    _statusNotifier.dispose();
    _currentItemNotifier.dispose();
    _playerSub?.cancel();
    _eventSub?.cancel();
    _connSub?.cancel();
    _player.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _checkServiceHealth() async {
    final ok = await _api.healthCheck();
    if (!mounted) return;
    setState(() => _serviceDown = !ok);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(playlistsKey);
    List<Playlist> playlists;
    try {
      final parsed = raw == null ? const [] : jsonDecode(raw);
      playlists = parsed is List
          ? parsed
                .whereType<Map>()
                .map((item) => Playlist.fromJson(item.cast<String, Object?>()))
                .toList()
          : <Playlist>[];
    } catch (_) {
      playlists = <Playlist>[];
    }
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _save(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      playlistsKey,
      jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
    );
  }

  Future<void> _importLinks() async {
    final urls = extractUrls(_linksController.text);
    if (urls.isEmpty) {
      _showMessage('没有识别到微博或小红书链接');
      return;
    }

    final name = _nameController.text.trim().isEmpty
        ? '我的节目'
        : _nameController.text.trim();
    final startedAt = nowMs();

    final cancel = CancelToken();
    _importCancel = cancel;

    setState(() {
      _importing = true;
      _status = '正在导入 0/${urls.length}';
    });
    _importingNotifier.value = true;
    _statusNotifier.value = _status;

    List<PlaylistItem> items;
    try {
      final results = await runBoundedConcurrent<String, PlaylistItem>(
        urls,
        concurrency: 4,
        cancelToken: cancel,
        onProgress: (done, total) {
          if (!mounted) return;
          final s = '正在导入 $done/$total';
          setState(() => _status = s);
          _statusNotifier.value = s;
        },
        op: (url) async {
          try {
            final resolved = await _api.resolveTrack(url, cancelToken: cancel);
            return _itemFromResolved(resolved, url);
          } on CancelledException {
            rethrow;
          } catch (_) {
            return PlaylistItem(
              sourceUrl: url,
              title: url,
              author: '',
              category: '节目',
              durationMs: 0,
              addedAt: nowMs(),
              unresolved: true,
            );
          }
        },
      );
      items = results;
    } on CancelledException {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _status = '已取消';
      });
      _importingNotifier.value = false;
      _statusNotifier.value = '已取消';
      return;
    } finally {
      _importCancel = null;
    }

    final next = [..._playlists];
    final existingIndex = next.indexWhere((playlist) => playlist.name == name);
    if (existingIndex >= 0) {
      final existing = next[existingIndex];
      final merged = [
        ...items,
        ...existing.items.where(
          (old) => !items.any((item) => item.sourceUrl == old.sourceUrl),
        ),
      ];
      next[existingIndex] = Playlist(
        id: existing.id,
        name: existing.name,
        createdAt: existing.createdAt,
        updatedAt: nowMs(),
        items: merged.take(maxItemsPerPlaylist).toList(),
      );
    } else {
      next.insert(
        0,
        Playlist(
          id: newPlaylistId(),
          name: name,
          createdAt: startedAt,
          updatedAt: nowMs(),
          items: items.take(maxItemsPerPlaylist).toList(),
        ),
      );
    }

    await _save(next);
    if (!mounted) return;
    setState(() {
      _playlists = next;
      _importing = false;
      _status = '已保存 ${items.length} 个节目';
      _linksController.clear();
    });
    _importingNotifier.value = false;
    _statusNotifier.value = _status;
    if (_importSheetOpen) {
      Navigator.of(context).maybePop();
    }
    _showMessage('已保存到「$name」');
  }

  void _cancelImport() {
    _importCancel?.cancel();
  }

  PlaylistItem _itemFromResolved(
    Map<String, Object?> track,
    String fallbackUrl,
  ) {
    final title = track['title'] as String? ?? fallbackUrl;
    final author = track['author'] as String? ?? '';
    final durationMs = (track['durationMs'] as num?)?.toInt() ?? 0;
    return PlaylistItem(
      sourceUrl: track['sourceUrl'] as String? ?? fallbackUrl,
      title: title,
      author: author,
      category: inferCategory(title, author, durationMs),
      durationMs: durationMs,
      addedAt: nowMs(),
    );
  }

  Future<void> _playItem(
    Playlist? playlist,
    PlaylistItem item, {
    bool openPlayer = true,
  }) async {
    // 用户从"我的列表"主动点播 → 退出系统 FM 模式（不再自动续播）。
    if (playlist != null) _fmCategory = null;

    if (_activeUrl == item.sourceUrl && _player.playing) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _isPlaying = false);
      return;
    }
    if (_activeUrl == item.sourceUrl &&
        !_player.playing &&
        _player.duration != null) {
      unawaited(_player.play());
      if (!mounted) return;
      setState(() => _isPlaying = true);
      if (openPlayer) await _openPlayerPage();
      return;
    }

    setState(() => _busyUrl = item.sourceUrl);
    try {
      final resolved = await _api.resolveTrack(item.sourceUrl);
      final mediaUrl = _api.mediaUrlFor(resolved);
      if (mediaUrl.isEmpty) {
        throw ApiException('没有可播放的媒体地址');
      }
      final resolvedItem = _itemFromResolved(resolved, item.sourceUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(mediaUrl),
          tag: MediaItem(
            id: resolvedItem.sourceUrl,
            title: displayTitle(resolvedItem),
            artist: resolvedItem.author.isEmpty
                ? resolvedItem.category
                : resolvedItem.author,
            album: resolvedItem.category,
            duration: resolvedItem.durationMs > 0
                ? Duration(milliseconds: resolvedItem.durationMs)
                : null,
          ),
        ),
      );
      unawaited(_player.play());

      if (playlist != null) {
        await _replacePlaylistItem(playlist.id, item.sourceUrl, resolvedItem);
      }
      if (!mounted) return;
      setState(() {
        _activeUrl = item.sourceUrl;
        _currentItem = resolvedItem;
        _isPlaying = true;
        _busyUrl = '';
      });
      if (openPlayer) await _openPlayerPage();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyUrl = '');
      _showMessage('暂时无法播放：$error');
    }
  }

  Future<void> _handlePlaybackError() async {
    if (_autoRetrying || _currentItem == null) return;

    final url = _currentItem!.sourceUrl;
    // 换了一首歌就重置计数
    if (_retryUrl != url) {
      _retryUrl = url;
      _retryCount = 0;
    }
    // 超过上限：不再自动重试，提示用户手动重试
    if (_retryCount >= _maxAutoRetries) {
      if (mounted) _showMessage('播放中断，请手动重试');
      return;
    }
    // 冷却：避免错误风暴里连续重试
    final sinceLast = DateTime.now().difference(_lastRetryAt);
    if (sinceLast < _retryCooldown) return;

    _autoRetrying = true;
    _retryCount++;
    _lastRetryAt = DateTime.now();
    try {
      // 静默重试：链接可能已过期，重新 resolve
      final resolved = await _api.resolveTrack(url);
      final mediaUrl = _api.mediaUrlFor(resolved);
      if (mediaUrl.isEmpty) return;
      final position = _player.position;
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(mediaUrl),
          tag: MediaItem(
            id: url,
            title: displayTitle(_currentItem!),
            artist: _currentItem!.author.isEmpty
                ? _currentItem!.category
                : _currentItem!.author,
            album: _currentItem!.category,
            duration: _currentItem!.durationMs > 0
                ? Duration(milliseconds: _currentItem!.durationMs)
                : null,
          ),
        ),
        initialPosition: position,
      );
      unawaited(_player.play());
    } catch (e) {
      debugPrint('auto retry failed: $e');
    } finally {
      _autoRetrying = false;
    }
  }

  Future<void> _maybeResume() async {
    if (_currentItem == null) return;
    if (_player.playing) return;
    // 网络刚恢复，主动重试一次
    await _handlePlaybackError();
  }

  Future<void> _replacePlaylistItem(
    String playlistId,
    String oldUrl,
    PlaylistItem nextItem,
  ) async {
    final next = _playlists.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      final items = playlist.items
          .map((item) => item.sourceUrl == oldUrl ? nextItem : item)
          .toList();
      return Playlist(
        id: playlist.id,
        name: playlist.name,
        createdAt: playlist.createdAt,
        updatedAt: nowMs(),
        items: items,
      );
    }).toList();
    await _save(next);
    if (mounted) setState(() => _playlists = next);
  }

  Future<void> _deletePlaylist(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除列表'),
        content: const Text('确定要删除这个列表吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final next = _playlists.where((playlist) => playlist.id != id).toList();
    await _save(next);
    if (!mounted) return;
    setState(() => _playlists = next);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePlayback() async {
    if (_currentItem == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (!mounted) return;
    setState(() => _isPlaying = _player.playing);
  }

  Future<void> _openPlayerPage() async {
    if (_currentItem == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PlayerPage(
          player: _player,
          itemListenable: _currentItemNotifier,
          onToggle: _togglePlayback,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _isPlaying = _player.playing);
  }

  Future<void> _openImportSheet() async {
    if (_importing) return;
    _importSheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xfffbfaf7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xffded8ce),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '导入节目',
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xff242520),
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<bool>(
                      valueListenable: _importingNotifier,
                      builder: (context, importing, _) {
                        return ValueListenableBuilder<String>(
                          valueListenable: _statusNotifier,
                          builder: (context, status, _) => _ImportPanel(
                            nameController: _nameController,
                            linksController: _linksController,
                            importing: importing,
                            status: status,
                            onImport: _importLinks,
                            onCancel: _cancelImport,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _importSheetOpen = false;
    }
  }

  int _systemFmCountFor(String category) {
    return recommendedItems.where((item) => item.category == category).length;
  }

  List<PlaylistItem> _fmCandidates(String category) => recommendedItems
      .where((item) => category == '全部' || item.category == category)
      .toList();

  /// 从 [category] 随机取一首，尽量不与 [excludeUrl] 相同（候选>1 时）。
  PlaylistItem? _pickRandomFm(String category, {String? excludeUrl}) {
    final candidates = _fmCandidates(category);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    final pool = excludeUrl == null
        ? candidates
        : candidates.where((item) => item.sourceUrl != excludeUrl).toList();
    final effective = pool.isEmpty ? candidates : pool;
    return effective[_random.nextInt(effective.length)];
  }

  Future<void> _startSystemFm(String category) async {
    final pick = _pickRandomFm(category);
    if (pick == null) {
      _showMessage(category == '全部' ? '系统 FM 暂无内容' : '系统 FM 暂无$category内容');
      return;
    }
    _fmCategory = category; // 进入 FM 模式，播完自动续播
    await _playItem(null, pick);
  }

  /// 当前 FM 歌曲自然播放结束时，自动随机续播同分类下一首。
  Future<void> _advanceFm() async {
    final category = _fmCategory;
    if (category == null || _advancingFm) return;
    _advancingFm = true;
    try {
      final next = _pickRandomFm(category, excludeUrl: _activeUrl);
      if (next == null) {
        _fmCategory = null;
        return;
      }
      // 续播不强行弹出/叠加播放页；已打开的播放页会随 notifier 自动刷新。
      await _playItem(null, next, openPlayer: false);
    } finally {
      _advancingFm = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _loading
          ? null
          : _MiniPlayer(
              player: _player,
              item: _currentItem,
              isPlaying: _isPlaying,
              onToggle: _togglePlayback,
              onOpenPlayer: _openPlayerPage,
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyHeaderDelegate(
                      isImportOpen: _importSheetOpen,
                      onImportTap: _importing ? null : _openImportSheet,
                      onAboutTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutPage()),
                      ),
                    ),
                  ),
                  if (_serviceDown)
                    SliverToBoxAdapter(
                      child: _ServiceBanner(onRetry: _checkServiceHealth),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    sliver: SliverList.list(
                      children: [
                        const _SectionTitle(title: '播放器'),
                        const SizedBox(height: 10),
                        _PlayerHomePanel(
                          totalCount: recommendedItems.length,
                          bookCount: _systemFmCountFor('听书'),
                          musicCount: _systemFmCountFor('听歌'),
                          activeUrl: _activeUrl,
                          isPlaying: _isPlaying,
                          busyUrl: _busyUrl,
                          onPlayAll: () => _startSystemFm('全部'),
                          onPlayBooks: () => _startSystemFm('听书'),
                          onPlayMusic: () => _startSystemFm('听歌'),
                          onImport: _importing ? null : _openImportSheet,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '我的列表',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xff242520),
                              ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  if (_playlists.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(18, 0, 18, 124),
                      sliver: SliverToBoxAdapter(child: _EmptyState()),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 124),
                      sliver: SliverList.builder(
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = _playlists[index];
                          return _PlaylistCard(
                            playlist: playlist,
                            isExpanded: _expandedPlaylistIds.contains(
                              playlist.id,
                            ),
                            activeUrl: _activeUrl,
                            isPlaying: _isPlaying,
                            busyUrl: _busyUrl,
                            onPlay: (item) => _playItem(playlist, item),
                            onToggleExpanded: () {
                              setState(() {
                                if (!_expandedPlaylistIds.add(playlist.id)) {
                                  _expandedPlaylistIds.remove(playlist.id);
                                }
                              });
                            },
                            onDelete: () => _deletePlaylist(playlist.id),
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ServiceBanner extends StatelessWidget {
  const _ServiceBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xfffff4ec),
          border: Border.all(color: const Color(0xfff6c4b5)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xffd9574b)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '解析服务暂时不可用，导入与播放可能失败。',
                style: TextStyle(
                  color: Color(0xff5e5b54),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyHeaderDelegate({
    required this.isImportOpen,
    required this.onImportTap,
    required this.onAboutTap,
  });

  final bool isImportOpen;
  final VoidCallback? onImportTap;
  final VoidCallback onAboutTap;

  static const double _height = 86;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final elevated = overlapsContent || shrinkOffset > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffbfaf7),
        border: Border(
          bottom: BorderSide(
            color: elevated ? const Color(0xffeee8df) : Colors.transparent,
          ),
        ),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x0f272218),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: _Header(
        isImportOpen: isImportOpen,
        onImportTap: onImportTap,
        onAboutTap: onAboutTap,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.isImportOpen != isImportOpen ||
        oldDelegate.onImportTap != onImportTap ||
        oldDelegate.onAboutTap != onAboutTap;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isImportOpen,
    required this.onImportTap,
    required this.onAboutTap,
  });

  final bool isImportOpen;
  final VoidCallback? onImportTap;
  final VoidCallback onAboutTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xfff6c4b5), Color(0xffd9574b)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1a272218),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.album_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '微听',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: const Color(0xff242520),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '把想听的视频，收进自己的列表。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xff5e5b54),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAboutTap,
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: '关于',
          ),
          IconButton.filledTonal(
            onPressed: onImportTap,
            icon: Icon(isImportOpen ? Icons.close_rounded : Icons.add_rounded),
            tooltip: isImportOpen ? '关闭导入' : '导入链接',
          ),
        ],
      ),
    );
  }
}

class _PlayerPage extends StatelessWidget {
  const _PlayerPage({
    required this.player,
    required this.itemListenable,
    required this.onToggle,
  });

  final AudioPlayer player;
  final ValueListenable<PlaylistItem?> itemListenable;
  final VoidCallback onToggle;

  void _seekBy(int seconds) {
    final duration = player.duration;
    final current = player.position;
    final next = current + Duration(seconds: seconds);
    final upper = duration ?? next;
    final bounded = next < Duration.zero
        ? Duration.zero
        : (duration != null && next > upper ? upper : next);
    player.seek(bounded);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaylistItem?>(
      valueListenable: itemListenable,
      builder: (context, item, _) {
        // 当前曲目为空（极端情况，如外部停止）→ 关闭播放页。
        if (item == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const Scaffold(
            backgroundColor: Color(0xfffbfaf7),
            body: SizedBox.shrink(),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xfffbfaf7),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        tooltip: '返回',
                      ),
                      const Expanded(
                        child: Text(
                          '正在播放',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xff5e5b54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                    child: Column(
                      children: [
                        StreamBuilder<PlayerState>(
                          stream: player.playerStateStream,
                          initialData: player.playerState,
                          builder: (context, snapshot) => _PlayerArtwork(
                            isPlaying: snapshot.data?.playing ?? false,
                            isBusy:
                                snapshot.data?.processingState ==
                                ProcessingState.loading,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          displayTitle(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                height: 1.18,
                                color: const Color(0xff242520),
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.author.isEmpty
                              ? item.category
                              : '${item.author} · ${item.category}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xffaaa49a),
                          ),
                        ),
                        const SizedBox(height: 36),
                        _PlayerProgress(player: player, item: item),
                        const SizedBox(height: 34),
                        _TransportControls(
                          player: player,
                          onToggle: onToggle,
                          onSeekBackward: () => _seekBy(-10),
                          onSeekForward: () => _seekBy(10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({required this.isPlaying, required this.isBusy});

  final bool isPlaying;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfffbf0ed), Color(0xfffffefa)],
        ),
        border: Border.all(color: const Color(0xfff0ddd8), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18272218),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 154,
            height: 154,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0xff242520), Color(0xff050505)],
              ),
            ),
          ),
          ...List.generate(
            6,
            (index) => Container(
              width: 58.0 + index * 16,
              height: 58.0 + index * 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xfffffefa),
            ),
            child: Center(
              child: Text(
                '微',
                style: TextStyle(
                  color: const Color(0xffd9574b).withValues(alpha: 0.88),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            right: 33,
            bottom: 33,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying
                    ? const Color(0xffd9574b)
                    : const Color(0xffded8ce),
                boxShadow: isPlaying
                    ? const [
                        BoxShadow(
                          color: Color(0x33d9574b),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          if (isBusy)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x33fffefa),
                  borderRadius: BorderRadius.all(Radius.circular(36)),
                ),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.player,
    required this.onToggle,
    required this.onSeekBackward,
    required this.onSeekForward,
  });

  final AudioPlayer player;
  final VoidCallback onToggle;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      initialData: player.playerState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: onSeekBackward,
              icon: const Icon(Icons.replay_10_rounded),
              iconSize: 34,
              color: const Color(0xff5e5b54),
              tooltip: '后退 10 秒',
            ),
            const SizedBox(width: 34),
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xffd9574b),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33d9574b),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: 74,
                child: IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 42,
                  ),
                  color: const Color(0xfffffefa),
                  tooltip: playing ? '暂停' : '播放',
                ),
              ),
            ),
            const SizedBox(width: 34),
            IconButton(
              onPressed: onSeekForward,
              icon: const Icon(Icons.forward_10_rounded),
              iconSize: 34,
              color: const Color(0xff5e5b54),
              tooltip: '前进 10 秒',
            ),
          ],
        );
      },
    );
  }
}

class _PlayerProgress extends StatelessWidget {
  const _PlayerProgress({required this.player, required this.item});

  final AudioPlayer player;
  final PlaylistItem item;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration =
            player.duration ?? Duration(milliseconds: item.durationMs);
        final durationMs = duration.inMilliseconds <= 0
            ? item.durationMs
            : duration.inMilliseconds;
        final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
        final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
        final remaining = Duration(
          milliseconds: (durationMs - value).clamp(0, durationMs).round(),
        );
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: max,
                value: value.clamp(0, max),
                activeColor: const Color(0xffd9574b),
                inactiveColor: const Color(0xffded8ce),
                onChanged: durationMs <= 0
                    ? null
                    : (next) =>
                          player.seek(Duration(milliseconds: next.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    formatDuration(position.inMilliseconds),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xff242520),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    durationMs > 0
                        ? '-${formatDuration(remaining.inMilliseconds)}'
                        : '00:00',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xff5e5b54),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.nameController,
    required this.linksController,
    required this.importing,
    required this.status,
    required this.onImport,
    required this.onCancel,
  });

  final TextEditingController nameController;
  final TextEditingController linksController;
  final bool importing;
  final String status;
  final VoidCallback onImport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffefa),
        border: Border.all(color: const Color(0xffeee8df)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0f272218),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '列表名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: linksController,
              minLines: 5,
              maxLines: 9,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: '粘贴微博 / 小红书视频链接',
                hintText: '每行一条，或直接粘贴一整段分享文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: importing ? null : onImport,
                    icon: importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_rounded),
                    label: Text(importing ? status : '导入并保存'),
                  ),
                ),
                if (importing) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onCancel, child: const Text('取消')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.isExpanded,
    required this.activeUrl,
    required this.isPlaying,
    required this.busyUrl,
    required this.onPlay,
    required this.onToggleExpanded,
    required this.onDelete,
  });

  final Playlist playlist;
  final bool isExpanded;
  final String activeUrl;
  final bool isPlaying;
  final String busyUrl;
  final ValueChanged<PlaylistItem> onPlay;
  final VoidCallback onToggleExpanded;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final total = playlist.items.fold<int>(
      0,
      (sum, item) => sum + item.durationMs,
    );
    const collapsedLimit = 6;
    final canCollapse = playlist.items.length > collapsedLimit;
    final visibleItems = canCollapse && !isExpanded
        ? playlist.items.take(collapsedLimit).toList()
        : playlist.items;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xfffffefa),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xffeee8df)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${playlist.items.length} 个节目${total > 0 ? ' · ${formatDuration(total)}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xffaaa49a),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '删除列表',
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...visibleItems.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => onPlay(item),
                title: Text(
                  displayTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  item.unresolved
                      ? '待解析'
                      : [
                          item.author,
                          formatDuration(item.durationMs),
                        ].where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _PlaybackIcon(
                  isBusy: busyUrl == item.sourceUrl,
                  isPlaying: activeUrl == item.sourceUrl && isPlaying,
                ),
              ),
            ),
            if (canCollapse)
              Center(
                child: TextButton.icon(
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isExpanded ? '收起' : '查看全部 ${playlist.items.length}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: const Color(0xff242520),
      ),
    );
  }
}

class _PlayerHomePanel extends StatelessWidget {
  const _PlayerHomePanel({
    required this.totalCount,
    required this.bookCount,
    required this.musicCount,
    required this.activeUrl,
    required this.isPlaying,
    required this.busyUrl,
    required this.onPlayAll,
    required this.onPlayBooks,
    required this.onPlayMusic,
    required this.onImport,
  });

  final int totalCount;
  final int bookCount;
  final int musicCount;
  final String activeUrl;
  final bool isPlaying;
  final String busyUrl;
  final VoidCallback onPlayAll;
  final VoidCallback onPlayBooks;
  final VoidCallback onPlayMusic;
  final VoidCallback? onImport;

  bool get _systemBusy =>
      busyUrl.isNotEmpty &&
      recommendedItems.any((item) => item.sourceUrl == busyUrl);

  bool get _systemPlaying =>
      isPlaying && recommendedItems.any((item) => item.sourceUrl == activeUrl);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffefa),
        border: Border.all(color: const Color(0xffeee8df)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d272218),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _FmDisc(),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '微听 FM',
                        style: TextStyle(
                          color: Color(0xff242520),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '随机播放系统精选内容。你的歌单保留在下方，点选后只播放自己的列表。',
                        style: TextStyle(
                          color: Color(0xff777168),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: totalCount > 0 ? onPlayAll : null,
                icon: _systemBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xfffffefa),
                        ),
                      )
                    : Icon(
                        _systemPlaying
                            ? Icons.pause_rounded
                            : Icons.shuffle_rounded,
                        size: 20,
                      ),
                label: Text(totalCount > 0 ? '随机播放' : '暂无系统 FM'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff242520),
                  foregroundColor: const Color(0xfffffefa),
                  disabledBackgroundColor: const Color(0xffded8ce),
                  disabledForegroundColor: const Color(0xff8f8980),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FmQuickButton(
                    icon: Icons.menu_book_rounded,
                    label: '听书',
                    count: bookCount,
                    onTap: bookCount > 0 ? onPlayBooks : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FmQuickButton(
                    icon: Icons.music_note_rounded,
                    label: '听歌',
                    count: musicCount,
                    onTap: musicCount > 0 ? onPlayMusic : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add_link_rounded, size: 18),
                label: const Text('导入自己的节目单'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xff242520),
                  side: const BorderSide(color: Color(0xffded8ce)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FmQuickButton extends StatelessWidget {
  const _FmQuickButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0xfff7f1e9) : const Color(0xfff3eee7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled
                    ? const Color(0xff5e5b54)
                    : const Color(0xffaaa49a),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  count > 0 ? '$label $count' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xff5e5b54)
                        : const Color(0xffaaa49a),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FmDisc extends StatelessWidget {
  const _FmDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xff242520),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1f272218),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.album_rounded, color: Color(0xfffffefa), size: 35),
          Icon(Icons.play_arrow_rounded, color: Color(0xffd9574b), size: 20),
        ],
      ),
    );
  }
}

class _PlaybackIcon extends StatelessWidget {
  const _PlaybackIcon({required this.isBusy, required this.isPlaying});

  final bool isBusy;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      isPlaying
          ? Icons.pause_circle_filled_rounded
          : Icons.play_circle_fill_rounded,
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.player,
    required this.item,
    required this.isPlaying,
    required this.onToggle,
    required this.onOpenPlayer,
  });

  final AudioPlayer player;
  final PlaylistItem? item;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final current = item;
    final hasCurrent = current != null;
    return SafeArea(
      top: false,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: GestureDetector(
          onTap: hasCurrent ? onOpenPlayer : null,
          child: Container(
            key: ValueKey(hasCurrent ? 'mini-player' : 'mini-player-empty'),
            width: double.infinity,
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: _playerDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const _AlbumTile(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasCurrent ? displayTitle(current) : '暂无播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xff242520),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasCurrent
                                ? (current.author.isEmpty
                                      ? current.category
                                      : '${current.author} · ${current.category}')
                                : '粘贴链接开始播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xffaaa49a),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: hasCurrent ? onToggle : null,
                      style: hasCurrent
                          ? _playButtonStyle
                          : _playButtonStyle.copyWith(
                              backgroundColor: const WidgetStatePropertyAll(
                                Color(0xffded8ce),
                              ),
                              foregroundColor: const WidgetStatePropertyAll(
                                Color(0xff8f8980),
                              ),
                            ),
                      child: Icon(
                        hasCurrent && isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                if (hasCurrent) ...[
                  const SizedBox(height: 8),
                  _PlayerProgress(player: player, item: current),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static final _playerDecoration = BoxDecoration(
    color: const Color(0xfffffefa),
    border: const Border(top: BorderSide(color: Color(0xffded8ce))),
    boxShadow: const [
      BoxShadow(
        color: Color(0x14272218),
        blurRadius: 22,
        offset: Offset(0, -6),
      ),
    ],
  );

  static final _playButtonStyle = FilledButton.styleFrom(
    fixedSize: const Size(54, 54),
    padding: EdgeInsets.zero,
    shape: const CircleBorder(),
    backgroundColor: const Color(0xffd9574b),
    foregroundColor: const Color(0xfffffefa),
  );
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xfff6c4b5), Color(0xffd9574b)],
        ),
      ),
      child: const Icon(Icons.album_rounded, color: Colors.white, size: 22),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffeee8df)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        '先粘贴几条你想听的视频链接。保存下来后，我们就能逐步看到真实的内容偏好。',
        style: TextStyle(color: Color(0xff5e5b54), height: 1.5),
      ),
    );
  }
}
