import 'package:flutter/services.dart';

import 'debug_log_service.dart';

/// 原生退出必须等到 mpv 的回调注销完成后才允许销毁 Flutter 引擎。
class MacosAppExitService {
  MacosAppExitService({required this.prepareForExit});

  static const channel = MethodChannel('com.feiniu.music/app_exit');

  final Future<void> Function() prepareForExit;
  Future<void>? _shutdown;

  Future<void> init() async {
    channel.setMethodCallHandler(_handleCall);
    await channel.invokeMethod<void>('ready');
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'prepareForExit') throw MissingPluginException();
    DebugLogService.instance.add('[AppExit] preparing player shutdown');
    try {
      await (_shutdown ??= prepareForExit());
      DebugLogService.instance.add('[AppExit] player shutdown completed');
      await DebugLogService.instance.flush();
      return true;
    } catch (error, stack) {
      DebugLogService.instance.add('[AppExit] shutdown failed: $error\n$stack');
      await DebugLogService.instance.flush();
      rethrow;
    }
  }
}
