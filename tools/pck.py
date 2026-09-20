#!/usr/bin/env python3
"""Мини-сборщик PCK (Godot 4.x, формат версии 2) на чистом Python.

Формат сверен с исходниками Godot 4.3 (core/io/pck_packer.cpp,
core/io/file_access_pack.cpp). Позволяет собирать кэш игры без Godot CLI —
в проекте только текстовые ресурсы (.gd/.tscn), импорт не требуется.

Пути в пакете хранятся БЕЗ префикса "res://", как это делает официальный
экспортер.
"""
import hashlib
import struct

MAGIC = b"GDPC"
FORMAT_VERSION = 2
ALIGN = 16


def _pad4(n: int) -> int:
    return (4 - (n % 4)) % 4


def pack_files(files: dict, out_path: str, engine_version=(4, 3, 0)) -> None:
    """files: {"br/boot.gd": bytes, ...} — пути относительно res://."""
    names = sorted(files.keys())
    # заголовок: magic, ver, major, minor, patch, flags, file_base(u64), 16x u32, count
    header_size = 4 + 4 + 4 + 4 + 4 + 4 + 8 + 64 + 4
    dir_size = 0
    for name in names:
        pb = name.encode("utf-8")
        dir_size += 4 + len(pb) + _pad4(len(pb)) + 8 + 8 + 16 + 4
    data_start = header_size + dir_size

    # раскладываем данные с выравниванием
    offsets = {}
    cur = data_start
    blob = bytearray()
    for name in names:
        pad = (ALIGN - (cur % ALIGN)) % ALIGN
        blob += b"\x00" * pad
        cur += pad
        offsets[name] = cur
        data = files[name]
        blob += data
        cur += len(data)

    out = bytearray()
    out += MAGIC
    out += struct.pack("<I", FORMAT_VERSION)
    out += struct.pack("<I", engine_version[0])
    out += struct.pack("<I", engine_version[1])
    out += struct.pack("<I", engine_version[2])
    out += struct.pack("<I", 0)          # pack_flags (без шифрования)
    out += struct.pack("<Q", 0)          # file_base
    out += b"\x00" * 64                  # 16 зарезервированных u32
    out += struct.pack("<I", len(names))
    for name in names:
        pb = name.encode("utf-8")
        out += struct.pack("<I", len(pb) + _pad4(len(pb)))
        out += pb
        out += b"\x00" * _pad4(len(pb))
        out += struct.pack("<Q", offsets[name])
        out += struct.pack("<Q", len(files[name]))
        out += hashlib.md5(files[name]).digest()
        out += struct.pack("<I", 0)      # flags файла
    out += blob

    with open(out_path, "wb") as f:
        f.write(bytes(out))
    return len(out)


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("usage: pck.py <dir> <out.pck>")
        sys.exit(1)
    import os
    root = sys.argv[1]
    files = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".godot", "builds")]
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if rel.endswith((".svg", ".import")):
                continue
            with open(p, "rb") as f:
                files[rel] = f.read()
    n = pack_files(files, sys.argv[2])
    print(f"packed {len(files)} files, {n} bytes -> {sys.argv[2]}")
