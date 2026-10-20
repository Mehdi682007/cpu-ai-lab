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
echo "Downloading $MODEL (already downloaded layers are reused)..."
"$OLLAMA_BIN" pull "$MODEL"
echo "Running a real CPU inference check..."
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
echo "Installation and real inference test completed."
if [[ "$SCRIPT_PATH" != /usr/local/bin/cpu-ai ]]; then
  install -m 755 "$SCRIPT_PATH" /usr/local/bin/cpu-ai
fi
configure_access "$SAVED_ACCESS_MODE"
echo "Open the management menu anytime: sudo cpu-ai"
}
