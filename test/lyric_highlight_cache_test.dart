import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart';
import 'package:flutter_test/flutter_test.dart';

LyricModel _model(List<String> words) => LyricModel(
  lines: [
    LyricLine(
      start: Duration.zero,
      end: const Duration(seconds: 30),
      text: words.join(),
      words: [
        for (var i = 0; i < words.length; i++)
          LyricWord(
            text: words[i],
            start: Duration(seconds: i * 2),
            end: Duration(seconds: (i + 1) * 2),
          ),
      ],
    ),
  ],
);

void main() {
  testWidgets('切歌后行号不变、字数增多时高亮不越界', (tester) async {
    final controller = LyricController();
    controller.loadLyricModel(_model(['a', 'b']));
    await tester.pumpWidget(
      MaterialApp(home: LyricView(controller: controller)),
    );
    controller.setProgress(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    controller.loadLyricModel(_model(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']));
    for (var i = 1; i < 15; i++) {
      controller.setProgress(Duration(seconds: i));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('切歌后行号与分词数相同也重新测量字宽', (tester) async {
    final controller = LyricController();
    controller.loadLyricModel(_model(['a', 'b']));
    await tester.pumpWidget(
      MaterialApp(home: LyricView(controller: controller)),
    );
    controller.setProgress(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(LyricView));
    final initialWidth = state.activeHighlightWidthNotifier.value as double;
    expect(initialWidth, greaterThan(0));

    controller.loadLyricModel(_model(['aaaa', 'b']));
    state.updateHighlightWidth();
    await tester.pumpAndSettle();
    final newWidth = state.activeHighlightWidthNotifier.value as double;
    expect(newWidth, greaterThan(initialWidth * 2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
