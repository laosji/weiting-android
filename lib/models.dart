const playlistsKey = 'weibo-listen.playlists';
const maxItemsPerPlaylist = 200;

class PlaylistItem {
  const PlaylistItem({
    required this.sourceUrl,
    required this.title,
    required this.author,
    required this.category,
    required this.durationMs,
    required this.addedAt,
    this.unresolved = false,
  });

  final String sourceUrl;
  final String title;
  final String author;
  final String category;
  final int durationMs;
  final int addedAt;
  final bool unresolved;

  Map<String, Object?> toJson() => {
        'sourceUrl': sourceUrl,
        'title': title,
        'author': author,
        'category': category,
        'durationMs': durationMs,
        'addedAt': addedAt,
        'unresolved': unresolved,
      };

  factory PlaylistItem.fromJson(Map<String, Object?> json) => PlaylistItem(
        sourceUrl: json['sourceUrl'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        category: json['category'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
        unresolved: json['unresolved'] == true,
      );
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final List<PlaylistItem> items;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
        id: json['id'] as String? ?? newPlaylistId(),
        name: json['name'] as String? ?? '我的节目',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? nowMs(),
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? nowMs(),
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => PlaylistItem.fromJson(item.cast<String, Object?>()))
            .where((item) => item.sourceUrl.isNotEmpty)
            .toList(),
      );
}

List<String> extractUrls(String text) {
  final matches = RegExp(r'https?://[^\s"' "'" r'<>，。；、]+').allMatches(text);
  final seen = <String>{};
  final urls = <String>[];
  for (final match in matches) {
    final url = match.group(0)?.replaceAll(RegExp(r'[),，。；;]+$'), '') ?? '';
    if (!looksLikeSupportedUrl(url) || seen.contains(url)) continue;
    seen.add(url);
    urls.add(url);
  }
  return urls;
}

bool looksLikeSupportedUrl(String value) {
  final uri = Uri.tryParse(value);
  final host = uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';
  return host == 'weibo.com' ||
      host == 'm.weibo.cn' ||
      host == 'weibo.cn' ||
      host == 'video.weibo.com' ||
      host == 't.cn' ||
      host == 'xiaohongshu.com' ||
      host == 'xhslink.com';
}

String inferCategory(String title, String author, int durationMs) {
  final haystack = '$title $author';
  if (RegExp(
    r'有声书|听书|小说|名著|读书|品读|完整版|人类简史|活着|老人与海|傲慢与偏见|菜根谭|墨菲定律|非暴力沟通',
  ).hasMatch(haystack)) {
    return '听书';
  }
  if (durationMs > 0 &&
      durationMs <= 15 * 60 * 1000 &&
      RegExp(r'《.+》').hasMatch(title)) {
    return '听歌';
  }
  return '节目';
}

String displayTitle(PlaylistItem item) {
  var title = item.title.trim();
  if (item.category == '听书') {
    title = title
        .replaceAll(RegExp(r'[【】]'), '')
        .replaceAll(RegExp(r'有声书[:：]?\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  return title.isEmpty ? item.title : title;
}

List<MapEntry<String, List<PlaylistItem>>> groupRecommendedItems(
  List<PlaylistItem> items,
) {
  const preferredOrder = ['听书', '听歌', '节目'];
  final groups = <String, List<PlaylistItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.category, () => <PlaylistItem>[]).add(item);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      final ai = preferredOrder.indexOf(a);
      final bi = preferredOrder.indexOf(b);
      if (ai == -1 && bi == -1) return a.compareTo(b);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
  return keys.map((key) => MapEntry(key, groups[key]!)).toList();
}

String formatDuration(int ms) {
  if (ms <= 0) return '';
  final total = ms ~/ 1000;
  final seconds = total % 60;
  final minutes = (total ~/ 60) % 60;
  final hours = total ~/ 3600;
  String pad(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '${pad(hours)}:${pad(minutes)}:${pad(seconds)}'
      : '${pad(minutes)}:${pad(seconds)}';
}

String newPlaylistId() =>
    'pl_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

int nowMs() => DateTime.now().millisecondsSinceEpoch;
