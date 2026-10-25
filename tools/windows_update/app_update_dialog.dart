import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services/app_update_service.dart';
import '../../app/services/windows_update_installer.dart';
import '../feedback/app_toast.dart';

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      AppToast.show(context, '无法打开浏览器，地址已复制');
    }
  }
}

/// Polished "update available" prompt. Shown for both manual checks and the
/// auto-check-on-launch flow.
///
/// Windows 安装版在 Release 提供 Setup.exe 资产时，可直接在弹窗内下载并
/// 静默安装（见 WindowsUpdateInstaller），其余平台仍引导到发布页。
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required String currentVersion,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateAvailableDialog(
      info: info,
      currentVersion: currentVersion,
    ),
  );
}

/// "Already on the latest version" confirmation (manual check only).
Future<void> showLatestVersionDialog(
  BuildContext context, {
  required String currentVersion,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.verified_rounded, color: scheme.primary, size: 32),
      title: const Text('已是最新版本'),
      content: Text('当前版本 $currentVersion 已是最新版本。'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('好的'),
        ),
      ],
    ),
  );
}

/// "Check failed" dialog with manual fallbacks (manual check only).
Future<void> showUpdateFailedDialog(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.cloud_off_rounded, color: scheme.error, size: 30),
      title: const Text('检查更新失败'),
      content: const Text('无法连接更新服务，请检查网络后重试，或手动打开发布页面。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: AppUpdateService.releasePageUrl),
            );
            if (!context.mounted) return;
            Navigator.pop(context);
            AppToast.show(context, '更新地址已复制');
          },
          child: const Text('复制地址'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            _openUrl(context, AppUpdateService.releasePageUrl);
          },
          child: const Text('手动打开'),
        ),
      ],
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class _UpdateAvailableDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final String currentVersion;

  const _UpdateAvailableDialog({
    required this.info,
    required this.currentVersion,
  });

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  CancelToken? _cancelToken;
  bool _downloading = false;
  bool _installing = false;
  double? _progress;
  String _status = '';
  String? _error;

  bool get _canAutoInstall => WindowsUpdateInstaller.canAutoInstall(widget.info);

  bool get _busy => _downloading || _installing;

  @override
  void dispose() {
    _cancelToken?.cancel('dialog disposed');
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    if (_busy) return;
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _downloading = true;
      _error = null;
      _progress = null;
      _status = '正在连接更新源…';
    });
    try {
      final file = await WindowsUpdateInstaller.download(
        widget.info,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
            _status = '正在下载 ${_formatBytes(received)} / ${_formatBytes(total)}';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
        _progress = 1;
        _status = '正在安装，应用将自动重启以完成更新…';
      });
      await WindowsUpdateInstaller.installAndExit(file);
    } on DioException catch (e) {
      if (!mounted) return;
      final cancelled = CancelToken.isCancel(e);
      setState(() {
        _downloading = false;
        _installing = false;
        _progress = null;
        _status = '';
        _error = cancelled ? null : '下载失败，请检查网络后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = false;
        _progress = null;
        _status = '';
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('user cancelled');
    setState(() {
      _downloading = false;
      _progress = null;
      _status = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = widget.info;
    final notes = (info.releaseNotes ?? '').trim();
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '发现新版本',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (info.releaseName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              info.releaseName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    _VersionChip(label: widget.currentVersion, dim: true),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    _VersionChip(label: info.latestVersion, dim: false),
                  ],
                ),
              ),
              if (notes.isNotEmpty)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 240),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          notes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: scheme.onSurface.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 下载/安装进度
              if (_busy || _error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_busy)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _installing ? null : _progress,
                            minHeight: 6,
                          ),
                        ),
                      if (_status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _status,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_downloading)
                      TextButton(
                        onPressed: _cancelDownload,
                        child: const Text('取消下载'),
                      )
                    else
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('稍后'),
                      ),
                    const SizedBox(width: 8),
                    if (_canAutoInstall)
                      FilledButton.icon(
                        onPressed: _busy ? null : _downloadAndInstall,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_rounded, size: 18),
                        label: Text(
                          _installing
                              ? '正在安装'
                              : (_downloading ? '下载中' : '下载并安装'),
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(context);
                                _openUrl(
                                  context,
                                  info.releaseUrl ??
                                      AppUpdateService.releasePageUrl,
                                );
                              },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('前往下载'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  final String label;
  final bool dim;

  const _VersionChip({required this.label, required this.dim});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dim
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: dim
            ? null
            : Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: dim ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
    );
  }
}
