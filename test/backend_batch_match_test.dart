import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/feiniu/api_client.dart';
import 'package:feiniu_music/app/services/song_match/backend_match_client.dart';

import 'batch_match_test_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const songs = [
    {'guid': 'song-1', 'title': 'one'},
    {'guid': 'song-2', 'title': 'two'},
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FeiNiuApiClient.instance.setAuth('http://test.invalid', 'test-token');
  });

  Future<List<BatchMatchResult>> call(Map<String, dynamic> response) async {
    final adapter = BatchMatchTestAdapter(payload: response);
    final dio = Dio()..httpClientAdapter = adapter;
    BackendMatchClient.instance.setDioForTest(dio);
    try {
      return await BackendMatchClient.instance.batchMatch(songs: songs);
    } finally {
      dio.close();
    }
  }

  test('batch requests override the 30 second receive timeout', () async {
    final adapter = BatchMatchTestAdapter(
      payload: {
        'code': 0,
        'data': {
          'results': [
            {'guid': 'song-1', 'matched': true},
            {'guid': 'song-2', 'matched': false, 'error': 'no match'},
          ],
        },
      },
    );
    final dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 30)))
      ..httpClientAdapter = adapter;
    BackendMatchClient.instance.setDioForTest(dio);
    final result = await BackendMatchClient.instance.batchMatch(songs: songs);
    expect(adapter.lastRequest!.receiveTimeout, const Duration(minutes: 10));
    expect(adapter.lastRequest!.sendTimeout, const Duration(minutes: 1));
    expect(result.where((song) => song.matched).length, 1);
    dio.close();
  });

  test(
    'missing or malformed results do not silently become an empty success',
    () async {
      for (final response in [
        <String, dynamic>{'code': 0},
        <String, dynamic>{'code': 0, 'data': <String, dynamic>{}},
        <String, dynamic>{
          'code': 0,
          'data': {'results': 'invalid'},
        },
        <String, dynamic>{
          'code': 0,
          'data': {'results': []},
        },
      ]) {
        await expectLater(call(response), throwsFormatException);
      }
    },
  );

  test(
    'missing, duplicate or unexpected song IDs cannot count as completed',
    () async {
      for (final results in [
        [
          {'guid': 'song-1', 'matched': true},
        ],
        [
          {'guid': 'song-1', 'matched': true},
          {'guid': 'song-1', 'matched': true},
        ],
        [
          {'guid': 'song-1', 'matched': true},
          {'guid': 'unknown', 'matched': true},
        ],
        [
          {'guid': 'song-1', 'matched': true},
          'invalid',
        ],
      ]) {
        await expectLater(
          call({
            'code': 0,
            'data': {'results': results},
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('response order need not match request order', () async {
    final result = await call({
      'code': 0,
      'data': {
        'results': [
          {'guid': 'song-2', 'matched': false},
          {'guid': 'song-1', 'matched': true},
        ],
      },
    });
    expect(result.map((song) => song.guid).toList(), ['song-2', 'song-1']);
  });
}
