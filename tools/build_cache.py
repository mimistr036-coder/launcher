#!/usr/bin/env python3
"""Сборка кэша игры «Провинция RP».

Складывает игровой проект в updates/www/game.pck (формат PCK v2 на чистом
Python — Godot не нужен), поднимает номер версии и пишет version.json,
который читает лаунчер. Повторный запуск без изменений кода версию НЕ
поднимает (сравнивается хеш исходников).

Использование:
    python3 tools/build_cache.py            # собрать кэш
    python3 tools/build_cache.py --force    # поднять версию даже без изменений
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME_DIR = os.path.join(ROOT, "game")
WWW_DIR = os.path.join(ROOT, "updates", "www")
PCK_PATH = os.path.join(WWW_DIR, "game.pck")
VER_PATH = os.path.join(WWW_DIR, "version.json")

sys.path.insert(0, HERE)
from pck import pack_files  # noqa: E402

INCLUDE_EXT = (".gd", ".tscn", ".tres", ".res", ".json", ".txt", ".cfg",
              ".glb", ".gltf", ".obj",  # свои 3D-модели
              ".png", ".jpg", ".jpeg", ".webp", ".svg",  # свои текстуры/картинки
              ".wav", ".ogg", ".mp3")  # свои звуки
SKIP_DIRS = {".godot", "builds", "__pycache__"}


def collect() -> dict:
    files = {}
    for dirpath, dirnames, filenames in os.walk(GAME_DIR):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.lower().endswith(INCLUDE_EXT):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, GAME_DIR).replace(os.sep, "/")
            with open(p, "rb") as f:
                files[rel] = f.read()
    # проект не включает project.godot: настройки остаются от лаунчера
    files.pop("project.godot", None)
    return files


def src_hash(files: dict) -> str:
    h = hashlib.sha256()
    for name in sorted(files):
        h.update(name.encode())
        h.update(files[name])
    return h.hexdigest()[:16]


def main() -> int:
    os.makedirs(WWW_DIR, exist_ok=True)
    files = collect()
    if not files:
        print("ОШИБКА: в game/ не найдено ни одного файла")
        return 1
    new_hash = src_hash(files)
    old = {}
    if os.path.exists(VER_PATH):
        try:
            with open(VER_PATH, "r", encoding="utf-8") as f:
                old = json.load(f)
        except Exception:
            old = {}
    force = "--force" in sys.argv
    if old.get("src_hash") == new_hash and not force and os.path.exists(PCK_PATH):
        print(f"Кэш актуален (v{old.get('version')}, хеш {new_hash}) — пересборка не нужна.")
        print("Подсказка: --force чтобы пересобрать принудительно.")
        return 0
    version = int(old.get("version", 0)) + 1
    # 4.0.0 в заголовке: любой Godot 4.2+ такой кэш откроет (движок отвергает
    # только кэш с версией СТАРШЕ своей), а формат PCK v2 читают все 4.2+.
    n = pack_files(files, PCK_PATH, engine_version=(4, 0, 0))
    md5 = hashlib.md5(open(PCK_PATH, "rb").read()).hexdigest()
    size = os.path.getsize(PCK_PATH)
    info = {
        "version": version,
        "file": "game.pck",
        "size": size,
        "md5": md5,
        "src_hash": new_hash,
    }
    with open(VER_PATH, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2)
    print(f"Готово: кэш v{version}")
    print(f"  файлов: {len(files)}")
    print(f"  размер: {size} байт ({size / 1024:.1f} КБ)")
    print(f"  md5:    {md5}")
    print(f"  -> {PCK_PATH}")
    print(f"  -> {VER_PATH}")
    print(f"  (упаковано {n} байт)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
