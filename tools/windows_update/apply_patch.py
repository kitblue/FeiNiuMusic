#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Fork 维护的「Windows 安装版自动更新」补丁应用到上游源码。

背景：fork 跟随上游 tag 发版，构建时拉的是上游源码，本仓库只在
`tools/windows_update/`、`installer/`、`.github/workflows/` 下维护自有改动。
因此每次构建前需要把下面三个 Dart 文件覆盖进上游源码：

  lib/app/services/app_update_service.dart      ← tools/windows_update/app_update_service.dart
  lib/components/dialog/app_update_dialog.dart  ← tools/windows_update/app_update_dialog.dart
  lib/app/services/windows_update_installer.dart ← 新增文件

覆盖是幂等的：无论目标文件是上游原版还是已打过补丁，结果都一致。
任何一步校验失败立即非零退出，避免静默产出「没有自动更新能力」的安装包。

用法：
  python apply_patch.py --root <上游源码根目录>
  python apply_patch.py --root ./src --check-only
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

PATCH_DIR = pathlib.Path(__file__).resolve().parent

TARGETS = {
    "app_update_service.dart": "lib/app/services/app_update_service.dart",
    "app_update_dialog.dart": "lib/components/dialog/app_update_dialog.dart",
    "windows_update_installer.dart": "lib/app/services/windows_update_installer.dart",
}

# 补丁必须携带的关键实现片段，缺一即视为补丁丢失
SIGNATURES = [
    ("lib/app/services/app_update_service.dart", "installerUrl"),
    ("lib/app/services/app_update_service.dart", "FEINIU_UPDATE_REPO"),
    ("lib/app/services/windows_update_installer.dart", "VERYSILENT"),
    ("lib/components/dialog/app_update_dialog.dart", "WindowsUpdateInstaller.canAutoInstall"),
]

# 依赖：安装包下载/校验与版本读取所需，上游 pubspec 必须已包含
REQUIRED_DEPS = ["dio:", "crypto:", "package_info_plus:", "path_provider:"]


def fail(msg: str) -> None:
    print(f"[apply_patch] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="上游源码根目录")
    ap.add_argument("--check-only", action="store_true", help="只校验，不写入")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    if not (root / "pubspec.yaml").exists():
        fail(f"{root} 不像 Flutter 项目根目录（缺少 pubspec.yaml）")

    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8", errors="replace")
    missing = [d for d in REQUIRED_DEPS if d not in pubspec]
    if missing:
        fail(f"pubspec.yaml 缺少依赖：{', '.join(missing)}（更新功能无法编译）")

    if args.check_only:
        print("[apply_patch] 依赖检查通过（--check-only，未写入文件）")
        return 0

    for src_name, dst_rel in TARGETS.items():
        src = PATCH_DIR / src_name
        if not src.exists():
            fail(f"补丁文件缺失：{src}")
        dst = root / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        print(f"[apply_patch] 写入 {dst_rel}")

    for rel, needle in SIGNATURES:
        path = root / rel
        content = path.read_text(encoding="utf-8", errors="replace")
        if needle not in content:
            fail(f"{rel} 缺少关键实现片段：{needle}")

    # 消费方（设置页）仍依赖这些符号，补丁必须保持兼容
    consumer = root / "lib/pages/settings/version_info_page.dart"
    if consumer.exists():
        text = consumer.read_text(encoding="utf-8", errors="replace")
        for symbol in ("checkLatest", "showAppUpdateDialog", "AppUpdateInfo"):
            if symbol not in text:
                print(
                    f"[apply_patch] WARN: version_info_page.dart 未引用 {symbol}，"
                    "请确认上游是否重构了更新入口",
                    file=sys.stderr,
                )

    print("[apply_patch] Windows 自动更新补丁应用完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
