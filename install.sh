#!/usr/bin/env bash
# CPU AI Lab 0.3.2 - menu-driven, CPU-only personal AI server.
# Download this file, inspect it, then run: sudo bash install-cpu-ai.sh
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 022
APP=/opt/cpu-ai
OLLAMA_PIN=0.40.6
fail() { printf '\n❌ ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "Run with sudo bash $0"
APP_VERSION=0.3.2
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# User-supplied ANSI artwork. Keep escapes as text until printing to a terminal.
show_banner() {
  local ART
  ART=$(cat <<'CPU_AI_BANNER'
\e[0;97;41m█▀▀▀▀\e[0;37;41m▀▀▀▀\e[0;37m▄  \e[0;97;41m█▀▀▀▀\e[0;37;41m▀▀▀▀\e[0;37m▄                      \e[0;97m▄\e[0;97;41m▀▀▀\e[0;37;41m▀▀▀▀\e[0;37m▄  \e[0;97;41m█▀▀\e[0;37m█      \e[0;97;47m█\e[0;97;41m▀▀\e[0;97m█\e[0;37m         \e[0;97m▄\e[0;97;41m▀▀▀\e[0;37;41m▀▀▀▀\e[0;37m▄  \e[0;97;41m█▀▀▀▀\e[0;37;41m▀▀▀▀\e[0;37m▄ \e[0m
\e[0;97;41m█  ▄▄\e[0;37;41m▄▄   \e[0;37m█ \e[0;97;41m█  \e[0;90;41m▄▄\e[0;37;41m▄▄   \e[0;37m█                    \e[0;97;41m█   \e[0;90;41m▄\e[0;37;41m▄▄   \e[0;37m█ \e[0;97;41m█  \e[0;37m█      \e[0;97;47m█\e[0;97;41m  \e[0;97m█\e[0;37m        \e[0;97;41m█   \e[0;90;41m▄\e[0;37;41m▄▄   \e[0;37m█ \e[0;97;41m█  ▄▄\e[0;37;41m▄▄   \e[0;37m█\e[0m
\e[0;97;41m█  █\e[0;37m▄▄▄\e[0;37;41m▀  \e[0;37m█ \e[0;97m█\e[0;97;41m  \e[0;90;41m█\e[0;37m   █\e[0;37;41m  \e[0;37m█      \e[0;97m█\e[0;97;41m▀▀▀\e[0;37;41m▀▀▀█\e[0;37m      \e[0;97m█\e[0;97;41m  \e[0;90;47m█\e[0;37m   █\e[0;37;41m  \e[0;37m█ \e[0;97;41m█  \e[0;37m█      \e[0;97;47m█\e[0;97;41m  █\e[0;37m        \e[0;97m█\e[0;97;41m  \e[0;90;47m█\e[0;37m   █\e[0;37;41m  \e[0;37m█ \e[0;97m█\e[0;97;41m  █\e[0;37m▄▄▄\e[0;37;41m▀  \e[0;37m█\e[0m
\e[0;97;47m▀\e[0;97;41m        \e[0;90;47m▄\e[0;37m  \e[0;97;47m▀\e[0;97;41m  \e[0;37m█   \e[0;97;47m▄\e[0;97;41m  \e[0;90;47m▄\e[0;37m      █\e[0;37;41m▄▄▄\e[0;90;41m▄▄▄\e[0;90m█\e[0;37m      \e[0;97;47m▀\e[0;97;41m  \e[0;90;47m▀\e[0;37m▄\e[0;97m▄▄\e[0;97;41m█  \e[0;90;47m▄\e[0;37m \e[0;97;47m▀\e[0;97;41m  \e[0;90;47m▄\e[0;37m      \e[0;97;47m▀\e[0;97;41m  \e[0;97;47m▀\e[0;37m        \e[0;97;47m▀\e[0;97;41m  \e[0;90;47m▀\e[0;37m▄\e[0;97m▄▄\e[0;97;41m█  \e[0;90;47m▄\e[0;37m \e[0;97;47m▀\e[0;97;41m        \e[0;90;47m▄\e[0;37m \e[0m
\e[0;37m█\e[0;37;41m  \e[0;37m█▀\e[0;90m▀▀▀▀\e[0;37m   █\e[0;37;41m  \e[0;37m█   \e[0;97;41m█  \e[0;90;41m█\e[0;37m                    █\e[0;37;41m         \e[0;90;41m█\e[0;37m █\e[0;37;41m  \e[0;90;41m█\e[0;37m      █\e[0;37;41m  █\e[0;37m        █\e[0;37;41m         \e[0;90;41m█\e[0;37m █\e[0;37;41m  \e[0;97;41m█\e[0;97m▀\e[0;37m▀▀\e[0;37;41m▄  \e[0;90;41m█\e[0m
\e[0;37m█\e[0;37;41m  \e[0;37m█        █\e[0;37;41m  ▀▀\e[0;97;41m▀▀   \e[0;90;41m█\e[0;37m                    █\e[0;37;41m  \e[0;37m█▀\e[0;90m▀▀█\e[0;90;41m  \e[0;90m█\e[0;37m █\e[0;37;41m  \e[0;90;41m█\e[0;37m      █\e[0;37;41m  \e[0;31m█\e[0;37;41m▀▀\e[0;90;41m▀▀▀▀█\e[0;37m █\e[0;37;41m  \e[0;37m█▀\e[0;90m▀▀█\e[0;90;41m  \e[0;90m█\e[0;37m █\e[0;37;41m  \e[0;97;41m▀\e[0;37;41m▀▀▀   \e[0;90;41m█\e[0m
\e[0;37m█\e[0;37;41m▄▄\e[0;37m█        █\e[0;37;41m▄▄▄▄\e[0;90;41m▄▄▄▄\e[0;90m▀\e[0;37m                     █\e[0;37;41m▄▄\e[0;37m█   \e[0;90m█\e[0;90;41m▄▄\e[0;90m█\e[0;37m \e[0;90m█\e[0;90;41m▄▄█\e[0;37m       ▀\e[0;37;41m▄▄▄▄\e[0;90;41m▄▄▄▄█\e[0;37m █\e[0;37;41m▄▄\e[0;37m█   \e[0;90m█\e[0;90;41m▄▄\e[0;90m█\e[0;37m █\e[0;37;41m▄▄▄▄\e[0;90;41m▄▄▄▄\e[0;90m▀\e[0;37m \e[0m
CPU_AI_BANNER
)
  printf '\n'
  if [[ -t 1 && "${TERM:-dumb}" != dumb && ! -v NO_COLOR ]]; then
    printf '%b\n' "$ART"
  else
    # Log files and NO_COLOR terminals receive the same artwork without ANSI.
    printf '%s\n' "$ART" | sed 's/\\e\[[0-9;]*m//g'
  fi
  printf '\n  🤖 CPU AI LAB  |  v%s  |  CPU-only AI\n' "$APP_VERSION"
}

install_app() {
show_banner
command -v flock >/dev/null || fail "flock (util-linux) is required."
exec 9>/run/cpu-ai-install.lock
flock -n 9 || fail "Another CPU AI installer is running."
mkdir -p /var/log/cpu-ai
chmod 700 /var/log/cpu-ai
exec > >(tee -a /var/log/cpu-ai/install.log) 2>&1
trap 'echo "Install failed at line $LINENO. See /var/log/cpu-ai/install.log. Fix the error and run this installer again."' ERR
[[ -d /run/systemd/system ]] || fail "A running systemd host is required."
source /etc/os-release
case "$ID:$VERSION_ID" in
  ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:12|debian:13) PACKAGE_FAMILY=apt ;;
  rocky:*|almalinux:*|rhel:*|centos:*)
    [[ "${VERSION_ID%%.*}" -ge 9 ]] || fail "RHEL-family hosts require version 9 or newer."
    PACKAGE_FAMILY=dnf ;;
  fedora:*) PACKAGE_FAMILY=dnf ;;
  *) fail "Supported families: Ubuntu 22.04/24.04/26.04, Debian 12/13, RHEL-family 9+, Fedora. systemd is required." ;;
esac
case "$(uname -m)" in
  x86_64)
    ARCH=amd64
    DIGEST=c164ab8b1b28e2a247c29719b8e404c423c5b83ae64c3ab4e59d50c7ff7fc5e0
    grep -qw avx /proc/cpuinfo || fail "This x86 CPU needs AVX support."
    ;;
  aarch64)
    ARCH=arm64
    DIGEST=0a279d9428ad17b06fdb7dddf3b059b2c148433585fa3b30676a102fc4459bb9f
    ;;
  *) fail "Supported CPU architectures: amd64, arm64." ;;
esac
TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
AVAILABLE_KB=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
[[ "$TOTAL_KB" -ge 1800000 ]] || fail "At least approximately 2 GB RAM is required."
[[ "$(nproc)" -ge 2 ]] || fail "At least 2 available CPU threads are required."
MANAGED=0
[[ -f "$APP/.managed" ]] && MANAGED=1
if [[ -e "$APP" && "$MANAGED" -eq 0 ]]; then
  fail "$APP already exists but is not managed by this installer."
fi
if [[ "$MANAGED" -eq 0 ]]; then
  [[ "$AVAILABLE_KB" -ge 1200000 ]] || fail "At least 1.2 GB available RAM is required; stop other workloads first."
  [[ "$(df -Pk / | awk 'NR==2 {print $4}')" -ge 8000000 ]] || fail "At least 8 GB free disk space is required."
  if command -v ollama >/dev/null || systemctl cat ollama.service >/dev/null 2>&1; then
    [[ "${ADOPT_OLLAMA:-0}" == 1 ]] || fail "Existing Ollama detected. Use a fresh server; existing installations are not modified automatically."
  fi
fi
SAVED_ACCESS_MODE=${ACCESS_MODE:-}
if [[ -z "$SAVED_ACCESS_MODE" && -f "$APP/config.env" ]]; then
  SAVED_ACCESS_MODE=$(sed -n 's/^CPU_AI_ACCESS_MODE=//p' "$APP/config.env")
fi
SAVED_ACCESS_MODE=${SAVED_ACCESS_MODE:-auto}
MODEL=${MODEL:-}
if [[ -z "$MODEL" && -f "$APP/config.env" ]]; then
  MODEL=$(sed -n 's/^CPU_AI_MODEL=//p' "$APP/config.env")
fi
if [[ -z "$MODEL" ]]; then
  MODEL=qwen2.5:0.5b
  [[ "$AVAILABLE_KB" -lt 1400000 ]] || MODEL=qwen2.5:1.5b
fi
case "$MODEL" in
  qwen2.5:0.5b) ;;
  qwen2.5:1.5b)
    if [[ "$MANAGED" -eq 0 && "$AVAILABLE_KB" -lt 1400000 ]]; then
      fail "The 1.5b preset requires at least 1.4 million kB of available RAM at installation."
    fi
    ;;
  *) fail "Supported presets: qwen2.5:0.5b or qwen2.5:1.5b." ;;
esac
echo "🔎 CPU AI Lab | CPU threads: $(nproc) | RAM: $((TOTAL_KB/1024)) MiB | Model: $MODEL"
if [[ "$PACKAGE_FAMILY" == apt ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o DPkg::Lock::Timeout=120 update -qq
  apt-get -o DPkg::Lock::Timeout=120 install -y -qq ca-certificates curl zstd python3 procps iproute2 gzip
else
  dnf install -y ca-certificates zstd python3 procps-ng iproute util-linux shadow-utils tar gzip
  command -v curl >/dev/null || dnf install -y curl
fi
python3 -c 'import sys; assert sys.version_info >= (3,9), "Python 3.9+ is required"'
if [[ "$MANAGED" -eq 0 ]]; then
  for PORT in 8080 11434; do
    if ss -H -ltn "( sport = :$PORT )" | grep -q .; then fail "Port $PORT is already in use."; fi
  done
else
  mkdir -p /var/backups
  BACKUP_DIR=$(mktemp -d /var/backups/cpu-ai-XXXXXXXX)
  for FILE in config.env chat.py index.html login.html benchmark.py version; do
    [[ ! -f "$APP/$FILE" ]] || cp -p "$APP/$FILE" "$BACKUP_DIR/"
  done
  echo "Previous app files backed up to $BACKUP_DIR"
  systemctl stop cpu-ai-proxy.service 2>/dev/null || true
fi
mkdir -p "$APP"
touch "$APP/.managed"
if ! command -v ollama >/dev/null; then
  TMP=$(mktemp -d)
  trap 'rm -rf -- "${TMP:?}"' EXIT
  echo "Downloading pinned Ollama $OLLAMA_PIN ($ARCH), then verifying SHA-256..."
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 1800 \
    "https://github.com/ollama/ollama/releases/download/v${OLLAMA_PIN}/ollama-linux-${ARCH}.tar.zst" \
    -o "$TMP/ollama.tar.zst"
  printf '%s  %s\n' "$DIGEST" "$TMP/ollama.tar.zst" | sha256sum -c -
  tar --zstd -xf "$TMP/ollama.tar.zst" -C /usr/local
fi
OLLAMA_BIN=$(command -v ollama)
if ! "$OLLAMA_BIN" --version 2>&1 | grep -F "$OLLAMA_PIN" >/dev/null; then
  fail "Ollama version differs from tested $OLLAMA_PIN. No automatic upgrade was performed."
fi
id ollama >/dev/null 2>&1 || useradd --system --user-group --create-home --home-dir /usr/share/ollama --shell /usr/sbin/nologin ollama
install -d -o ollama -g ollama -m 750 /usr/share/ollama
id cpu-ai >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin cpu-ai
cat > /etc/systemd/system/ollama.service <<EOF
[Unit]
Description=CPU AI Lab - Ollama
After=network-online.target
Wants=network-online.target
[Service]
User=ollama
Group=ollama
ExecStart=$OLLAMA_BIN serve
Environment="HOME=/usr/share/ollama"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_CONTEXT_LENGTH=4096"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="CUDA_VISIBLE_DEVICES=-1"
Environment="ROCR_VISIBLE_DEVICES=-1"
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
MemoryMax=75%
[Install]
WantedBy=multi-user.target
EOF
printf 'CPU_AI_MODEL=%s\nCPU_AI_THREADS=%s\nCPU_AI_CONTEXT=4096\nCPU_AI_WEB_PORT=8080\n' "$MODEL" "$(nproc)" > "$APP/config.env"
printf '%s\n' "$APP_VERSION" > "$APP/version"


cat > "$APP/chat.py" <<'CPU_AI_PYTHON'

#!/usr/bin/env python3
"""CPU AI Lab 0.3: bounded, loopback-only streaming chat."""
import hashlib
import hmac
import secrets
from collections import deque
from http.cookies import SimpleCookie
import json
import math
import os
import threading
import time
import urllib.request
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = '0.3.2'
MODEL = os.environ.get('CPU_AI_MODEL', 'qwen2.5:1.5b')
THREADS = max(1, int(os.environ.get('CPU_AI_THREADS', '2')))
CONTEXT = max(2048, min(8192, int(os.environ.get('CPU_AI_CONTEXT', '4096'))))
LOCK = threading.Lock()
PORT = int(os.environ.get('CPU_AI_WEB_PORT', '5555'))
PUBLIC_HOST = os.environ.get('CPU_AI_PUBLIC_HOST', '')
ALLOWED_HOSTS = (f'127.0.0.1:{PORT}', f'localhost:{PORT}') + ((PUBLIC_HOST,) if PUBLIC_HOST else ())
AUTH_PATH = os.environ.get('CPU_AI_AUTH_FILE', '')
AUTH = json.loads(Path(AUTH_PATH).read_text()) if AUTH_PATH else None
SESSIONS = {}
LOGIN_FAILURES = deque(maxlen=8)
AUTH_LOCK = threading.Lock()
LOGIN_PAGE = Path(__file__).with_name('login.html').read_bytes()
PAGE = Path(__file__).with_name('index.html').read_bytes()

# A conservative estimate, not a tokenizer. Always disclose when history is trimmed.
def estimate(messages):
    total = 0
    for message in messages:
        content = message['content']
        ascii_count = sum(ord(c) < 128 for c in content)
        total += math.ceil(ascii_count / 2.5 + (len(content)-ascii_count)*1.5) + 24
    return total

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, status, body, content_type='application/json; charset=utf-8'):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(body)

    def discard_body(self):
        try:
            size = int(self.headers.get('Content-Length','0'))
            if 0 < size <= 160000:
                self.connection.settimeout(2)
                self.rfile.read(size)
        except (ValueError,TimeoutError,OSError):
            pass

    def reject(self, status, body):
        self.discard_body()
        return self.send(status, body)

    def valid_host(self):
        return self.headers.get('Host', '') in ALLOWED_HOSTS

    def origin_ok(self):
        origin = self.headers.get('Origin')
        if origin is None:
            return True
        allowed = {f'http://127.0.0.1:{PORT}', f'http://localhost:{PORT}'}
        if PUBLIC_HOST:
            allowed.add('https://' + PUBLIC_HOST)
        return origin in allowed

    def session(self):
        if AUTH is None:
            return True
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get('Cookie', ''))
            token = cookie['cpu_ai_session'].value
        except Exception:
            return False
        now = time.monotonic()
        with AUTH_LOCK:
            for key in list(SESSIONS):
                if SESSIONS[key] <= now:
                    del SESSIONS[key]
            return token if token in SESSIONS else False

    def login(self):
        if AUTH is None:
            return self.send(404, {'error':'Login is not enabled'})
        now = time.monotonic()
        with AUTH_LOCK:
            while LOGIN_FAILURES and now - LOGIN_FAILURES[0] > 60:
                LOGIN_FAILURES.popleft()
            if len(LOGIN_FAILURES) >= 8:
                return self.reject(429, {'error':'تلاش‌های ناموفق زیاد است؛ یک دقیقه بعد دوباره تلاش کنید.'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                raise ValueError()
            self.connection.settimeout(15)
            body = json.loads(self.rfile.read(size))
            username, password = body['username'], body['password']
            if not isinstance(username,str) or not isinstance(password,str) or len(password)>1024:
                raise ValueError()
            calculated = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(AUTH['salt']),310000).hex()
            valid = hmac.compare_digest(username.encode(), AUTH['username'].encode()) and hmac.compare_digest(calculated,AUTH['password_hash'])
        except (ValueError,KeyError,TypeError,TimeoutError):
            return self.send(400, {'error':'درخواست نامعتبر است.'})
        if not valid:
            with AUTH_LOCK:
                LOGIN_FAILURES.append(now)
            return self.send(401, {'error':'نام کاربری یا رمز ورود درست نیست.'})
        token = secrets.token_urlsafe(32)
        with AUTH_LOCK:
            if len(SESSIONS) >= 32:
                SESSIONS.pop(next(iter(SESSIONS)))
            SESSIONS[token] = now+28800
            LOGIN_FAILURES.clear()
        secure = '; Secure' if self.headers.get('X-Forwarded-Proto') == 'https' else ''
        self.send_response(200)
        self.send_header('Set-Cookie','cpu_ai_session='+token+'; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800'+secure)
        self.send_header('Cache-Control','no-store')
        self.send_header('Content-Length','2')
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(b'{}')

    def do_GET(self):
        if not self.valid_host():
            return self.send(403, {'error': 'Invalid host'})
        if self.path == '/':
            return self.send(200, PAGE if self.session() else LOGIN_PAGE, 'text/html; charset=utf-8')
        if self.path == '/config':
            if not self.session():
                return self.send(401, {'error':'لطفاً وارد شوید.'})
            return self.send(200, {'model': MODEL, 'version': VERSION, 'cpu_only': True,
                       'context': CONTEXT, 'output_choices': [512, 1024, 2048], 'default_output': 1024, 'auth_enabled': AUTH is not None})
        if self.path == '/health':
            try:
                with urllib.request.urlopen('http://127.0.0.1:11434/api/tags', timeout=5) as response:
                    models = json.load(response).get('models', [])
                if MODEL not in [model['name'] for model in models]:
                    raise RuntimeError('Missing model')
                return self.send(200, {'status': 'ready', 'model': MODEL, 'version': VERSION, 'busy': LOCK.locked()})
            except Exception:
                return self.send(503, {'error': 'Model unavailable', 'version': VERSION})
        return self.send(404, {'error': 'Not found'})

    def do_POST(self):
        if not self.valid_host():
            return self.reject(403, {'error': 'Invalid host'})
        if not self.origin_ok():
            return self.reject(403, {'error': 'Cross-origin request rejected'})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.reject(415, {'error': 'JSON required'})
        if self.path == '/login':
            return self.login()
        if not self.session():
            return self.reject(401, {'error':'نشست ورود تمام شده است. صفحه را دوباره باز کنید.'})
        if self.path == '/logout':
            self.discard_body()
            token = self.session()
            with AUTH_LOCK:
                SESSIONS.pop(token, None)
            self.send_response(200)
            self.send_header('Set-Cookie','cpu_ai_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
            self.send_header('Content-Length','2')
            self.end_headers()
            self.wfile.write(b'{}')
            return
        if self.path != '/chat':
            return self.reject(404, {'error':'Not found'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 160000:
                return self.send(413, {'error': 'متن درخواست بیش از حد طولانی است.'})
            self.connection.settimeout(20)
            body = json.loads(self.rfile.read(size))
            messages = body['messages']
            output = body.get('max_tokens', 1024)
            mode = body.get('mode', 'general')
            continuing = body.get('continuing', False)
            if type(continuing) is not bool:
                raise ValueError()
            if type(output) is not int or output not in (512, 1024, 2048) or mode not in ('general', 'code'):
                raise ValueError()
            if not isinstance(messages, list) or not 1 <= len(messages) <= 12:
                raise ValueError()
            for message in messages:
                if not isinstance(message, dict) or message['role'] not in ('user', 'assistant'):
                    raise ValueError()
                if not isinstance(message['content'], str) or not 0 < len(message['content']) <= 24000:
                    raise ValueError()
            if messages[-1]['role'] != 'user':
                raise ValueError()
            system = 'Answer directly and accurately. If unsure, say so. Follow the requested language and length. Avoid repetition.'
            if mode == 'code':
                system += ' For code requests, give complete runnable code in fenced code blocks. Keep explanation short. Do not use filler. Never claim code was tested.'
            fitted = [dict(role=m['role'], content=m['content']) for m in messages]
            trimmed = 0
            budget = CONTEXT - output - 256
            while len(fitted) > (3 if continuing else 2) and estimate(fitted) + estimate([{'role':'system','content':system}]) > budget:
                fitted.pop(0)
                trimmed += 1
                if fitted and fitted[0]['role'] == 'assistant':
                    fitted.pop(0)
                    trimmed += 1
            if estimate(fitted) + estimate([{'role':'system','content':system}]) > budget:
                return self.send(400, {'error': 'متن برای طول پاسخ انتخاب‌شده زیاد است. پاسخ کوتاه‌تر انتخاب کنید یا گفت‌وگوی جدید بسازید.'})
        except (ValueError, KeyError, TypeError, TimeoutError):
            return self.send(400, {'error': 'درخواست نامعتبر است.'})
        if not LOCK.acquire(blocking=False):
            return self.send(429, {'error': 'مدل مشغول است؛ کمی بعد دوباره تلاش کنید.'})
        streaming = False
        start = time.monotonic()
        first = None
        try:
            payload = {'model': MODEL, 'messages': [{'role': 'system', 'content': system}] + fitted,
                       'stream': True, 'keep_alive': '5m', 'options': {'num_gpu': 0,
                       'num_thread': THREADS, 'num_ctx': CONTEXT, 'num_batch': 128,
                       'num_predict': output, 'temperature': 0.1 if mode == 'code' else 0.2}}
            if MODEL.startswith('qwen3'):
                payload['think'] = False
            request = urllib.request.Request('http://127.0.0.1:11434/api/chat', json.dumps(payload).encode(),
                                             {'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=1200) as response:
                self.send_response(200)
                self.send_header('Content-Type', 'application/x-ndjson; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                streaming = True
                completed = False
                for line in response:
                    data = json.loads(line)
                    if 'error' in data:
                        raise RuntimeError(data['error'])
                    token = data.get('message', {}).get('content', '')
                    if token and first is None:
                        first = time.monotonic() - start
                    event = {'token': token}
                    if data.get('done'):
                        completed = True
                        duration = data.get('eval_duration', 0)/1e9
                        event.update(done=True, tokens=data.get('eval_count', 0),
                            tokens_per_second=data.get('eval_count', 0)/duration if duration else 0,
                            truncated=(data.get('done_reason') == 'length' or
                                       (not data.get('done_reason') and data.get('eval_count', 0) >= output)),
                            done_reason=data.get('done_reason', 'stop'), context_trimmed=trimmed,
                            ttft_seconds=round(first, 2) if first is not None else None,
                            wall_seconds=round(time.monotonic()-start, 2), max_tokens=output)
                    self.wfile.write((json.dumps(event, ensure_ascii=False)+'\n').encode())
                    self.wfile.flush()
                if not completed:
                    raise RuntimeError('Incomplete upstream stream')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            error = {'error': 'ارتباط با مدل قطع شد یا زمان پردازش تمام شد. متن دریافت‌شده حفظ شده است؛ می‌توانید دوباره تلاش کنید.'}
            try:
                if streaming:
                    self.wfile.write((json.dumps(error, ensure_ascii=False)+'\n').encode())
                    self.wfile.flush()
                else:
                    self.send(502, error)
            except OSError:
                pass
        finally:
            LOCK.release()

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()


CPU_AI_PYTHON


cat > "$APP/index.html" <<'CPU_AI_PYTHON'

<!doctype html>
<html lang="fa" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>CPU AI Lab · چت شخصی</title>
<style>
:root{color-scheme:dark;--bg:#0c1220;--panel:#121d30;--line:#25334b;--muted:#a4b1c8;--green:#7ee4be;--text:#eef3fc}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.9 Tahoma,Arial,sans-serif}button,textarea,select{font:inherit}button{cursor:pointer}button:disabled{opacity:.45;cursor:default}button:focus-visible,select:focus-visible,textarea:focus{outline:2px solid var(--green);outline-offset:2px}main{max-width:980px;margin:auto;padding:26px 22px 40px}header{display:flex;justify-content:space-between;gap:16px;align-items:center;padding-bottom:22px;border-bottom:1px solid var(--line)}h1{margin:0;font-size:24px}small,.muted{color:var(--muted)}.brand{color:var(--green);font:bold 11px Arial;letter-spacing:2px}.pill{font-size:12px;border:1px solid var(--line);border-radius:30px;padding:4px 12px;white-space:nowrap}.online{color:var(--green)}.offline{color:#f7b9b9}.toolbar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:18px 0}.toolbar .model{margin-left:auto;font:12px/1.8 Consolas,monospace;color:var(--muted);direction:ltr}.ghost{background:transparent;color:var(--muted);border:1px solid var(--line);border-radius:9px;padding:5px 12px}.welcome{text-align:center;padding:40px 0 26px}.welcome h2{font-size:25px;margin:8px 0}.welcome p{color:var(--muted);margin:0}.examples{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:24px 0}.example{background:var(--panel);border:1px solid var(--line);color:var(--text);border-radius:12px;text-align:right;padding:15px;font-size:13px}.example span{display:block;color:var(--green);font-size:12px;margin-bottom:5px}#chat{min-height:80px}.message{margin:18px 0;border:1px solid var(--line);border-radius:14px;background:var(--panel);overflow:hidden}.message.user{background:#153137;border-color:#27444a;margin-right:10%}.message-head{display:flex;align-items:center;justify-content:space-between;padding:10px 16px;border-bottom:1px solid #ffffff08;color:var(--muted);font-size:12px}.message.user .message-head{color:#b1ded3}.content{padding:15px 18px;overflow-wrap:anywhere}.prose{white-space:pre-wrap;unicode-bidi:plaintext}.code{margin:12px 0;background:#080e19;border:1px solid #2c3d59;border-radius:10px;overflow:hidden;direction:ltr;text-align:left}.code-head{padding:7px 12px;display:flex;justify-content:space-between;border-bottom:1px solid #26344b;color:#9bb4d8;font:12px Consolas,monospace}.copy{background:none;border:0;color:var(--green);font:12px Tahoma;cursor:pointer}.code pre{margin:0;padding:16px;overflow:auto;tab-size:2;white-space:pre;font:13px/1.8 Consolas,'Courier New',monospace}.message-foot{padding:0 18px 12px;color:var(--muted);font-size:11px}.metrics{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0 0}.metric{background:#0c1627;border:1px solid var(--line);border-radius:8px;padding:4px 10px}.metric strong{color:var(--green);font-size:13px}.notice{border:1px solid #80632f;background:#2a2317;color:#f4d491;border-radius:10px;padding:10px 14px;margin:12px 0;font-size:13px}.error{color:#ffc1c1}.composer{margin-top:22px;background:var(--panel);border:1px solid var(--line);border-radius:15px;padding:16px}.options{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:12px;font-size:12px;color:var(--muted)}select{background:#0c1627;color:var(--text);border:1px solid var(--line);padding:4px 8px;border-radius:7px;font-size:12px;margin-right:6px}textarea{width:100%;min-height:100px;max-height:320px;resize:vertical;background:transparent;border:0;color:var(--text);padding:8px;line-height:1.9}textarea:focus{outline-offset:0;border-radius:6px}.actions{display:flex;align-items:center;gap:8px;margin-top:10px}.primary{background:var(--green);color:#07271e;border:0;border-radius:9px;padding:8px 23px;font-weight:bold}.stop{background:#492a35;border:1px solid #78404f;color:#ffd4dc;border-radius:9px;padding:8px 18px}.hint{color:var(--muted);font-size:11px;margin-right:auto}.status{font-size:12px;color:var(--muted);min-height:26px;margin-top:10px}footer{font-size:11px;color:#8796b0;text-align:center;margin-top:20px}#continue{display:block;margin:12px auto;color:var(--green)}[hidden]{display:none!important}@media(max-width:620px){main{padding:18px 14px}h1{font-size:20px}.examples{grid-template-columns:1fr}.welcome{padding-top:22px}.message.user{margin-right:4%}.hint{display:none}.toolbar .model{width:100%;order:3}.content{padding:12px}.code pre{font-size:12px}header{gap:8px}}
</style></head>
<body><main>
<header><div><div class="brand">CPU AI LAB / 03</div><h1>دستیار شخصی شما</h1><small>اجرا روی سرور خودتان · بدون GPU</small></div><span id="health" class="pill">در حال اتصال…</span></header>
<div class="toolbar"><button class="ghost" id="new">گفت‌وگوی جدید</button><button class="ghost" id="download">دریافت گفت‌وگو</button><button class="ghost" id="logout" hidden>خروج از حساب</button><span class="model" id="model">…</span></div>
<section id="welcome" class="welcome"><h2>از کجا شروع کنیم؟</h2><p>سؤال بپرسید، ایده بگیرید یا یک قطعه کد بسازید.</p>
<div class="examples"><button class="example" data-prompt="تفاوت RAM و فضای دیسک را کوتاه توضیح بده."><span>یادگیری</span>تفاوت RAM و دیسک چیست؟</button><button class="example" data-mode="code" data-prompt="Write a complete single-file HTML splash screen for a mobile app. Inline CSS, no external assets, centered app name, animated loading dots. Return only the complete HTML code."><span>ساختن</span>کد یک اسپلش اسکرین موبایل</button><button class="example" data-mode="code" data-prompt="Write a short Python function that checks if a string is a palindrome, with two usage examples."><span>برنامه‌نویسی</span>یک تابع Python با مثال</button></div></section>
<div id="chat" aria-live="polite"></div><div id="notice" class="notice" hidden></div>
<button class="ghost" id="continue" hidden>ادامه پاسخ ←</button>
<form id="form" class="composer"><div class="options"><label>نوع پاسخ<select id="mode"><option value="general">عمومی</option><option value="code">کدنویسی</option></select></label><label>طول پاسخ<select id="length"><option value="512">کوتاه · ۵۱۲ توکن</option><option value="1024" selected>معمولی · ۱۰۲۴ توکن</option><option value="2048">بلند · ۲۰۴۸ توکن</option></select></label></div>
<textarea id="prompt" aria-label="متن پیام" maxlength="12000" placeholder="پیام خود را بنویسید… برای کد، زبان و نتیجه مورد انتظار را مشخص کنید." required></textarea>
<div class="actions"><button class="primary" id="send">ارسال پیام</button><button type="button" class="stop" id="stop" hidden>توقف تولید</button><span class="hint">Ctrl + Enter برای ارسال</span></div><div id="status" class="status" role="status"></div></form>
<footer>مدل کوچک ممکن است اشتباه کند؛ کد را بررسی و آزمایش کنید. پاسخ بلند روی CPU زمان بیشتری می‌برد.<br>گفت‌وگو فقط در حافظه همین صفحه است؛ قبل از بستن، در صورت نیاز آن را دریافت کنید.</footer>
</main><script>
const $=id=>document.getElementById(id);let messages=[],busy=false,controller=null,lastView=null;
function notice(text){$('notice').textContent=text;$('notice').hidden=!text;}
async function copy(text,button){try{await navigator.clipboard.writeText(text);button.textContent='کپی شد';setTimeout(()=>button.textContent='کپی',1500);}catch{$('status').textContent='کپی خودکار در دسترس نیست؛ متن را انتخاب و کپی کنید.';}}
function render(target,text){target.replaceChildren();const pattern=/```([^\n`]*)\n([\s\S]*?)(```|$)/g;let offset=0,match;
function prose(value){if(!value)return;const p=document.createElement('div');p.className='prose';p.textContent=value;target.append(p);}
while((match=pattern.exec(text))!==null){prose(text.slice(offset,match.index));const code=document.createElement('div');code.className='code';const head=document.createElement('div');head.className='code-head';const lang=document.createElement('span');lang.textContent=match[1].trim()||'code';const button=document.createElement('button');button.type='button';button.className='copy';button.textContent='کپی';const source=match[2];button.onclick=()=>copy(source,button);head.append(lang,button);const pre=document.createElement('pre');const node=document.createElement('code');node.textContent=source;pre.append(node);code.append(head,pre);target.append(code);offset=pattern.lastIndex;}prose(text.slice(offset));}
function add(role,text){$('welcome').hidden=true;const box=document.createElement('article');box.className='message '+role;const head=document.createElement('div');head.className='message-head';const name=document.createElement('span');name.textContent=role==='user'?'شما':'دستیار';const button=document.createElement('button');button.type='button';button.className='copy';button.textContent='کپی';const body=document.createElement('div');body.className='content';const foot=document.createElement('div');foot.className='message-foot';const view={box,body,foot,text};button.onclick=()=>copy(view.text,button);head.append(name,button);box.append(head,body,foot);$('chat').append(box);render(body,text);return view;}
function showMetrics(view,stats){
view.foot.replaceChildren();const metrics=document.createElement('div');metrics.className='metrics';
for(const [label,value] of [['⏱ زمان کل',stats.wall_seconds.toFixed(1)+' ثانیه'],['⚡ سرعت تولید',stats.tokens_per_second.toFixed(1)+' توکن/ثانیه'],['📝 خروجی',stats.tokens+' توکن']]){const item=document.createElement('span');item.className='metric';item.append(document.createTextNode(label+': '));const strong=document.createElement('strong');strong.textContent=value;item.append(strong);metrics.append(item);}view.foot.append(metrics);const note=document.createElement('div');note.textContent='آمار همین مرحله از پاسخ · زمان کل شامل آماده‌سازی مدل است؛ سرعت مربوط به تولید متن است.';view.foot.append(note);
}
function setBusy(value){busy=value;for(const id of ['send','new','mode','length','continue','download','logout'])$(id).disabled=value;$('prompt').disabled=value;$('stop').hidden=!value;for(const button of document.querySelectorAll('[data-prompt]'))button.disabled=value;}
function continuationAvailable(){return messages.length&&messages[messages.length-1].role==='assistant';}
async function submit(continuing=false){if(busy)return;const prompt=$('prompt').value.trim();if(!continuing&&!prompt)return;if(continuing&&!continuationAvailable())return;
notice('');$('status').classList.remove('error');$('continue').hidden=true;setBusy(true);controller=new AbortController();let history,view,prefix='';
if(continuing){prefix=messages[messages.length-1].content;view=lastView;history=messages.concat([{role:'user',content:'Continue exactly where your last response stopped. Do not repeat previous text or restart the code. Finish the remaining code or explanation.'}]);}
else{add('user',prompt);history=messages.concat([{role:'user',content:prompt}]);view=add('assistant','');lastView=view;$('prompt').value='';}
let text='',done=false,stats=null,start=performance.now(),lastRender=0;
const timer=setInterval(()=>$('status').textContent=(text?'در حال دریافت پاسخ… ':'در حال آماده‌سازی مدل و پردازش… ')+Math.round((performance.now()-start)/1000)+' ثانیه',500);
function update(){view.text=prefix+text;render(view.body,view.text);}
try{const response=await fetch('/chat',{method:'POST',signal:controller.signal,headers:{'Content-Type':'application/json'},body:JSON.stringify({messages:history.slice(-12),mode:$('mode').value,max_tokens:Number($('length').value),continuing})});if(!response.ok){const data=await response.json();throw Error(data.error||'درخواست انجام نشد.');}
const reader=response.body.getReader(),decoder=new TextDecoder();let pending='';
function event(line){if(!line.trim())return;const data=JSON.parse(line);if(data.error)throw Error(data.error);if(data.token){text+=data.token;if(performance.now()-lastRender>140){update();lastRender=performance.now();}}if(data.done){done=true;stats=data;}}
while(true){const chunk=await reader.read();if(chunk.done){pending+=decoder.decode();if(pending.trim())event(pending);break;}pending+=decoder.decode(chunk.value,{stream:true});let split;while((split=pending.indexOf('\n'))>=0){const line=pending.slice(0,split);pending=pending.slice(split+1);event(line);}}
if(!done)throw Error('ارتباط قبل از پایان پاسخ قطع شد.');update();
if(continuing)messages[messages.length-1].content=view.text;else messages=history.concat([{role:'assistant',content:text}]);messages=messages.slice(-10);
showMetrics(view,stats);
$('status').textContent='پاسخ دریافت شد. '+(stats.ttft_seconds===null?'':'شروع پاسخ پس از '+stats.ttft_seconds+' ثانیه.');
$('continue').hidden=false;
if(stats.truncated){notice('⚠️ پاسخ به محدودیت '+stats.max_tokens+' توکن رسید و ممکن است متن یا کد ناقص باشد. برای دریافت بقیه، «ادامه پاسخ» را بزنید.');$('continue').hidden=false;}
else if((view.text.match(/```/g)||[]).length%2){notice('بخش کد بسته نشده و ممکن است ناقص باشد؛ می‌توانید ادامه پاسخ را درخواست کنید.');}
else if(stats.context_trimmed){notice('برای جا شدن در حافظه گفت‌وگو، بخشی از پیام‌های قدیمی از ورودی مدل کنار گذاشته شد.');}
}catch(error){update();if(text){if(continuing)messages[messages.length-1].content=view.text;else messages=history.concat([{role:'assistant',content:text}]);$('continue').hidden=false;}
$('status').textContent=error.name==='AbortError'?'تولید متوقف شد؛ متن دریافت‌شده حفظ شد.':error.message;$('status').classList.add('error');}
finally{clearInterval(timer);setBusy(false);controller=null;$('prompt').focus();}}
$('form').onsubmit=e=>{e.preventDefault();submit();};$('continue').onclick=()=>submit(true);$('stop').onclick=()=>controller?.abort();
$('prompt').onkeydown=e=>{if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)){e.preventDefault();submit();}};
$('new').onclick=()=>{messages=[];lastView=null;$('chat').replaceChildren();$('welcome').hidden=false;$('continue').hidden=true;notice('');$('status').textContent='';$('prompt').focus();};
for(const button of document.querySelectorAll('[data-prompt]'))button.onclick=()=>{$('prompt').value=button.dataset.prompt;$('mode').value=button.dataset.mode||'general';$('prompt').focus();};
$('download').onclick=()=>{if(!messages.length){$('status').textContent='هنوز گفت‌وگویی برای دریافت وجود ندارد.';return;}const text=messages.map(m=>(m.role==='user'?'شما':'دستیار')+'\n'+m.content).join('\n\n---\n\n');const url=URL.createObjectURL(new Blob([text],{type:'text/plain;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='cpu-ai-chat.txt';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
$('logout').onclick=async()=>{await fetch('/logout',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});location.reload();};
async function health(){try{const r=await fetch('/health');if(!r.ok)throw Error();$('health').textContent='● آماده';$('health').className='pill online';}catch{$('health').textContent='● سرویس در دسترس نیست';$('health').className='pill offline';}}
fetch('/config').then(r=>r.json()).then(c=>{$('model').textContent=c.model+' · v'+c.version;$('logout').hidden=!c.auth_enabled;}).catch(()=>$('model').textContent='اتصال را بررسی کنید');health();setInterval(health,30000);
</script></body></html>


CPU_AI_PYTHON


cat > "$APP/login.html" <<'CPU_AI_PYTHON'

<!doctype html><html lang="fa" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ورود · CPU AI Lab</title>
<style>:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0c1220;color:#eef3fc;font:15px/1.9 Tahoma,Arial}main{width:min(420px,92vw);background:#121d30;border:1px solid #25334b;border-radius:20px;padding:32px}.brand{color:#7ee4be;font:bold 11px Arial;letter-spacing:2px}h1{margin:12px 0 4px}p{color:#a4b1c8;font-size:13px}label{display:block;margin-top:16px}input{display:block;width:100%;background:#0c1627;color:#fff;border:1px solid #344660;border-radius:9px;padding:12px;font:inherit;direction:ltr;margin-top:6px}button{width:100%;background:#7ee4be;color:#07271e;border:0;border-radius:10px;padding:12px;font:inherit;font-weight:bold;margin-top:24px;cursor:pointer}button:disabled{opacity:.5}#error{min-height:26px;color:#ffbcbc;font-size:12px;margin-top:12px}small{display:block;color:#899ab6;font-size:11px;margin-top:16px}</style>
<main><div class="brand">CPU AI LAB / 03</div><h1>به دستیار خود وارد شوید</h1><p>مدل روی سرور شما اجرا می‌شود.</p><form id="login"><label>نام کاربری<input id="username" autocomplete="username" value="admin" required maxlength="100"></label><label>رمز ورود<input id="password" type="password" autocomplete="current-password" required maxlength="1024"></label><button id="submit">ورود به چت</button><div id="error" role="status"></div></form><small>اطلاعات ورود را مدیر سرور با فرمان cpu-ai --access دریافت می‌کند.</small></main>
<script>document.getElementById('login').onsubmit=async e=>{e.preventDefault();const button=document.getElementById('submit');button.disabled=true;document.getElementById('error').textContent='';try{const r=await fetch('/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:document.getElementById('username').value,password:document.getElementById('password').value})});const d=await r.json();if(!r.ok)throw Error(d.error||'ورود انجام نشد.');location.replace('/');}catch(err){document.getElementById('error').textContent=err.message;}finally{button.disabled=false;}};</script></html>


CPU_AI_PYTHON


cat > "$APP/benchmark.py" <<'CPU_AI_PYTHON'

#!/usr/bin/env python3
"""Repeatable streaming CPU benchmark. Writes responses and measured statistics."""
import argparse
import datetime
import json
import os
import platform
import subprocess
import threading
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--models", nargs="+", default=[os.environ.get("CPU_AI_MODEL", "qwen2.5:0.5b")])
parser.add_argument("--repeats", type=int, default=3)
parser.add_argument("--output", default="benchmark-results.json")
args = parser.parse_args()
if not 1 <= args.repeats <= 10:
    parser.error("repeats must be 1..10")
tests = [
    ("persian", "به فارسی و در سه جمله ساده توضیح بده تفاوت RAM و فضای دیسک چیست."),
    ("summary", "این متن را در یک جمله فارسی خلاصه کن: یک فروشگاه اینترنتی هر شب از پایگاه داده خود نسخه پشتیبان تهیه می‌کند. نسخه‌ها روی سرور دیگری نگهداری می‌شوند. مدیر فروشگاه هر هفته بازیابی نسخه پشتیبان را آزمایش می‌کند تا از سالم بودن اطلاعات مطمئن شود."),
    ("bash", "Write a short Bash script that prints a warning if root filesystem disk usage exceeds 80 percent. Do not delete or modify any files."),
]
def memory():
    with open("/proc/meminfo") as f:
        return {k: int(v.split()[0]) for k, v in (line.split(":", 1) for line in f)}

def post(path, payload):
    if payload.get("model", "").startswith("qwen3"):
        payload["think"] = False
    return urllib.request.urlopen(urllib.request.Request(
        "http://127.0.0.1:11434/api"+path, json.dumps(payload).encode(),
        {"Content-Type": "application/json"}), timeout=300)

report = {"timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "platform": platform.platform(), "cpu_count": os.cpu_count(),
          "memory_total_mib": memory()["MemTotal"]/1024,
          "ollama_version": subprocess.check_output(["ollama", "--version"], text=True).strip(),
          "settings": {"num_gpu": 0, "num_ctx": 2048, "num_predict": 128,
                       "num_thread": os.cpu_count(), "temperature": 0, "seed": 42},
          "note": "Memory is whole-system MemAvailable sampled every 100ms; not isolated model RSS. First run per model is cold; later runs are warm. TTFT includes prompt processing.",
          "results": []}
for model in args.models:
    with urllib.request.urlopen("http://127.0.0.1:11434/api/ps", timeout=10) as response:
        for loaded in json.load(response).get("models", []):
            with post("/generate", {"model": loaded["name"], "keep_alive": 0}) as result:
                result.read()
    for repeat in range(args.repeats):
        for name, prompt in tests:
            baseline = memory()["MemAvailable"]
            samples = [baseline]
            stop = threading.Event()
            def sample():
                while not stop.wait(0.1):
                    samples.append(memory()["MemAvailable"])
            sampler = threading.Thread(target=sample, daemon=True)
            sampler.start()
            start = time.perf_counter()
            first = None
            text = ""
            final = {}
            try:
                with post("/generate", {"model": model, "prompt": prompt, "stream": True,
                           "keep_alive": "2m", "options": report["settings"]}) as response:
                    for line in response:
                        event = json.loads(line)
                        if "error" in event:
                            raise RuntimeError(event["error"])
                        if event.get("response"):
                            if first is None:
                                first = time.perf_counter()-start
                            text += event["response"]
                        if event.get("done"):
                            final = event
                if not final:
                    raise RuntimeError("Missing completion event")
            except Exception as exc:
                report.setdefault("errors", []).append({
                    "model": model, "test": name, "repeat": repeat+1,
                    "error": str(exc), "wall_seconds": round(time.perf_counter()-start, 3),
                    "minimum_system_available_mib": round(min(samples)/1024, 1)})
                with open(args.output, "w", encoding="utf-8") as f:
                    json.dump(report, f, ensure_ascii=False, indent=2)
                raise
            finally:
                stop.set()
                sampler.join()
            elapsed = time.perf_counter()-start
            duration = final.get("eval_duration", 0)/1e9
            with urllib.request.urlopen("http://127.0.0.1:11434/api/ps", timeout=10) as response:
                running = json.load(response)
            row = {"model": model, "test": name, "repeat": repeat+1,
                   "cold": repeat == 0 and name == "persian",
                   "thinking_disabled": model.startswith("qwen3"),
                   "wall_seconds": round(elapsed, 3), "ttft_seconds": round(first, 3) if first is not None else None,
                   "tokens": final.get("eval_count", 0), "done_reason": final.get("done_reason"),
                   "tokens_per_second": round(final.get("eval_count", 0)/duration, 2) if duration else 0,
                   "load_seconds": round(final.get("load_duration", 0)/1e9, 3),
                   "minimum_system_available_mib": round(min(samples)/1024, 1),
                   "system_available_drop_mib": round((baseline-min(samples))/1024, 1),
                   "response": text, "loaded_models": running}
            report["results"].append(row)
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(report, f, ensure_ascii=False, indent=2)
            print(json.dumps({k:v for k,v in row.items() if k not in ("response", "loaded_models")}), flush=True)


CPU_AI_PYTHON

chmod 644 "$APP/chat.py" "$APP/index.html" "$APP/login.html" "$APP/benchmark.py" "$APP/config.env" "$APP/version"
cat > /etc/systemd/system/cpu-ai-web.service <<'EOF'
[Unit]
Description=CPU AI Lab - Lightweight Chat
After=network-online.target ollama.service
Wants=ollama.service
[Service]
User=cpu-ai
Group=cpu-ai
EnvironmentFile=/opt/cpu-ai/config.env
ExecStart=/usr/bin/python3 /opt/cpu-ai/chat.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
MemoryMax=128M
TasksMax=32
[Install]
WantedBy=multi-user.target
EOF
cat > /usr/local/bin/cpu-ai-benchmark <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
set -a
source /opt/cpu-ai/config.env
set +a
exec python3 /opt/cpu-ai/benchmark.py "$@"
EOF
chmod 755 /usr/local/bin/cpu-ai-benchmark
systemctl daemon-reload
systemctl enable ollama.service cpu-ai-web.service
systemctl restart ollama.service
READY=0
for _ in $(seq 1 60); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:11434/api/version >/dev/null; then READY=1; break; fi
  sleep 1
done
[[ "$READY" -eq 1 ]] || fail "Ollama did not start. Run: journalctl -u ollama -n 80"
echo "📥 Downloading $MODEL (already downloaded layers are reused)..."
"$OLLAMA_BIN" pull "$MODEL"
echo "🧪 Running a real CPU inference check..."
CPU_AI_MODEL="$MODEL" CPU_AI_THREADS="$(nproc)" python3 - <<'PY'
import json, os, urllib.request
data = {"model": os.environ["CPU_AI_MODEL"], "prompt": "Reply with the word READY.",
        "stream": False, "keep_alive": 0, "options": {"num_gpu": 0, "num_ctx": 4096, "num_batch": 128,
        "num_thread": int(os.environ["CPU_AI_THREADS"]), "num_predict": 16, "temperature": 0}}
request = urllib.request.Request("http://127.0.0.1:11434/api/generate",
          json.dumps(data).encode(), {"Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=300) as response:
    result = json.load(response)
assert result.get("done") and result.get("response", "").strip(), result
print("Inference check passed:", result["response"].strip())
PY
systemctl restart cpu-ai-web.service
READY=0
for _ in $(seq 1 30); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:8080/health >/dev/null; then READY=1; break; fi
  sleep 1
done
[[ "$READY" -eq 1 ]] || fail "Chat health check failed. Run: journalctl -u cpu-ai-web -n 80"
echo
echo "✅ Installation and real inference test completed."
if [[ "$SCRIPT_PATH" != /usr/local/bin/cpu-ai ]]; then
  install -m 755 "$SCRIPT_PATH" /usr/local/bin/cpu-ai
fi
configure_access "$SAVED_ACCESS_MODE"
show_install_summary
}

# Network profiles. The model API always stays on loopback.
access_info() {
  require_app
  if grep -q "^CPU_AI_ACCESS_MODE=public$" "$APP/config.env" && [[ -f /etc/cpu-ai/access.txt ]]; then cat /etc/cpu-ai/access.txt; else echo 'Local profile: http://localhost:5555 (no login)'; fi
}
show_install_summary() {
  printf '\n============================================================\n'
  printf '  ✅ CPU AI Lab v%s is ready!\n' "$APP_VERSION"
  if grep -q '^CPU_AI_ACCESS_MODE=public$' "$APP/config.env"; then
    local HOST
    HOST=$(sed -n 's/^CPU_AI_PUBLIC_HOST=//p' "$APP/config.env")
    printf '  🌐 Open chat: https://%s\n' "$HOST"
    printf '  🔐 Login: sudo cpu-ai --access\n'
    printf '     Credentials are private: /etc/cpu-ai/access.txt\n'
    printf '  🔓 Keep TCP 80 open for HTTPS renewal; chat uses TCP 5555.\n'
  else
    printf '  🌐 Open chat: http://localhost:5555\n'
    printf '  🏠 Local access only; no web login required.\n'
  fi
  printf '  🎛️  Management menu: sudo cpu-ai\n'
  printf '  📊 Service status: sudo cpu-ai --status\n'
  printf '============================================================\n\n'
}
configure_access() {
  local MODE="${1:-auto}"
  [[ "$MODE" != auto ]] || { if grep -qi microsoft /proc/sys/kernel/osrelease; then MODE=local; else MODE=public; fi; }
  [[ "$MODE" == local || "$MODE" == public ]] || fail 'Access mode must be local or public.'
  install -d -m 755 /etc/cpu-ai
  # Keep model/thread settings; replace only network settings.
  sed -i '/^CPU_AI_WEB_PORT=/d; /^CPU_AI_PUBLIC_HOST=/d; /^CPU_AI_AUTH_FILE=/d; /^CPU_AI_ACCESS_MODE=/d' "$APP/config.env"
  if [[ "$MODE" == local ]]; then
    systemctl disable --now cpu-ai-proxy.service 2>/dev/null || true
    if ss -H -ltn '( sport = :5555 )' | grep -q .; then
      local LOCAL_PID; LOCAL_PID=$(systemctl show cpu-ai-web -p MainPID --value)
      ss -H -ltnp '( sport = :5555 )' | grep -F "pid=$LOCAL_PID," >/dev/null || fail 'Port 5555 is used by another service.'
    fi
    printf 'CPU_AI_ACCESS_MODE=local\nCPU_AI_WEB_PORT=5555\n' >> "$APP/config.env"
    systemctl restart cpu-ai-web
    local LOCAL_READY=0
    for _ in $(seq 1 30); do
      if curl -fsS --max-time 3 http://127.0.0.1:5555/health >/dev/null; then LOCAL_READY=1; break; fi
      sleep 1
    done
    [[ "$LOCAL_READY" == 1 ]] || fail 'Local chat failed to start.'
    echo 'Local profile: http://localhost:5555'
    return
  fi
  local PUBLIC_ADDRESS="${PUBLIC_IP:-}"
  if [[ -z "$PUBLIC_ADDRESS" ]]; then
    PUBLIC_ADDRESS=$(ip -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -1)
    if ! python3 -c 'import ipaddress,sys; a=ipaddress.ip_address(sys.argv[1]); assert a.version==4 and a.is_global' "$PUBLIC_ADDRESS" 2>/dev/null; then
      PUBLIC_ADDRESS=$(curl -fsS --connect-timeout 5 --max-time 15 https://api.ipify.org)
    fi
  fi
  python3 -c 'import ipaddress,sys; a=ipaddress.ip_address(sys.argv[1]); assert a.version==4 and a.is_global, "A global public IPv4 is required"' "$PUBLIC_ADDRESS"
  local PROXY_WAS_ACTIVE=0
  systemctl is-active --quiet cpu-ai-proxy && PROXY_WAS_ACTIVE=1
  if [[ "$PROXY_WAS_ACTIVE" == 0 ]]; then
    for NET_PORT in 80 5555; do
      # The old local profile may own 5555; stop it only when switching profiles.
      if ss -H -ltn "( sport = :$NET_PORT )" | grep -q .; then
        if [[ "$NET_PORT" == 5555 ]] && systemctl is-active --quiet cpu-ai-web; then
          local OWNER_PID; OWNER_PID=$(systemctl show cpu-ai-web -p MainPID --value)
          ss -H -ltnp '( sport = :5555 )' | grep -F "pid=$OWNER_PID," >/dev/null || fail 'Port 5555 is used by another service.'
        else
          fail "Port $NET_PORT is in use. Public HTTPS needs ports 80 and 5555 free."
        fi
      fi
    done
  fi
  if ss -H -ltn '( sport = :8080 )' | grep -q .; then
    local BACKEND_PID; BACKEND_PID=$(systemctl show cpu-ai-web -p MainPID --value)
    ss -H -ltnp '( sport = :8080 )' | grep -F "pid=$BACKEND_PID," >/dev/null || fail 'Port 8080 is used by another service.'
  fi
  local CADDY_VERSION=2.11.7 CADDY_ARCH CADDY_SHA
  case "$(uname -m)" in
    x86_64) CADDY_ARCH=amd64; CADDY_SHA=727b91701a392de6ebc5027509f548bf39979e5216340d0faed8fa5e69c84f8b ;;
    aarch64) CADDY_ARCH=arm64; CADDY_SHA=d8fc6d179a5d283028a472a5618564f6ad8a86fed513e64f032b3b0b7cc45e42 ;;
    *) fail 'Unsupported architecture.' ;;
  esac
  mkdir -p /usr/local/lib/cpu-ai
  if [[ ! -x /usr/local/lib/cpu-ai/caddy ]]; then
    local CADDY_TMP; CADDY_TMP=$(mktemp -d)
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz" -o "$CADDY_TMP/caddy.tar.gz"
    printf '%s  %s\n' "$CADDY_SHA" "$CADDY_TMP/caddy.tar.gz" | sha256sum -c -
    tar -xzf "$CADDY_TMP/caddy.tar.gz" -C "$CADDY_TMP" caddy
    install -m 755 "$CADDY_TMP/caddy" /usr/local/lib/cpu-ai/caddy
    rm -rf -- "$CADDY_TMP"
  fi
  id cpu-ai-proxy >/dev/null 2>&1 || useradd --system --user-group --create-home --home-dir /var/lib/cpu-ai-proxy --shell /usr/sbin/nologin cpu-ai-proxy
  install -d -o cpu-ai-proxy -g cpu-ai-proxy -m 750 /var/lib/cpu-ai-proxy
  PUBLIC_ADDRESS="$PUBLIC_ADDRESS" python3 - <<'PY'
import hashlib,json,os,secrets
from pathlib import Path
folder=Path('/etc/cpu-ai'); auth=folder/'auth.json'; access=folder/'access.txt'
if not auth.exists() or not access.exists():
    password=secrets.token_urlsafe(18); salt=secrets.token_hex(16)
    auth.write_text(json.dumps({'username':'admin','salt':salt,'password_hash':hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),310000).hex()}))
    access.write_text('Username: admin\nPassword: '+password+'\n')
    access.chmod(0o600)
if access.exists():
    lines=[line for line in access.read_text().splitlines() if not line.startswith('URL:')]
    access.write_text('\n'.join(lines)+'\nURL: https://'+os.environ['PUBLIC_ADDRESS']+':5555\n')
    access.chmod(0o600)
PY
  chown root:cpu-ai /etc/cpu-ai/auth.json
  chmod 640 /etc/cpu-ai/auth.json
  printf 'CPU_AI_ACCESS_MODE=public\nCPU_AI_WEB_PORT=8080\nCPU_AI_PUBLIC_HOST=%s:5555\nCPU_AI_AUTH_FILE=/etc/cpu-ai/auth.json\n' "$PUBLIC_ADDRESS" >> "$APP/config.env"
  cat > /etc/cpu-ai/Caddyfile <<EOF
{
    admin off
    auto_https disable_redirects
    default_sni $PUBLIC_ADDRESS
}
https://$PUBLIC_ADDRESS:5555 {
    tls {
        issuer acme {
            dir https://acme-v02.api.letsencrypt.org/directory
            profile shortlived
            disable_tlsalpn_challenge
        }
    }
    reverse_proxy 127.0.0.1:8080 {
        flush_interval -1
    }
}
EOF
  /usr/local/lib/cpu-ai/caddy validate --config /etc/cpu-ai/Caddyfile --adapter caddyfile
  cat > /etc/systemd/system/cpu-ai-proxy.service <<'EOF'
[Unit]
Description=CPU AI Lab - Public HTTPS
After=network-online.target cpu-ai-web.service
Wants=network-online.target cpu-ai-web.service
[Service]
User=cpu-ai-proxy
Group=cpu-ai-proxy
Environment=XDG_DATA_HOME=/var/lib/cpu-ai-proxy/data
Environment=XDG_CONFIG_HOME=/var/lib/cpu-ai-proxy/config
ExecStart=/usr/local/lib/cpu-ai/caddy run --config /etc/cpu-ai/Caddyfile --adapter caddyfile
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/cpu-ai-proxy
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
MemoryMax=192M
[Install]
WantedBy=multi-user.target
EOF
  if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    ufw allow 80/tcp comment 'CPU AI Lab ACME'
    ufw allow 5555/tcp comment 'CPU AI Lab HTTPS'
  fi
  if systemctl is-active --quiet firewalld; then
    firewall-cmd --add-port=80/tcp --permanent; firewall-cmd --add-port=5555/tcp --permanent
    firewall-cmd --add-port=80/tcp; firewall-cmd --add-port=5555/tcp
  fi
  systemctl daemon-reload
  systemctl restart cpu-ai-web
  systemctl enable cpu-ai-proxy
  systemctl restart cpu-ai-proxy
  echo 'Waiting for a publicly trusted IP certificate; inbound port 80 is required...'
  local HTTPS_READY=0
  for _ in $(seq 1 40); do
    if curl --fail --silent --max-time 4 "https://$PUBLIC_ADDRESS:5555/health" >/dev/null; then HTTPS_READY=1; break; fi
    sleep 2
  done
  [[ "$HTTPS_READY" == 1 ]] || fail 'HTTPS is not ready. Check inbound 80/5555, cloud firewall and journalctl -u cpu-ai-proxy. No insecure HTTP fallback was enabled.'
  echo "Public chat: https://$PUBLIC_ADDRESS:5555"
  echo 'View your private login with: sudo cpu-ai --access'
}
update_from_github() {
  CPU_AI_UPDATE_TMP=$(mktemp -d)
  trap 'rm -rf -- "${CPU_AI_UPDATE_TMP:?}"' EXIT
  curl -fsSL --retry 2 --connect-timeout 15 --max-time 45 \
    https://api.github.com/repos/Mehdi682007/cpu-ai-lab/releases/latest -o "$CPU_AI_UPDATE_TMP/release.json"
  python3 - "$CPU_AI_UPDATE_TMP/release.json" > "$CPU_AI_UPDATE_TMP/urls" <<'PY'
import json,re,sys
release=json.load(open(sys.argv[1]))
tag=release['tag_name']
if not re.fullmatch(r'v\d+\.\d+\.\d+',tag):raise SystemExit('Unsupported release tag')
assets={a['name']:a['browser_download_url'] for a in release['assets']}
for name in ('install.sh','SHA256SUMS.txt'):
    url=assets[name]
    expected='https://github.com/Mehdi682007/cpu-ai-lab/releases/download/'+tag+'/'+name
    if url != expected:raise SystemExit('Unexpected release asset URL')
    print(url)
PY
  local INSTALL_URL CHECKSUM_URL
  INSTALL_URL=$(sed -n '1p' "$CPU_AI_UPDATE_TMP/urls"); CHECKSUM_URL=$(sed -n '2p' "$CPU_AI_UPDATE_TMP/urls")
  curl -fsSL --retry 2 --max-time 90 "$INSTALL_URL" -o "$CPU_AI_UPDATE_TMP/install.sh"
  curl -fsSL --retry 2 --max-time 45 "$CHECKSUM_URL" -o "$CPU_AI_UPDATE_TMP/SHA256SUMS.txt"
  python3 - "$CPU_AI_UPDATE_TMP" <<'PY'
import hashlib,re,sys
from pathlib import Path
folder=Path(sys.argv[1]);matches=[]
for line in (folder/'SHA256SUMS.txt').read_text().splitlines():
    parts=line.split()
    if len(parts)==2 and parts[1]=='install.sh' and re.fullmatch(r'[a-fA-F0-9]{64}',parts[0]):matches.append(parts[0].lower())
if len(matches)!=1 or hashlib.sha256((folder/'install.sh').read_bytes()).hexdigest()!=matches[0]:raise SystemExit('Installer SHA-256 check failed')
print('GitHub release installer checksum verified.')
PY
  bash "$CPU_AI_UPDATE_TMP/install.sh" --apply-update
}

is_installed() { [[ -f "$APP/.managed" && -f "$APP/chat.py" ]]; }
require_app() { is_installed || fail "CPU AI Lab is not installed. Choose Install first."; }
status_app() {
  echo "📊 CPU AI Lab - status"
  if is_installed; then
    echo "Installed version: $(cat "$APP/version" 2>/dev/null || echo legacy)"
    sed -n '/^CPU_AI_MODEL=/p; /^CPU_AI_THREADS=/p; /^CPU_AI_CONTEXT=/p' "$APP/config.env"
  else
    echo "App is not installed. Downloaded Ollama runtime/models may be retained."
  fi
  for SERVICE in ollama cpu-ai-web cpu-ai-proxy; do
    printf '%s: ' "$SERVICE"
    systemctl is-active "$SERVICE" 2>/dev/null || true
  done
  echo "RAM:"; free -h
  if grep -q '^CPU_AI_ACCESS_MODE=public$' "$APP/config.env" 2>/dev/null; then
    echo "URL: https://$(sed -n 's/^CPU_AI_PUBLIC_HOST=//p' "$APP/config.env")"
    echo 'View private login with: sudo cpu-ai --access'
  else echo 'URL: http://localhost:5555'; fi
}
restart_app() {
  require_app
  systemctl restart ollama cpu-ai-web
  if grep -q "^CPU_AI_ACCESS_MODE=public$" "$APP/config.env"; then systemctl restart cpu-ai-proxy; fi
  echo "✅ Services restarted. Check health with option 3."
}
uninstall_app() {
  [[ -f "$APP/.managed" && ! -L "$APP" ]] || fail "No managed installation found."
  if [[ "${1:-}" != --yes ]]; then
    echo "This removes CPU AI Lab's chat app and management command."
    echo "Ollama and downloaded models are kept for reinstall, and its service is stopped."
    read -r -p 'Type REMOVE to uninstall: ' CONFIRM
    [[ "$CONFIRM" == REMOVE ]] || { echo 'Cancelled.'; return 0; }
  fi
  exec 9>/run/cpu-ai-install.lock
  flock -n 9 || fail "Another management operation is running."
  systemctl disable --now cpu-ai-proxy.service 2>/dev/null || true
  systemctl disable --now cpu-ai-web.service 2>/dev/null || true
  if systemctl cat ollama.service 2>/dev/null | grep -F 'Description=CPU AI Lab - Ollama' >/dev/null; then
    systemctl disable --now ollama.service
  fi
  rm -f -- /etc/systemd/system/cpu-ai-web.service /etc/systemd/system/cpu-ai-proxy.service /usr/local/bin/cpu-ai-benchmark /usr/local/bin/cpu-ai
  for FILE in chat.py index.html login.html benchmark.py config.env version; do rm -f -- "$APP/$FILE"; done
  systemctl daemon-reload
  echo "✅ CPU AI Lab removed. Downloaded models/runtime and the ownership marker are retained."
  echo "Run your saved installer and choose Install to reinstall."
}
show_menu() {
  [[ -t 0 ]] || fail "Interactive terminal required. Use --install, --update, --status, --restart, --logs or --uninstall."
  while true; do
    show_banner
    printf '  --------------------------------------\n'
    printf '  1) 📦 Install\n  2) 🔄 Update from GitHub\n  3) 📊 Status & connection info\n  4) 🔁 Restart services\n  5) 🗑️  Uninstall (keep downloaded models)\n  6) 📋 Recent logs\n  7) 🌐 Public / local access profile\n  8) 🔐 Show private web login\n  0) 🚪 Exit\n\n'
    read -r -p '  👉 Choose an option: ' CHOICE || return 0
    case "$CHOICE" in
      1) ACTION=--install ;;
      2) ACTION=--update ;;
      3) ACTION=--status ;;
      4) ACTION=--restart ;;
      5) ACTION=--uninstall ;;
      6) ACTION=--logs ;;
      7)
        read -r -p '1) Public HTTPS :5555  2) Localhost :5555 : ' PROFILE_CHOICE
        case "$PROFILE_CHOICE" in 1) ACTION=--public ;; 2) ACTION=--local ;; *) continue ;; esac
        ;;
      8) ACTION=--access ;;
      0) return 0 ;;
      *) echo 'Choose 0 to 8.'; continue ;;
    esac
    if bash "$SCRIPT_PATH" "$ACTION"; then :; else echo '❌ Operation failed. Read the error above.'; fi
    read -r -p 'Press Enter to return to the menu...' _ || return 0
  done
}
case "${1:-menu}" in
  menu|--menu) show_menu ;;
  --install) install_app ;;
  --update) require_app; update_from_github ;;
  --apply-update|--repair) require_app; install_app ;;
  --access) access_info ;;
  --public|--local)
    require_app
    exec 9>/run/cpu-ai-install.lock; flock -n 9 || fail 'Another operation is running.'
    if [[ "$(cat "$APP/version" 2>/dev/null)" != "$APP_VERSION" ]]; then fail 'Update the app before changing its network profile.'; fi
    configure_access "${1#--}" ;;

  --status) status_app ;;
  --restart) restart_app ;;
  --logs) journalctl -u ollama -u cpu-ai-web -u cpu-ai-proxy -n 60 --no-pager ;;
  --uninstall) uninstall_app "${2:-}" ;;
  --help|-h) echo 'sudo bash install-cpu-ai.sh [--install|--update|--repair|--status|--restart|--logs|--public|--local|--access|--uninstall [--yes]]' ;;
  *) fail "Unknown option. Use --help." ;;
esac
