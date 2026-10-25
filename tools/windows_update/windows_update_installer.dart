import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'app_update_service.dart';

/// Windows 安装版的「静默更新」执行器：
/// 下载 GitHub Release 上的 Setup.exe → 校验 → 以 /VERYSILENT 启动安装 →
/// 退出当前进程，由安装程序接管替换文件并在安装完成后重新拉起应用。
class WindowsUpdateInstaller {
  WindowsUpdateInstaller._();

  static const String _downloadSubDir = 'feiniumusic_updates';

  /// 仅在 Windows 且 Release 提供安装包资产时可用。
  static bool get supported => Platform.isWindows;

  static bool canAutoInstall(AppUpdateInfo info) =>
      supported && info.hasInstaller;

  static Directory _downloadDir() {
    // 用系统临时目录（%TEMP%），不经过 path_provider：
    // 便携模式会重定向 path_provider，把安装包写进应用数据目录不合适。
    // 这里只跑在 Windows，直接用 pathSeparator 拼接，避免额外依赖 path 包。
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$_downloadSubDir',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'FeiNiuMusic-Setup.exe' : cleaned;
  }

  /// 下载安装包，返回落盘后的文件；失败抛异常由调用方提示。
  static Future<File> download(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = info.installerUrl;
    if (url == null || url.trim().isEmpty) {
      throw StateError('更新源未提供安装包地址');
    }
    final dir = _downloadDir();
    final fileName = _safeFileName(info.installerName ?? 'FeiNiuMusic-Setup.exe');
    final target = File('${dir.path}${Platform.pathSeparator}$fileName');
    final part = File('${target.path}.part');
    if (part.existsSync()) {
      try {
        part.deleteSync();
      } catch (_) {}
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 30),
        followRedirects: true,
        headers: const {'User-Agent': 'FeiNiuMusic'},
      ),
    );
    try {
      await dio.download(
        url,
        part.path,
        deleteOnError: true,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received, total);
        },
      );
    } finally {
      dio.close();
    }

    final length = await part.length();
    // 防御：GitHub 限流页/错误页也会 200，用最小体积阈值挡住假安装包。
    const minBytes = 5 * 1024 * 1024;
    if (length < minBytes) {
      try {
        await part.delete();
      } catch (_) {}
      throw StateError('安装包体积异常（$length 字节），已放弃安装');
    }
    if (info.installerSize > 0 && length != info.installerSize) {
      try {
        await part.delete();
      } catch (_) {}
      throw StateError('安装包大小与发布信息不一致，已放弃安装');
    }

    final expected = info.installerSha256;
    if (expected != null && expected.trim().isNotEmpty) {
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString().toLowerCase() != expected.trim().toLowerCase()) {
        try {
          await part.delete();
        } catch (_) {}
        throw StateError('安装包校验失败，已放弃安装');
      }
    }

    if (target.existsSync()) {
      try {
        target.deleteSync();
      } catch (_) {}
    }
    await part.rename(target.path);
    return target;
  }

  /// 静默启动安装程序并退出当前应用。
  ///
  /// 安装脚本（Inno Setup）配置了 CloseApplications=yes，并会在安装结束后
  /// 自动拉起新版本，因此这里只需确保安装进程脱壳存活、当前进程尽快退出。
  static Future<void> installAndExit(File installer) async {
    if (!installer.existsSync()) {
      throw StateError('安装包不存在：${installer.path}');
    }
    await Process.start(
      installer.path,
      const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/FORCECLOSEAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
    );
    // 给安装进程一点启动时间，再让出进程锁（安装器会等旧进程退出后替换文件）。
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    exit(0);
  }
}
