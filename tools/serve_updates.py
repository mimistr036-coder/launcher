#!/usr/bin/env python3
"""Локальный сервер обновлений (кэш + новости) для игры «Провинция RP».

Раздаёт содержимое updates/www по HTTP. Запусти на ПК — и тестируй лаунчер
с телефона в той же Wi-Fi сети:

    python3 tools/serve_updates.py            # порт 8090
    python3 tools/serve_updates.py 8080
"""
import http.server
import json
import os
import socket
import sys
import urllib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WWW = os.path.join(ROOT, "updates", "www")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WWW, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".pck"):
            return "application/octet-stream"
        if path.endswith(".json"):
            return "application/json"
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        sys.stdout.write("HTTP %s\n" % (fmt % args))
        sys.stdout.flush()


def lan_ips():
    ips = set()
    try:
        host = socket.gethostname()
        for info in socket.getaddrinfo(host, None):
            ip = info[4][0]
            if "." in ip and not ip.startswith("127."):
                ips.add(ip)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return sorted(ips)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    os.makedirs(WWW, exist_ok=True)
    httpd = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"Сервер обновлений: http://0.0.0.0:{port}/  (папка {WWW})")
    for ip in lan_ips():
        print(f"  в локальной сети: http://{ip}:{port}/  <- впиши этот адрес в лаунчер")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("Остановлено.")


if __name__ == "__main__":
    main()
