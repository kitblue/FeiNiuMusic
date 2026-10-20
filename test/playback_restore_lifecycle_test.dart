import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/player/playback_session_store.dart';
import 'package:feiniu_music/app/services/player_service.dart';
import 'package:feiniu_music/app/state/song_state.dart';

void main() {
  testWidgets('启动恢复前的窗口事件不会把已保存歌曲和进度覆盖为空', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const audioChannel = MethodChannel('com.ryanheise.audio_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioChannel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(audioChannel, null));
    final saved = PlaybackSession(
      queue: const [
        SongEntity(
          id: 'previous',
          title: '上一首',
          artist: '测试歌手',
          uri: 'file:///private/tmp/previous.flac',
        ),
        SongEntity(
          id: 'current',
          title: '当前歌曲',
          artist: '测试歌手',
          uri: 'file:///private/tmp/current.flac',
          durationMs: 180000,
        ),
      ],
      index: 1,
      position: const Duration(seconds: 42),
      mode: PlaybackMode.loop,
      wasPlaying: true,
    );
    SharedPreferences.setMockInitialValues({
      'playback_session_v2': jsonEncode(saved.toMap()),
      'app_onboarding_completed': true,
    });
    final player = PlayerService.instance;
    // macOS 启动时窗口激活/失活可能早于异步的播放器恢复。
    player.didChangeAppLifecycleState(AppLifecycleState.inactive);
    player.didChangeAppLifecycleState(AppLifecycleState.hidden);
    player.didChangeAppLifecycleState(AppLifecycleState.detached);
    await tester.pump(const Duration(milliseconds: 300));

    final restored = await PlaybackSessionStore().read(
      canRestoreSong: (_) => true,
    );
    expect(restored, isNotNull);
    expect(restored!.queue[restored.index].id, 'current');
    expect(restored.position, const Duration(seconds: 42));
    expect(player.currentSong.value?.id, 'current');
    expect(player.position.value, const Duration(seconds: 42));
    unawaited(player.dispose());
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  });
}
