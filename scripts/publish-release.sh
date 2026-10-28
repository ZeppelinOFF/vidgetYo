#!/bin/bash
# Create a GitHub Release and upload the DMG. Uses GH_TOKEN, no gh CLI.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${VERSION:?VERSION is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${TARGET_SHA:?TARGET_SHA is required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob
DMGS=("$ROOT"/dist/VidgetYo-"${VERSION}"-macOS27-*.dmg)
if [[ ${#DMGS[@]} -eq 0 ]]; then
  echo "ERROR: no DMG found in $ROOT/dist for version $VERSION."
  exit 1
fi

export DMG_DIR="$ROOT/dist"
python3 - <<'PY'
import json
import os
import urllib.error
import urllib.parse
import urllib.request

token = os.environ["GH_TOKEN"]
version = os.environ["VERSION"]
repo = os.environ["GITHUB_REPOSITORY"]
target = os.environ["TARGET_SHA"]
dmg_dir = os.environ["DMG_DIR"]
names = sorted(
    name
    for name in os.listdir(dmg_dir)
    if name.startswith(f"VidgetYo-{version}-macOS27-") and name.endswith(".dmg")
)
if not names:
    raise SystemExit(f"no DMG in {dmg_dir}")
listed = "\n".join(f"- `{name}`" for name in names)
notes = f"""Пакет собран из этого коммита после поднятия версии.

{listed}
- Release, macOS 27: `arm64` — Apple Silicon, `x86_64` — Intel
- Подпись ad-hoc, без Developer ID и нотаризации

Правила версии для пуша в `main`: `major` поднимает первую цифру, `minor` вторую, любое другое сообщение — третью.

Первый запуск может потребовать Control-click по приложению, затем «Открыть».
"""

def request(method, url, data=None, headers=None):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if headers:
        for key, value in headers.items():
            req.add_header(key, value)
    if body is not None and "Content-Type" not in (headers or {}):
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode() or "null")
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        print(raw)
        raise SystemExit(error.code)

status, payload = request(
    "POST",
    f"https://api.github.com/repos/{repo}/releases",
    {
        "tag_name": f"v{version}",
        "name": f"VidgetYo {version}",
        "body": notes,
        "target_commitish": target,
        "make_latest": "true",
    },
)
release_id = payload["id"]
print(f"Release {payload.get('html_url')} ({status})")

for name in names:
    path = os.path.join(dmg_dir, name)
    with open(path, "rb") as handle:
        data = handle.read()
    upload = (
        "https://uploads.github.com/repos/"
        f"{repo}/releases/{release_id}/assets?name={urllib.parse.quote(name)}"
    )
    req = urllib.request.Request(upload, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", "application/octet-stream")
    req.add_header("Content-Length", str(len(data)))
    try:
        with urllib.request.urlopen(req) as response:
            uploaded = json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        print(error.read().decode())
        raise SystemExit(error.code)
    print(f"Uploaded {uploaded.get('name')} ({uploaded.get('size')} bytes)")
PY
