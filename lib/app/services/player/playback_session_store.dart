import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/player_state.dart';
import '../../state/song_state.dart';

class PlaybackSession {
  final List<SongEntity> queue;
  final int index;
  final Duration position;
  final PlaybackMode mode;
  final bool wasPlaying;
  final String? roamId;

  PlaybackSession({
    required List<SongEntity> queue,
    required this.index,
    required this.position,
    required this.mode,
    required this.wasPlaying,
    this.roamId,
  }) : queue = List.unmodifiable(queue);

  Map<String, dynamic> toMap() => {
    'queue': queue.map((song) => song.toMap()).toList(),
    'index': index,
    'songId': queue[index].id,
    'positionMs': position.inMilliseconds,
    'mode': mode.name,
    'wasPlaying': wasPlaying,
    'roamId': roamId,
  };
}

class PlaybackSessionStore {
  static const _sessionKey = 'playback_session_v2';
  Future<void> _pendingWrite = Future.value();

  Future<PlaybackSession?> read({
    required bool Function(SongEntity) canRestoreSong,
  }) async {
    try {
      await _pendingWrite;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      // An explicit null snapshot keeps a cleared queue from restoring legacy data.
      final Object? decoded = raw != null
          ? jsonDecode(raw)
          : _readLegacy(prefs);
      if (decoded is! Map || decoded['queue'] is! List) return null;
      final savedIndex = decoded['index'] is int ? decoded['index'] as int : 0;
      final savedSongId = decoded['songId'];
      final queue = <SongEntity>[];
      final originalIndices = <int>[];
      final entries = decoded['queue'] as List;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry is! Map<String, dynamic>) continue;
        final song = SongEntity.fromMap(entry);
        if (song.id.trim().isEmpty ||
            (song.uri ?? '').trim().isEmpty ||
            song.isAudioFileDeleted ||
            !canRestoreSong(song)) {
          continue;
        }
        queue.add(song);
        originalIndices.add(i);
      }
      if (queue.isEmpty) return null;

      var index = originalIndices.indexOf(savedIndex);
      if (savedSongId is String && savedSongId.isNotEmpty) {
        if (index < 0 || queue[index].id != savedSongId) {
          index = queue.indexWhere((song) => song.id == savedSongId);
        }
      }
      final sameSong = index >= 0;
      if (index < 0) {
        index = originalIndices.indexWhere((i) => i >= savedIndex);
        if (index < 0) index = queue.length - 1;
      }
      var positionMs = sameSong && decoded['positionMs'] is int
          ? decoded['positionMs'] as int
          : 0;
      if (positionMs < 0) positionMs = 0;
      final durationMs = queue[index].durationMs;
      if (durationMs != null && durationMs > 0 && positionMs > durationMs) {
        positionMs = durationMs;
      }
      final mode = PlaybackMode.values.firstWhere(
        (mode) => mode.name == decoded['mode'],
        orElse: () => PlaybackMode.loop,
      );
      return PlaybackSession(
        queue: queue,
        index: index,
        position: Duration(milliseconds: positionMs),
        mode: mode,
        wasPlaying: decoded['wasPlaying'] == true,
        roamId: decoded['roamId'] is String
            ? decoded['roamId'] as String
            : null,
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Read playback session failed: $error');
      return null;
    }
  }

  Map<String, dynamic>? _readLegacy(SharedPreferences prefs) {
    final raw = prefs.getString('playback_queue_v1');
    if (raw == null || raw.trim().isEmpty) return null;
    return {
      'queue': jsonDecode(raw),
      'index': prefs.getInt('playback_index_v1') ?? 0,
      'songId': prefs.getString('playback_song_id_v1'),
      'positionMs': prefs.getInt('playback_position_v1') ?? 0,
      'mode': prefs.getString('playback_mode_v1'),
      'wasPlaying': prefs.getBool('playback_was_playing_v1') ?? false,
      'roamId': prefs.getString('playback_roam_id_v1'),
    };
  }

  Future<void> save(PlaybackSession? session) {
    // Capture before awaiting storage: later player events must not mix sessions.
    final raw = jsonEncode(session?.toMap());
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_sessionKey, raw)) {
          throw StateError('Playback session write was rejected');
        }
      } catch (error) {
        if (kDebugMode) debugPrint('Save playback session failed: $error');
      }
    });
    return _pendingWrite;
  }
}
