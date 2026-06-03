import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:weiting_android/main.dart';

void main() {
  testWidgets('首页渲染头部、微听 FM 与空状态引导', (WidgetTester tester) async {
    // 加高测试视口，确保唱片机 + 空状态等全部内容都被构建（slivers 懒加载）
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WeitingApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('微听'), findsOneWidget);
    expect(find.text('微听 FM'), findsOneWidget);
    // FM 走带：听书/听歌 副控 + 圆形播放主控（无"随机播放"文字了）
    expect(find.text('听书'), findsOneWidget);
    expect(find.text('听歌'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.text('我的列表'), findsOneWidget);
    // 旧的"播放器"标题和重复导入按钮已移除
    expect(find.text('播放器'), findsNothing);
    expect(find.text('导入自己的节目单'), findsNothing);
    // 空状态引导 + 主 CTA
    expect(find.text('还没有自己的节目'), findsOneWidget);
    expect(find.text('导入节目'), findsOneWidget);
  });

  testWidgets('点击 + 按钮打开导入面板', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WeitingApp());
    await tester.pump(const Duration(milliseconds: 100));

    // header 中的 "导入链接" 按钮（add_rounded 图标）
    final importBtn = find.byTooltip('导入链接');
    expect(importBtn, findsOneWidget);
    await tester.tap(importBtn);
    await tester.pumpAndSettle();

    // "导入节目" 既是弹窗标题又是空状态按钮，用唯一文案断言弹窗
    expect(find.text('导入并保存'), findsOneWidget);
    expect(find.text('列表名'), findsOneWidget);
  });

  testWidgets('点击 i 按钮打开关于页', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WeitingApp());
    await tester.pump(const Duration(milliseconds: 100));

    final aboutBtn = find.byTooltip('关于');
    expect(aboutBtn, findsOneWidget);
    await tester.tap(aboutBtn);
    await tester.pumpAndSettle();

    expect(find.text('关于微听'), findsOneWidget);
    // package_info 在测试环境下也会触发 FutureBuilder，但 await pumpAndSettle 已经处理
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
