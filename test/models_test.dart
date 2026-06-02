import 'package:flutter_test/flutter_test.dart';
import 'package:weiting_android/models.dart';

void main() {
  group('extractUrls', () {
    test('从分享文本中识别微博/小红书链接并去重', () {
      const text = '''
        来听这个：https://video.weibo.com/show?fid=1034:5069963929518150 ，
        和这个 http://t.cn/AXciUTgC，还有 https://m.weibo.cn/status/123，
        重复：https://video.weibo.com/show?fid=1034:5069963929518150。
        无关链接 https://example.com/foo 不应被识别。
      ''';
      final urls = extractUrls(text);
      expect(urls, [
        'https://video.weibo.com/show?fid=1034:5069963929518150',
        'http://t.cn/AXciUTgC',
        'https://m.weibo.cn/status/123',
      ]);
    });

    test('去除尾部中文标点', () {
      final urls = extractUrls('看这个：https://t.cn/abc。结束');
      expect(urls, ['https://t.cn/abc']);
    });

    test('过滤不支持的域名', () {
      final urls = extractUrls('https://google.com https://example.org/test');
      expect(urls, isEmpty);
    });

    test('支持小红书短链', () {
      final urls = extractUrls('https://xhslink.com/abc');
      expect(urls, ['https://xhslink.com/abc']);
    });
  });

  group('inferCategory', () {
    test('命中"有声书"等关键字归为听书', () {
      expect(inferCategory('有声书《活着》完整版', '某博主', 0), '听书');
      expect(inferCategory('听书《墨菲定律》', '', 0), '听书');
    });

    test('短时长且带书名号的标题归为听歌', () {
      expect(inferCategory('《逆光》', '孙燕姿', 4 * 60 * 1000), '听歌');
    });

    test('时长过长不算听歌', () {
      expect(inferCategory('《某节目》', '某人', 30 * 60 * 1000), '节目');
    });

    test('其他归为节目', () {
      expect(inferCategory('随便聊聊', '', 0), '节目');
    });
  });

  group('displayTitle', () {
    test('听书去除"有声书:"前缀和【】', () {
      expect(
        displayTitle(const PlaylistItem(
          sourceUrl: 'x',
          title: '【有声书：活着】完整版',
          author: '',
          category: '听书',
          durationMs: 0,
          addedAt: 0,
        )),
        '活着完整版',
      );
      expect(
        displayTitle(const PlaylistItem(
          sourceUrl: 'x',
          title: '有声书  《活着》  完整版',
          author: '',
          category: '听书',
          durationMs: 0,
          addedAt: 0,
        )),
        '《活着》 完整版',
      );
    });

    test('其它分类保持原标题', () {
      expect(
        displayTitle(const PlaylistItem(
          sourceUrl: 'x',
          title: '《逆光》',
          author: '',
          category: '听歌',
          durationMs: 0,
          addedAt: 0,
        )),
        '《逆光》',
      );
    });
  });

  group('formatDuration', () {
    test('小于 1 小时返回 mm:ss', () {
      expect(formatDuration(75 * 1000), '01:15');
    });
    test('超过 1 小时返回 hh:mm:ss', () {
      expect(formatDuration(3 * 3600 * 1000 + 5 * 60 * 1000 + 7 * 1000),
          '03:05:07');
    });
    test('0 或负数返回空串', () {
      expect(formatDuration(0), '');
      expect(formatDuration(-1), '');
    });
  });

  group('groupRecommendedItems', () {
    test('按 听书/听歌/节目 顺序分组', () {
      final groups = groupRecommendedItems(const [
        PlaylistItem(sourceUrl: 'a', title: 't', author: '', category: '节目', durationMs: 0, addedAt: 0),
        PlaylistItem(sourceUrl: 'b', title: 't', author: '', category: '听歌', durationMs: 0, addedAt: 0),
        PlaylistItem(sourceUrl: 'c', title: 't', author: '', category: '听书', durationMs: 0, addedAt: 0),
      ]);
      expect(groups.map((e) => e.key).toList(), ['听书', '听歌', '节目']);
    });
  });

  group('Playlist.fromJson', () {
    test('容忍缺字段', () {
      final p = Playlist.fromJson({'name': 'x'});
      expect(p.name, 'x');
      expect(p.id, startsWith('pl_'));
      expect(p.items, isEmpty);
    });
    test('过滤空 sourceUrl 项', () {
      final p = Playlist.fromJson({
        'id': 'id1',
        'name': 'n',
        'createdAt': 1,
        'updatedAt': 2,
        'items': [
          {'sourceUrl': 'http://t.cn/a', 'title': 'a'},
          {'sourceUrl': '', 'title': 'broken'},
        ],
      });
      expect(p.items.length, 1);
      expect(p.items.first.sourceUrl, 'http://t.cn/a');
    });
  });
}
