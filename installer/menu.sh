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
    if bash "$SCRIPT_PATH" "$ACTION"; then
      if [[ "$ACTION" == --update ]]; then
        echo '✅ Update completed. Reloading the current menu...'
        exec bash "$SCRIPT_PATH" --menu
      fi
    else echo '❌ Operation failed. Read the error above.'; fi
    read -r -p 'Press Enter to return to the menu...' _ || return 0
  done
}
case "${1:-menu}" in
  menu|--menu) show_menu ;;
  --install) install_app ;;
  --update) require_app; update_from_github ;;
  --apply-update) require_app; CPU_AI_APPLY_UPDATE=1; install_app ;;
  --repair) require_app; install_app ;;
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
