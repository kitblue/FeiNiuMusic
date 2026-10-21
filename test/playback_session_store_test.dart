import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/player/playback_session_store.dart';
import 'package:feiniu_music/app/state/player_state.dart';
import 'package:feiniu_music/app/state/song_state.dart';

SongEntity song(String id, {bool deleted = false, bool cue = false}) =>
    SongEntity(
      id: id,
      title: id,
      artist: '[]',
      uri: 'https://nas/music/$id.flac',
      durationMs: 180000,
      isAudioFileDeleted: deleted,
      isCue: cue,
      cueOffsetMs: cue ? 240000 : null,
    );

PlaybackSession session({List<SongEntity>? queue, int index = 1}) =>
    PlaybackSession(
      queue: queue ?? [song('a'), song('b', cue: true)],
      index: index,
      position: const Duration(seconds: 42),
      mode: PlaybackMode.shuffle,
      wasPlaying: true,
      roamId: 'roam-1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackSessionStore store;

  Future<PlaybackSession?> read() =>
      store.read(canRestoreSong: (song) => song.format != 'txt');

  Future<void> seed(Map<String, dynamic> data) async {
    SharedPreferences.setMockInitialValues({
      'playback_session_v2': jsonEncode(data),
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = PlaybackSessionStore();
  });

  test(
    'round trip restores queue, mode, song, CUE offset and progress',
    () async {
      await store.save(session());
      store = PlaybackSessionStore();
      final restored = (await read())!;
      expect(restored.queue.map((s) => s.id), ['a', 'b']);
      expect(restored.index, 1);
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.mode, PlaybackMode.shuffle);
      expect(restored.wasPlaying, isTrue);
      expect(restored.roamId, 'roam-1');
      expect(restored.queue[1].isCue, isTrue);
      expect(restored.queue[1].cueOffsetMs, 240000);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'playback_session_v2'});
    },
  );

  test('reads 1.6.8 legacy state and prefers subsequent snapshot', () async {
    SharedPreferences.setMockInitialValues({
      'playback_queue_v1': jsonEncode([song('legacy').toMap()]),
      'playback_index_v1': 0,
      'playback_song_id_v1': 'legacy',
      'playback_position_v1': 12000,
      'playback_mode_v1': 'single',
      'playback_was_playing_v1': false,
      'playback_roam_id_v1': 'old-roam',
    });
    final legacy = (await read())!;
    expect(legacy.queue.single.id, 'legacy');
    expect(legacy.position.inMilliseconds, 12000);
    expect(legacy.mode, PlaybackMode.single);
    expect(legacy.wasPlaying, isFalse);
    expect(legacy.roamId, 'old-roam');
    await store.save(session());
    expect((await read())!.queue.last.id, 'b');
    await store.save(null);
    store = PlaybackSessionStore();
    expect(
      await read(),
      isNull,
      reason: 'Clear must not resurrect legacy data',
    );
  });

  test(
    'concurrent updates and clear keep the newest coherent session',
    () async {
      final first = store.save(session());
      final clear = store.save(null);
      final last = store.save(session(queue: [song('new')], index: 0));
      await Future.wait([first, clear, last]);
      final restored = (await read())!;
      expect(restored.queue.single.id, 'new');
      expect(restored.index, 0);
      expect(restored.position, const Duration(seconds: 42));
      await store.save(null);
      expect(await read(), isNull);
    },
  );

  test('captures queue before caller changes it during a save', () async {
    final queue = [song('a')];
    final pending = store.save(session(queue: queue, index: 0));
    queue[0] = song('changed');
    await pending;
    expect((await read())!.queue.single.id, 'a');
  });

  test('keeps duplicate song occurrence at its saved index', () async {
    await store.save(
      session(queue: [song('a'), song('b'), song('a')], index: 2),
    );
    expect((await read())!.index, 2);
  });

  test(
    'filtering earlier entries keeps the current song and position',
    () async {
      final data = session().toMap();
      data['queue'] = [
        null,
        song('a', deleted: true).toMap(),
        song('b').toMap(),
      ];
      data['index'] = 2;
      await seed(data);
      final restored = (await read())!;
      expect(restored.queue.single.id, 'b');
      expect(restored.index, 0);
      expect(restored.position, const Duration(seconds: 42));
    },
  );

  test('missing current song selects the next playable song at zero', () async {
    final data = session().toMap();
    data['queue'] = [
      song('a').toMap(),
      song('b', deleted: true).toMap(),
      song('c').toMap(),
    ];
    await seed(data);
    final restored = (await read())!;
    expect(restored.queue[restored.index].id, 'c');
    expect(restored.position, Duration.zero);
  });

  test(
    'missing song ID never transfers progress to a different song',
    () async {
      final data = session().toMap()..['songId'] = 'missing';
      await seed(data);
      expect((await read())!.position, Duration.zero);
    },
  );

  test(
    'legacy index maps to original queue after invalid entries removed',
    () async {
      final data = session().toMap()..remove('songId');
      data['queue'] = [song('a').copyWith(uri: '').toMap(), song('b').toMap()];
      await seed(data);
      final restored = (await read())!;
      expect(restored.queue.single.id, 'b');
      expect(restored.position, const Duration(seconds: 42));
    },
  );

  test('non-audio entries are excluded and an empty queue is safe', () async {
    final data = session().toMap();
    data['queue'] = [song('a').copyWith(format: 'txt').toMap()];
    await seed(data);
    expect(await read(), isNull);
  });

  test('clamps invalid progress and defaults unknown mode', () async {
    final data = session().toMap()
      ..['positionMs'] = -50
      ..['mode'] = 'unknown';
    await seed(data);
    expect((await read())!.position, Duration.zero);
    expect((await read())!.mode, PlaybackMode.loop);
    data['positionMs'] = 999999;
    await seed(data);
    expect((await read())!.position.inMilliseconds, 180000);
  });

  test('out of range index falls back safely without old progress', () async {
    final data = session().toMap()
      ..remove('songId')
      ..['index'] = 999;
    await seed(data);
    final restored = (await read())!;
    expect(restored.index, 1);
    expect(restored.position, Duration.zero);
  });

  test('corrupt snapshot does not resurrect stale legacy queue', () async {
    SharedPreferences.setMockInitialValues({
      'playback_session_v2': '{broken',
      'playback_queue_v1': jsonEncode([song('legacy').toMap()]),
    });
    expect(await read(), isNull);
  });
}
