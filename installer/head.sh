#!/usr/bin/env bash
# CPU AI Lab 0.3.3 - menu-driven, CPU-only personal AI server.
# Download this file, inspect it, then run: sudo bash install-cpu-ai.sh
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 022
APP=/opt/cpu-ai
OLLAMA_PIN=0.40.6
fail() { printf '\n❌ ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "Run with sudo bash $0"
APP_VERSION=0.3.3
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")

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
