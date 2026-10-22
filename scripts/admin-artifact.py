#!/usr/bin/env python3
"""将固定版本和摘要的 Admin 发行物安装到空的发布 staging 目录。"""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tarfile

MANIFEST = "sparq-admin-manifest.json"
FORBIDDEN = {"__app__", "plugin-assets", "plugins", "platforms"}


def read_artifact(archive, expected_sha, version):
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
        raise ValueError("ADMIN_SHA256 必须是固定的 SHA256 摘要")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("ADMIN_VERSION 必须是不带 v 前缀的正式 SemVer")
    body = Path(archive).read_bytes()
    if hashlib.sha256(body).hexdigest() != expected_sha:
        raise ValueError("Admin 归档 SHA256 不匹配")
    files = {}
    with tarfile.open(fileobj=io.BytesIO(body), mode="r:gz") as reader:
        for member in reader:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                raise ValueError(f"Admin 归档路径越界：{member.name}")
            if not path.parts and member.isdir():
                continue
            if not path.parts or path.parts[0] in FORBIDDEN:
                raise ValueError(f"Admin 归档包含禁止发布的资源：{member.name}")
            if member.isdir():
                continue
            if not member.isfile() or str(path) in files:
                raise ValueError(f"Admin 归档含链接、特殊文件或重复文件：{member.name}")
            files[str(path)] = reader.extractfile(member).read()
    if MANIFEST not in files or "index.html" not in files:
        raise ValueError("Admin 归档缺少 manifest 或 index.html")
    manifest = json.loads(files[MANIFEST])
    if manifest.get("format") != "sparq.admin.artifact.v1" or manifest.get("version") != version:
        raise ValueError("Admin manifest 格式或版本与指定版本不一致")
    names = sorted(name for name in files if name != MANIFEST)
    if manifest.get("files") != names:
        raise ValueError("Admin manifest 文件清单与归档不一致")
    fingerprint = hashlib.sha256()
    for name in names:
        fingerprint.update(name.encode() + b"\0" + files[name] + b"\0")
    if manifest.get("fingerprint") != fingerprint.hexdigest():
        raise ValueError("Admin manifest 内容指纹不匹配")
    return files, manifest


def install(files, destination):
    # 先校验全部文件，再写入；禁止覆盖运行目录，避免破坏 __app__ 和 plugin-assets。
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Admin 目标必须不存在，拒绝覆盖：{destination}")
    if any(parent.is_symlink() for parent in destination.parents):
        raise ValueError(f"Admin 目标父路径不能包含符号链接：{destination}")
    for name in files:
        if any(str(parent) in files for parent in PurePosixPath(name).parents if str(parent) != "."):
            raise ValueError(f"Admin 归档文件与目录冲突：{name}")
    destination.mkdir(parents=True)
    for name, body in files.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    files, manifest = read_artifact(args.archive, args.sha256, args.version)
    if args.output:
        install(files, args.output)
    print(json.dumps({"admin_version": manifest["version"], "admin_sha256": args.sha256, "admin_fingerprint": manifest["fingerprint"]}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, tarfile.TarError) as error:
        raise SystemExit(str(error))
