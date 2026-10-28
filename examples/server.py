#!/usr/bin/env python3
"""Локальный API задач, чтобы проверить виджет без своего сервера."""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HOST = "127.0.0.1"
PORT = 8787
LOCK = threading.Lock()
TASKS = [
    {
        "id": "1",
        "title": "Открыть веб-приложение",
        "done": False,
        "url": "https://example.com",
    },
    {
        "id": "2",
        "title": "Проверить виджет на рабочем столе",
        "done": False,
        "due": "2026-10-28",
    },
]
NEXT_ID = 3


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def _send(self, code, payload=None):
        data = b"" if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path != "/tasks":
            self._send(404, {"error": "not found"})
            return
        with LOCK:
            payload = {"tasks": TASKS}
        self._send(200, payload)

    def do_POST(self):
        global NEXT_ID
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path != "/tasks":
            self._send(404, {"error": "not found"})
            return
        try:
            body = self._read_json()
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid json"})
            return
        title = str(body.get("title", "")).strip()
        if not title:
            self._send(400, {"error": "title is required"})
            return
        with LOCK:
            task = {"id": str(NEXT_ID), "title": title, "done": False}
            NEXT_ID += 1
            TASKS.insert(0, task)
        self._send(201, task)

    def do_PATCH(self):
        path = urlparse(self.path).path.rstrip("/")
        prefix = "/tasks/"
        if not path.startswith(prefix):
            self._send(404, {"error": "not found"})
            return
        task_id = path[len(prefix) :]
        try:
            body = self._read_json()
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid json"})
            return
        with LOCK:
            for task in TASKS:
                if task["id"] != task_id:
                    continue
                if "done" in body:
                    task["done"] = bool(body["done"])
                found = dict(task)
                break
            else:
                found = None
        if found is None:
            self._send(404, {"error": "not found"})
            return
        self._send(200, found)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"API: http://{HOST}:{PORT}/tasks")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
