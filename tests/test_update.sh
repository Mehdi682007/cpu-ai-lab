#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
export CPU_AI_TEST_MARKER="$FIXTURE/applied"
export CPU_AI_TEST_CAPTURE="$FIXTURE/download-dir"
cat > "$FIXTURE/install.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --apply-update ]]
printf '%s' "$(dirname -- "$0")" > "$CPU_AI_TEST_CAPTURE"
touch "$CPU_AI_TEST_MARKER"
SH
(cd "$FIXTURE" && sha256sum install.sh > SHA256SUMS.txt)
cat > "$FIXTURE/release.json" <<'JSON'
{"tag_name":"v0.3.0","assets":[{"name":"install.sh","browser_download_url":"https://github.com/Mehdi682007/cpu-ai-lab/releases/download/v0.3.0/install.sh"},{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/Mehdi682007/cpu-ai-lab/releases/download/v0.3.0/SHA256SUMS.txt"}]}
JSON
export ROOT FIXTURE
cat > "$FIXTURE/run.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/installer/network.sh"
curl() {
  local OUTPUT='' URL=''
  while [[ $# -gt 0 ]]; do
    case "$1" in -o) OUTPUT=$2;shift 2 ;; --retry|--connect-timeout|--max-time) shift 2 ;; -*) shift ;; *) URL=$1;shift ;; esac
  done
  case "$URL" in
    */releases/latest) cp "$FIXTURE/release.json" "$OUTPUT" ;;
    */install.sh) cp "$FIXTURE/install.sh" "$OUTPUT" ;;
    */SHA256SUMS.txt) cp "$FIXTURE/SHA256SUMS.txt" "$OUTPUT" ;;
    *) return 1 ;;
  esac
}
update_from_github
SH
bash "$FIXTURE/run.sh"
[[ -f "$CPU_AI_TEST_MARKER" ]]
[[ ! -d "$(cat "$CPU_AI_TEST_CAPTURE")" ]]
echo 'PASS: verified release applies and temporary directory is removed after return'
rm "$CPU_AI_TEST_MARKER"
printf '%064d  install.sh\n' 0 > "$FIXTURE/SHA256SUMS.txt"
if bash "$FIXTURE/run.sh"; then echo 'Bad checksum unexpectedly accepted' >&2;exit 1;fi
[[ ! -f "$CPU_AI_TEST_MARKER" ]]
echo 'PASS: altered installer is rejected before execution'
