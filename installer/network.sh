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
sync_update_launcher() {
  # Recover the caller for upgrades from releases that did not pass its path.
  python3 - "$SCRIPT_PATH" "$PPID" "${CPU_AI_UPDATE_SOURCE:-}" <<'PY'
import os,re,stat,sys,tempfile
from pathlib import Path
source=Path(sys.argv[1]).resolve()
try:
    candidate=sys.argv[3]
    if not candidate:
        args=Path('/proc/'+sys.argv[2]+'/cmdline').read_bytes().split(b'\0')
        if len(args)<3 or Path(os.fsdecode(args[0])).name not in ('bash','bash.exe') or b'--update' not in args:
            raise ValueError('No Bash updater parent')
        candidate=os.fsdecode(args[1])
        if not os.path.isabs(candidate):
            candidate=os.path.join(os.readlink('/proc/'+sys.argv[2]+'/cwd'),candidate)
    target=Path(candidate).resolve(strict=True)
    if target==source or target==Path('/usr/local/bin/cpu-ai'):sys.exit(0)
    metadata=target.stat()
    if not stat.S_ISREG(metadata.st_mode):raise ValueError('Not a regular installer')
    content=target.read_text()
    if '# CPU AI Lab ' not in content or not re.search(r'^APP_VERSION=\d+\.\d+\.\d+$',content,re.M) or 'update_from_github()' not in content:
        raise ValueError('Not a CPU AI Lab launcher')
except (OSError,ValueError,UnicodeError):
    sys.exit(0) # Direct repair/install has no originating updater.
temporary=None
try:
    fd,temporary=tempfile.mkstemp(prefix='.cpu-ai-update-',dir=target.parent)
    with os.fdopen(fd,'wb') as stream:
        stream.write(source.read_bytes());stream.flush();os.fsync(stream.fileno())
    os.chmod(temporary,stat.S_IMODE(metadata.st_mode))
    os.chown(temporary,metadata.st_uid,metadata.st_gid)
    os.replace(temporary,target)
    print('✅ Downloaded launcher updated: '+str(target))
except OSError as error:
    print('⚠️ App updated, but the downloaded launcher could not be refreshed: '+str(error),file=sys.stderr)
    print('Open the current menu with: sudo cpu-ai',file=sys.stderr)
finally:
    if temporary and os.path.exists(temporary):os.unlink(temporary)
PY
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
  CPU_AI_UPDATE_SOURCE="$SCRIPT_PATH" bash "$CPU_AI_UPDATE_TMP/install.sh" --apply-update
}
