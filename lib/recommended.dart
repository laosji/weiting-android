import 'models.dart';

// 系统 FM 示例池（仅供"随机播放"按钮取样，App 不渲染可浏览的推荐列表）。
//
// 说明：下列 sourceUrl 均为**微博/微博短链(t.cn)的公开视频分享链接**，等同于
// 用户自己能在浏览器里打开的公开页面。App 本身不托管、不存储任何音视频内容，
// 仅在用户主动触发时，借助后端解析这些公开链接以便在手机上收听。
// 这些条目只是开箱即用的演示样例，可自由替换为你有权分发的内容。
//
// Sample pool for the "shuffle play" button only; the app does not render a
// browsable recommendation list. Every sourceUrl below is a PUBLIC Weibo /
// t.cn video share link — the same public page a user could open in a browser.
// The app hosts/stores no media; it only resolves these public links on demand.
const recommendedItems = <PlaylistItem>[
  PlaylistItem(
    sourceUrl: 'https://video.weibo.com/show?fid=1034:5207267984212022',
    title: '【有声书：世界名著《老人与海》】海明威著作，完整版',
    author: '思想品读',
    category: '听书',
    durationMs: 17195398,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'https://video.weibo.com/show?fid=1034:4763719205584906',
    title: '有声书世界名著《傲慢与偏见》下部，建议收藏转发听听',
    author: '追波逐影',
    category: '听书',
    durationMs: 34750375,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'https://video.weibo.com/show?fid=1034:4947460100128808',
    title: '有声书《菜根谭》原文及其译文',
    author: '追波逐影',
    category: '听书',
    durationMs: 32136832,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'https://video.weibo.com/show?fid=1034:5012665026936838',
    title: '听书《墨菲定律》完整版',
    author: '文史令官',
    category: '听书',
    durationMs: 26050652,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'http://t.cn/AXciUTgC',
    title: '《逆光》',
    author: '孙燕姿',
    category: '听歌',
    durationMs: 0,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'http://t.cn/AXVAMY6J',
    title: '《飞瀑而下》',
    author: '孙燕姿',
    category: '听歌',
    durationMs: 0,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'http://t.cn/AXUfHQ29',
    title: '《当你》',
    author: '林俊杰',
    category: '听歌',
    durationMs: 0,
    addedAt: 0,
  ),
  PlaylistItem(
    sourceUrl: 'http://t.cn/AXvf68oU',
    title: '《晚安》',
    author: '林俊杰',
    category: '听歌',
    durationMs: 0,
    addedAt: 0,
  ),
];
