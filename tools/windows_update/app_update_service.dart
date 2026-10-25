import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String? releaseName;
  final String? releaseUrl;
  final String? releaseNotes;
  final bool hasUpdate;

  /// Windows 安装版：可直接下载并静默安装的 Setup.exe 直链。
  /// 由 Fork 仓库的 Release 附件提供，绿色版 Release（仅 zip）下为空。
  final String? installerUrl;
  final String? installerName;

  /// 安装包 SHA-256（GitHub Release 资产的 digest 字段），可能为空。
  final String? installerSha256;
  final int installerSize;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseName,
    this.releaseUrl,
    this.releaseNotes,
    this.installerUrl,
    this.installerName,
    this.installerSha256,
    this.installerSize = 0,
  });

  bool get hasInstaller =>
      installerUrl != null && installerUrl!.trim().isNotEmpty;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// 构建时通过 `--dart-define=FEINIU_UPDATE_REPO=owner/repo` 注入，
  /// 保证安装包与检查更新始终指向同一发布仓库（Fork）。
  static const String _repoOverride =
      String.fromEnvironment('FEINIU_UPDATE_REPO');

  static String get releaseRepo =>
      _repoOverride.trim().isNotEmpty ? _repoOverride.trim() : _fallbackRepo;

  static const String _fallbackRepo = 'kitblue/FeiNiuMusic';

  /// 上游官方仓库：Fork Release 拉取失败时兜底，仅用于提示新版本存在。
  static const String upstreamRepo = 'kuilei0926/FeiNiuMusic';

  static String get releasePageUrl =>
      'https://github.com/$releaseRepo/releases/latest';

  static String get latestReleaseApiUrl =>
      'https://api.github.com/repos/$releaseRepo/releases/latest';

  static String get upstreamReleaseApiUrl =>
      'https://api.github.com/repos/$upstreamRepo/releases/latest';

  /// 安装版安装包文件名特征：FeiNiuMusic-v1.6.9-Windows-Setup.exe
  static final RegExp installerAssetPattern =
      RegExp(r'(setup|installer|安装).*\.exe$', caseSensitive: false);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  String? _cachedVersion;

  /// The running app's clean release version (e.g. "1.3.1"), read from the
  /// platform. The build number is intentionally omitted — it's only a
  /// maintenance counter and shouldn't appear in the displayed version or
  /// affect update comparison.
  Future<String> currentVersion() async {
    final cached = _cachedVersion;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      _cachedVersion = v.isEmpty ? '0.0.0' : v;
      return _cachedVersion!;
    } catch (_) {
      return _cachedVersion ?? '0.0.0';
    }
  }

  Future<AppUpdateInfo> checkLatest(String currentVersion) async {
    // 优先查 Fork 发布仓库：只有它带 Windows 安装包资产，能闭环“检查-下载-安装”。
    final primary = await _fetch(latestReleaseApiUrl, currentVersion);
    if (primary != null) return primary;
    // Fork 不可达/无 Release 时回退上游：至少提示存在新版本。
    final fallback = await _fetch(upstreamReleaseApiUrl, currentVersion);
    if (fallback != null) return fallback;
    return AppUpdateInfo(latestVersion: currentVersion, hasUpdate: false);
  }

  Future<AppUpdateInfo?> _fetch(String apiUrl, String currentVersion) async {
    try {
      final response = await _dio.get(
        apiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'FeiNiuMusic',
          },
        ),
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;

      final tagName = (data['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) return null;
      final latestName = tagName.startsWith('v') || tagName.startsWith('V')
          ? tagName.substring(1)
          : tagName;
      final releaseName = data['name'] as String?;
      final body = data['body'] as String?;
      final htmlUrl = data['html_url'] as String?;

      final asset = _pickInstallerAsset(data['assets']);
      final hasUpdate = _compareVersions(latestName, currentVersion) > 0;
      return AppUpdateInfo(
        latestVersion: latestName,
        hasUpdate: hasUpdate,
        releaseName: releaseName,
        releaseUrl: htmlUrl ?? releasePageUrl,
        releaseNotes: body,
        installerUrl: asset?['browser_download_url'] as String?,
        installerName: asset?['name'] as String?,
        installerSha256: _digestSha256(asset?['digest'] as String?),
        installerSize: (asset?['size'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 在 Release 资产中挑选 Windows 安装包（Setup.exe）。
  /// zip/绿色版资产不参与匹配，避免把便携包当安装包静默执行。
  Map<String, dynamic>? _pickInstallerAsset(Object? assets) {
    if (assets is! List) return null;
    for (final item in assets) {
      if (item is! Map) continue;
      final name = (item['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      if (installerAssetPattern.hasMatch(name)) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  String? _digestSha256(String? digest) {
    if (digest == null) return null;
    final value = digest.trim();
    if (value.toLowerCase().startsWith('sha256:')) {
      final hex = value.substring(7).trim();
      return hex.isEmpty ? null : hex.toLowerCase();
    }
    return null;
  }

  String _normalizeVersion(String version) {
    final value = version.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }
    return value;
  }

  int _compareVersions(String a, String b) {
    // Compare only the release part (major.minor.patch); ignore any build or
    // prerelease suffix so maintenance builds (e.g. 1.3.1-2 vs 1.3.1) don't
    // register as a new version.
    List<int> release(String v) {
      var s = _normalizeVersion(v);
      final cut = s.indexOf(RegExp(r'[+\-]'));
      if (cut >= 0) s = s.substring(0, cut);
      return s.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }

    final left = release(a);
    final right = release(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
