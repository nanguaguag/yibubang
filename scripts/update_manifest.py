#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
自动更新 yibubang_update.json 清单脚本
在 GitHub Actions 打包发布时被调用，根据 Tag 版本号和 Release 说明更新清单内容。
"""

import json
import os
import re
import sys

def update_manifest(tag_name: str, release_notes: str = "", repo: str = "nanguaguag/yibubang"):
    clean_version = re.sub(r'^[vV]', '', tag_name.strip()).split('+')[0].strip()
    if not clean_version:
        raise ValueError(f"无法从 Tag 解析有效版本号: '{tag_name}'")

    file_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "yibubang_update.json")
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"未找到清单文件: {file_path}")

    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    data["latest_app"] = clean_version
    data["latest_app_url"] = f"https://github.com/{repo}/releases/tag/v{clean_version}"

    if release_notes and release_notes.strip():
        data["update_info"] = f"【医不帮 v{clean_version}】：\n\n{release_notes.strip()}"

    data["assets"] = {
        "android": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-android.apk",
        "android_arm64": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-android-arm64-v8a.apk",
        "android_armv7": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-android-armeabi-v7a.apk",
        "android_x86_64": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-android-x86_64.apk",
        "windows": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-windows-x64.zip",
        "macos": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-macos.zip",
        "linux": f"https://github.com/{repo}/releases/download/v{clean_version}/yibubang-v{clean_version}-linux-x64.tar.gz"
    }

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        f.write("\n")

    print(f"✅ 成功将 yibubang_update.json 更新至版本 v{clean_version}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python3 update_manifest.py <tag_name> [release_notes_file_or_string]")
        sys.exit(1)

    tag = sys.argv[1]
    notes = ""
    if len(sys.argv) >= 3:
        raw_notes = sys.argv[2]
        if os.path.isfile(raw_notes):
            with open(raw_notes, "r", encoding="utf-8") as nf:
                notes = nf.read()
        else:
            notes = raw_notes

    update_manifest(tag, notes)
