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
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
source "$ROOT/installer/network.sh"
sync_update_launcher
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
# CPU AI Lab updater test launcher
APP_VERSION=0.0.1
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
source "$ROOT/installer/network.sh"
# update_from_github() is provided by the sourced module.
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
cp "$FIXTURE/run.sh" "$FIXTURE/run-original.sh"
bash "$FIXTURE/run.sh"
[[ -f "$CPU_AI_TEST_MARKER" ]]
[[ ! -d "$(cat "$CPU_AI_TEST_CAPTURE")" ]]
cmp "$FIXTURE/run.sh" "$FIXTURE/install.sh"
echo 'PASS: verified release applies, downloaded launcher refreshes and temporary directory is removed'
# An old release invokes its downloaded updater without passing the source path.
cat > "$FIXTURE/legacy.sh" <<'SH'
#!/usr/bin/env bash
# CPU AI Lab legacy test launcher
APP_VERSION=0.0.1
update_from_github() { bash "$FIXTURE/install.sh" --apply-update; }
update_from_github
SH
chmod 750 "$FIXTURE/legacy.sh"
env -u CPU_AI_UPDATE_SOURCE bash "$FIXTURE/legacy.sh" --update
cmp "$FIXTURE/legacy.sh" "$FIXTURE/install.sh"
[[ "$(stat -c '%a' "$FIXTURE/legacy.sh")" == 750 ]]
echo 'PASS: upgrades from legacy launchers repair the original file and preserve permissions'
# A lookalike path without our installer signature must never be overwritten.
printf 'unrelated file\n' > "$FIXTURE/unrelated.sh"
CPU_AI_UPDATE_SOURCE="$FIXTURE/unrelated.sh" bash "$FIXTURE/install.sh" --apply-update
[[ "$(cat "$FIXTURE/unrelated.sh")" == 'unrelated file' ]]
echo 'PASS: unrelated files are not replaced'
# Restore the original wrapper for the rejection test.
cp "$FIXTURE/run-original.sh" "$FIXTURE/run.sh"
rm "$CPU_AI_TEST_MARKER"
printf '%064d  install.sh\n' 0 > "$FIXTURE/SHA256SUMS.txt"
if bash "$FIXTURE/run.sh"; then echo 'Bad checksum unexpectedly accepted' >&2;exit 1;fi
[[ ! -f "$CPU_AI_TEST_MARKER" ]]
echo 'PASS: altered installer is rejected before execution'
