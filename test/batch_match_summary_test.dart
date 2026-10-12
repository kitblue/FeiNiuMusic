import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feiniu_music/pages/songs/batch_match_summary.dart';

void main() {
  Widget build(
    String phase, {
    int completed = 0,
    int success = 0,
    int failed = 0,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: BatchMatchSummary(
          phase: phase,
          total: 6,
          completed: completed,
          success: success,
          failed: failed,
        ),
      ),
    );
  }

  testWidgets('timeout or incomplete response does not look completed', (
    tester,
  ) async {
    await tester.pumpWidget(build('error'));
    expect(find.text('客户端未收到完整结果'), findsOneWidget);
    expect(find.text('批量匹配完成'), findsNothing);
    expect(find.text('服务端可能仍在处理，请先核对结果，避免重复提交。'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
  });

  testWidgets('completed result shows full progress and counts', (
    tester,
  ) async {
    await tester.pumpWidget(build('done', completed: 6, success: 5, failed: 1));
    expect(find.text('批量匹配完成'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });

  testWidgets('in-flight request keeps its running title and progress', (
    tester,
  ) async {
    await tester.pumpWidget(build('running', completed: 2, success: 2));
    expect(find.text('正在匹配 2/6'), findsOneWidget);
    expect(find.text('批量匹配完成'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      2 / 6,
    );
  });
}
