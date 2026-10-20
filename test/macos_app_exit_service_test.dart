import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feiniu_music/app/services/macos_app_exit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> requestExit() async {
    final response = Completer<Object?>();
    await messenger.handlePlatformMessage(
      MacosAppExitService.channel.name,
      codec.encodeMethodCall(const MethodCall('prepareForExit')),
      (data) {
        try {
          response.complete(codec.decodeEnvelope(data!));
        } catch (error, stack) {
          response.completeError(error, stack);
        }
      },
    );
    return response.future;
  }

  setUp(() {
    messenger.setMockMethodCallHandler(MacosAppExitService.channel, (
      call,
    ) async {
      expect(call.method, 'ready');
      return null;
    });
  });

  tearDown(() {
    MacosAppExitService.channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(MacosAppExitService.channel, null);
  });

  test('退出请求等待清理完成，重复请求共用同一次清理', () async {
    final shutdown = Completer<void>();
    var calls = 0;
    final service = MacosAppExitService(
      prepareForExit: () {
        calls++;
        return shutdown.future;
      },
    );
    await service.init();
    var completed = false;
    final first = requestExit().then((value) {
      completed = true;
      return value;
    });
    final second = requestExit();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(completed, isFalse);
    shutdown.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('清理失败时不会通知原生允许退出', () async {
    final service = MacosAppExitService(
      prepareForExit: () async {
        throw StateError('dispose failed');
      },
    );
    await service.init();
    await expectLater(requestExit(), throwsA(isA<PlatformException>()));
  });
}
