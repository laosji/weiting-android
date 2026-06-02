import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:weiting_android/main.dart';

void main() {
  testWidgets('首页渲染头部与首次使用引导', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WeitingApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('微听'), findsOneWidget);
    expect(find.text('播放器'), findsOneWidget);
    expect(find.text('微听 FM'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
    expect(find.text('推荐节目'), findsNothing);
    expect(find.text('导入自己的节目单'), findsOneWidget);
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

    expect(find.text('导入节目'), findsOneWidget);
    expect(find.text('导入并保存'), findsOneWidget);
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
