import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/player_service.dart';
import 'package:feiniu_music/app/state/settings_state.dart';
import 'package:feiniu_music/app/state/song_state.dart';
import 'package:feiniu_music/pages/player/widgets/player_bottom_panel.dart';
import 'package:feiniu_music/pages/songs/song_detail_sheet.dart';

const _song = SongEntity(
  id: 'scroll-test',
  title: '横屏滚动测试',
  artist: '测试歌手',
  album: '{"guid":"test-album","name":"测试专辑"}',
  audioSpec: 'FLAC · 44.1 kHz',
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlayerBottomActionSettings.ensureLoaded();
    PlayerBottomActionSettings.showMore.value = true;
    PlayerService.instance.currentSong.value = _song;
  });

  tearDown(() {
    PlayerService.instance.currentSong.value = null;
  });

  for (final poster in [false, true]) {
    for (final rotate in [false, true]) {
      testWidgets(
        '${poster ? '海报' : '经典'}更多面板：${rotate ? '打开后旋转' : '横屏打开'}可滚动并点击底部选项',
        (tester) async {
          tester.view.physicalSize = rotate
              ? const Size(390, 844)
              : const Size(844, 390);
          tester.view.devicePixelRatio = 1;
          // 模拟手机横屏导航栏占用底部空间。
          tester.view.padding = FakeViewPadding(bottom: 24);
          addTearDown(tester.view.reset);

          final player = PlayerService.instance;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: poster
                    ? PosterControls(player: player)
                    : PlayerBottomPanel(
                        player: player,
                        stylePreset: PlayerStylePreset.classic,
                        onTapLyrics: () {},
                        showMiniLyrics: false,
                        compact: true,
                      ),
              ),
            ),
          );
          await tester.tap(
            find.byIcon(poster ? Icons.more_vert_rounded : Icons.more_horiz),
          );
          await tester.pumpAndSettle();

          if (rotate) {
            tester.view.physicalSize = const Size(844, 390);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);

          final scrollable = find.descendant(
            of: find.byType(SongDetailSheet),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.text('音频规格'),
            150,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(find.text('音频规格').hitTestable(), findsOneWidget);
          expect(tester.getRect(find.text('音频规格')).bottom, lessThan(366));

          await tester.ensureVisible(find.text(_song.title));
          await tester.pumpAndSettle();
          expect(find.text(_song.title).hitTestable(), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('音频规格'),
            150,
            scrollable: scrollable,
          );
          await tester.tap(find.text('音频规格'));
          await tester.pumpAndSettle();
          expect(find.byType(SongDetailSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
