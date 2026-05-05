#!/bin/bash
set -Eeuo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="SSH 免密配置器（macOS）"
DEFAULT_REMOTE_USER="root"
DEFAULT_SSH_PORT="22"
SSH_CONNECT_TIMEOUT="10"
CONSOLE_BOOTSTRAP_REQUIRED="0"
TARGET_KEY_ALREADY_WORKS="0"

log() { printf '🔹 %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }
warn() { printf '⚠️  %s\n' "$*"; }

pause_and_exit() {
  local code="${1:-0}"
  echo
  read -r -p "按回车键关闭窗口..." _ || true
  exit "$code"
}

on_error() {
  local line="$1"
  err "执行失败（第 ${line} 行）。"
  if [[ -n "${DIAG_LOG:-}" ]]; then
    err "排查日志：$DIAG_LOG"
  fi
  pause_and_exit 1
}
trap 'on_error $LINENO' ERR

need_command() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少系统命令：$1"; pause_and_exit 1; }
}

need_command ssh
need_command ssh-keygen
need_command awk
need_command sed
need_command grep
need_command tee
need_command tr
need_command mktemp

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

trim_value() {
  printf '%s' "$1" | awk '{$1=$1; print}'
}

default_if_blank() {
  local value
  value="$(trim_value "$1")"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

sanitize_alias() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

prompt_inputs() {
  echo
  read -r -p "请输入服务器 IP 或域名: " SSH_HOST_INPUT
  SSH_HOST="$(trim_value "$SSH_HOST_INPUT")"
  [[ -n "$SSH_HOST" ]] || { err "服务器 IP 或域名不能为空。"; pause_and_exit 1; }

  read -r -p "请输入 SSH 用户名（默认 ${DEFAULT_REMOTE_USER}）: " SSH_USER_INPUT
  SSH_USER="$(default_if_blank "${SSH_USER_INPUT:-}" "$DEFAULT_REMOTE_USER")"
  [[ -n "$SSH_USER" ]] || { err "SSH 用户名不能为空。"; pause_and_exit 1; }

  read -r -p "请输入 SSH 端口（默认 ${DEFAULT_SSH_PORT}）: " SSH_PORT_INPUT
  SSH_PORT="$(default_if_blank "${SSH_PORT_INPUT:-}" "$DEFAULT_SSH_PORT")"
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 || "$SSH_PORT" -gt 65535 ]]; then
    err "SSH 端口必须是 1-65535 之间的数字。"
    pause_and_exit 1
  fi

  read -r -p "请输入本地备注名（例如 vultr-root）: " HOST_ALIAS_INPUT
  HOST_ALIAS_INPUT="$(trim_value "$HOST_ALIAS_INPUT")"
  [[ -n "$HOST_ALIAS_INPUT" ]] || { err "备注名不能为空。"; pause_and_exit 1; }

  HOST_ALIAS="$(sanitize_alias "$HOST_ALIAS_INPUT")"
  [[ -n "$HOST_ALIAS" ]] || { err "备注名清洗后为空，请换一个。"; pause_and_exit 1; }

  if [[ "$HOST_ALIAS" != "$HOST_ALIAS_INPUT" ]]; then
    warn "备注名已自动规范化为：$HOST_ALIAS"
  fi

  KEY_FILE="$HOME/.ssh/id_ed25519_${HOST_ALIAS}"
  CONFIG_FILE="$HOME/.ssh/config"
  MARK_BEGIN="# >>> ${HOST_ALIAS} managed block >>>"
  MARK_END="# <<< ${HOST_ALIAS} managed block <<<"
}

init_diagnostics() {
  DIAG_LOG="$HOME/.ssh/passwordless-setup-${HOST_ALIAS}-$(date '+%Y%m%d-%H%M%S').log"
  : > "$DIAG_LOG"
  chmod 600 "$DIAG_LOG"

  {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "diagnostic log created"
    printf 'script=%s\n' "$0"
    printf 'host=%s\n' "$SSH_HOST"
    printf 'user=%s\n' "$SSH_USER"
    printf 'port=%s\n' "$SSH_PORT"
    printf 'alias=%s\n' "$HOST_ALIAS"
    printf 'key_file=%s\n' "$KEY_FILE"
    printf 'ssh_path=%s\n' "$(command -v ssh)"
    if command -v ssh-copy-id >/dev/null 2>&1; then
      printf 'ssh_copy_id_path=%s\n' "$(command -v ssh-copy-id)"
    else
      printf 'ssh_copy_id_path=not found\n'
    fi
    ssh -V 2>&1 | sed 's/^/ssh_version=/'
  } >> "$DIAG_LOG"

  ok "排查日志：$DIAG_LOG"
}

diag() {
  if [[ -n "${DIAG_LOG:-}" ]]; then
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DIAG_LOG"
  fi
}

ensure_keypair() {
  if [[ -f "$KEY_FILE" && -f "$KEY_FILE.pub" ]]; then
    ok "检测到已有密钥，将复用：$KEY_FILE"
    diag "reuse existing key: $KEY_FILE"
    return
  fi

  log "正在生成新的 SSH 密钥：$KEY_FILE"
  diag "generating key: $KEY_FILE"
  ssh-keygen -t ed25519 -f "$KEY_FILE" -C "${USER}@$(hostname -s)-${HOST_ALIAS}" -N ""
  chmod 600 "$KEY_FILE"
  chmod 644 "$KEY_FILE.pub"
  ok "密钥生成完成"
  diag "key generated"
}

show_connectivity_tips() {
  warn "请优先检查："
  warn "1. 服务器 IP/域名和 SSH 端口是否正确。"
  warn "2. 云厂商防火墙、安全组是否放行 TCP ${SSH_PORT}。"
  warn "3. 服务器上的 sshd 是否正在运行，且没有只允许特定来源 IP。"
  warn "4. 如果服务商使用了自定义端口，请重新运行脚本并填写正确端口。"
}

mark_console_bootstrap_required() {
  CONSOLE_BOOTSTRAP_REQUIRED="1"
  diag "console bootstrap required: $*"
}

preflight_ssh_connectivity() {
  local probe_output
  local probe_status

  log "正在预检 SSH 连接：${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
  diag "probe ssh connectivity start"

  trap - ERR
  set +e
  probe_output="$(
    ssh -vvv \
      -p "$SSH_PORT" \
      -i "$KEY_FILE" \
      -o IdentitiesOnly=yes \
      -o BatchMode=yes \
      -o NumberOfPasswordPrompts=0 \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      -o ConnectionAttempts=1 \
      -o StrictHostKeyChecking=accept-new \
      -o ControlMaster=no \
      -o ControlPath=none \
      "${SSH_USER}@${SSH_HOST}" \
      "echo __SSH_PROBE__" 2>&1
  )"
  probe_status=$?
  set -e
  trap 'on_error $LINENO' ERR

  {
    printf '\n[%s] ssh preflight output (exit=%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$probe_status"
    printf '%s\n' "$probe_output"
  } >> "$DIAG_LOG"

  if grep -Eqi "Operation timed out|Connection timed out" <<< "$probe_output"; then
    err "SSH 连接超时：${SSH_HOST}:${SSH_PORT}"
    show_connectivity_tips
    warn "脚本将进入控制台接力模式：生成一条命令，用 VNC/服务商 Console 粘贴一次后继续。"
    mark_console_bootstrap_required "ssh connect timed out"
    return
  fi

  if grep -qi "Connection refused" <<< "$probe_output"; then
    err "服务器拒绝连接：${SSH_HOST}:${SSH_PORT}"
    show_connectivity_tips
    warn "脚本将进入控制台接力模式：生成一条命令，用 VNC/服务商 Console 粘贴一次后继续。"
    mark_console_bootstrap_required "ssh connection refused"
    return
  fi

  if grep -Eqi "Could not resolve hostname|Name or service not known|nodename nor servname provided" <<< "$probe_output"; then
    err "无法解析服务器地址：$SSH_HOST"
    err "详细日志：$DIAG_LOG"
    pause_and_exit 1
  fi

  if grep -qi "Host key verification failed" <<< "$probe_output"; then
    err "服务器主机指纹校验失败。可能是服务器重装过，或 known_hosts 中记录不一致。"
    warn "可以确认服务器可信后执行：ssh-keygen -R \"$SSH_HOST\""
    err "详细日志：$DIAG_LOG"
    pause_and_exit 1
  fi

  if grep -qx "__SSH_PROBE__" <<< "$probe_output"; then
    ok "SSH 连接预检通过（现有免密登录可能已经可用）。"
    diag "probe result: passwordless already works"
    TARGET_KEY_ALREADY_WORKS="1"
    return
  fi

  if grep -qi "Permission denied" <<< "$probe_output"; then
    if grep -Eqi "Authentications that can continue: publickey$|Authentications that can continue: publickey," <<< "$probe_output" \
      && ! grep -Eqi "Authentications that can continue: .*password|Authentications that can continue: .*keyboard-interactive" <<< "$probe_output"; then
      warn "服务器可达，但只允许公钥认证，不能通过密码自动安装公钥。"
      warn "脚本将进入控制台接力模式：生成一条命令，用 VNC/服务商 Console 粘贴一次后继续。"
      mark_console_bootstrap_required "password authentication unavailable"
      return
    fi

    ok "SSH 端口可达，接下来需要输入服务器密码安装公钥。"
    diag "probe result: reachable, authentication required"
    return
  fi

  warn "SSH 预检没有得到明确结果，将继续尝试安装公钥。"
  warn "如果后续仍卡住，请把日志发给排查人员：$DIAG_LOG"
  diag "probe result: unclear, continuing"
}

build_console_bootstrap_script() {
  local public_key

  public_key="$(cat "$KEY_FILE.pub")"

  cat <<BOOTSTRAP
set +H
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
echo $public_key | tee -a ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
ufw allow ${SSH_PORT}/tcp
firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
firewall-cmd --reload
iptables -I INPUT -p tcp --dport ${SSH_PORT} -j ACCEPT
systemctl reload ssh
systemctl reload sshd
echo __SSH_BOOTSTRAP_DONE__
BOOTSTRAP
}

console_bootstrap_flow() {
  local bootstrap_script

  bootstrap_script="$(build_console_bootstrap_script)"

  {
    printf '\n[%s] console bootstrap script\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' "$bootstrap_script"
  } >> "$DIAG_LOG"

  echo
  warn "当前无法直接用本地 SSH 把公钥安装到服务器。"
  warn "请打开服务商 VNC/Console，登录目标用户后粘贴下面这段多行脚本。"
  warn "它会写入当前公钥、尝试放行 TCP ${SSH_PORT}、重载 SSH 服务。"
  echo
  printf '%s\n' "$bootstrap_script"
  echo
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s\n' "$bootstrap_script" | pbcopy
    ok "这段脚本已复制到剪贴板。"
  fi
  read -r -p "看到服务器输出 __SSH_BOOTSTRAP_DONE__ 后，按回车继续验证..." _ || true

  log "正在重新检测 SSH 免密连接..."
  if verify_direct_key_login; then
    ok "控制台接力完成，免密 SSH 已可用。"
    CONSOLE_BOOTSTRAP_REQUIRED="0"
    TARGET_KEY_ALREADY_WORKS="1"
    return
  fi

  err "控制台接力后仍无法免密登录。"
  err "如果服务器端已输出 __SSH_BOOTSTRAP_DONE__，请继续检查服务商防火墙是否放行 TCP ${SSH_PORT}。"
  err "详细日志：$DIAG_LOG"
  pause_and_exit 1
}

install_public_key() {
  echo
  log "接下来会要求你输入服务器密码，用于安装公钥。"
  log "密码只会由本机 ssh 读取，不会写入脚本或配置文件。"
  echo

  if command -v ssh-copy-id >/dev/null 2>&1; then
    diag "running ssh-copy-id"
    if ssh-copy-id \
      -i "$KEY_FILE.pub" \
      -p "$SSH_PORT" \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      -o ConnectionAttempts=1 \
      -o ServerAliveInterval=10 \
      -o ServerAliveCountMax=2 \
      "${SSH_USER}@${SSH_HOST}" \
      > >(tee -a "$DIAG_LOG") \
      2> >(tee -a "$DIAG_LOG" >&2); then
      diag "ssh-copy-id completed"
      return
    fi

    err "ssh-copy-id 执行失败。"
    err "详细日志：$DIAG_LOG"
    pause_and_exit 1
  fi

  diag "ssh-copy-id not found, using manual authorized_keys installer"
  if cat "$KEY_FILE.pub" | ssh \
    -p "$SSH_PORT" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ConnectionAttempts=1 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=2 \
    "${SSH_USER}@${SSH_HOST}" '
      set -eu
      umask 077
      mkdir -p "$HOME/.ssh"
      touch "$HOME/.ssh/authorized_keys"
      chmod 700 "$HOME/.ssh"
      chmod 600 "$HOME/.ssh/authorized_keys"
      tmp="$(mktemp)"
      cat > "$tmp"
      grep -qxFf "$tmp" "$HOME/.ssh/authorized_keys" || cat "$tmp" >> "$HOME/.ssh/authorized_keys"
      rm -f "$tmp"
    ' > >(tee -a "$DIAG_LOG") \
      2> >(tee -a "$DIAG_LOG" >&2); then
    diag "manual authorized_keys installer completed"
    return
  fi

  err "手动安装公钥失败。"
  err "详细日志：$DIAG_LOG"
  pause_and_exit 1
}

write_config() {
  touch "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"

  local tmp_file
  tmp_file="$(mktemp)"

  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$CONFIG_FILE" > "$tmp_file"

  {
    cat "$tmp_file"
    [[ -s "$tmp_file" ]] && echo
    echo "$MARK_BEGIN"
    echo "Host $HOST_ALIAS"
    echo "  HostName $SSH_HOST"
    echo "  Port $SSH_PORT"
    echo "  User $SSH_USER"
    echo "  IdentityFile $KEY_FILE"
    echo "  IdentitiesOnly yes"
    echo "  PreferredAuthentications publickey"
    echo "$MARK_END"
  } > "$CONFIG_FILE"

  rm -f "$tmp_file"
  ok "已写入 ~/.ssh/config 别名：$HOST_ALIAS"
  diag "ssh config updated: $CONFIG_FILE"
}

verify_passwordless_login() {
  log "正在验证新免密 SSH..."
  diag "verify passwordless login start"
  verify_direct_key_login

  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ConnectionAttempts=1 \
    -o ControlMaster=no \
    -o ControlPath=none \
    "$HOST_ALIAS" \
    "echo __SSH_ALIAS_OK__"

  ok "免密 SSH 验证通过"
  diag "verify passwordless login completed"
}

verify_direct_key_login() {
  ssh \
    -i "$KEY_FILE" \
    -p "$SSH_PORT" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=accept-new \
    -o ControlMaster=no \
    -o ControlPath=none \
    "${SSH_USER}@${SSH_HOST}" \
    "echo __SSH_OK__"
}

main() {
  clear || true
  echo "========================================"
  echo "  $SCRIPT_NAME"
  echo "========================================"
  echo
  log "这个工具会自动完成：生成新密钥、上传公钥、写入 SSH 别名、验证免密登录。"
  log "适合第一次在新机器上配置 SSH。"

  ensure_ssh_dir
  prompt_inputs
  init_diagnostics
  ensure_keypair
  preflight_ssh_connectivity
  if [[ "$CONSOLE_BOOTSTRAP_REQUIRED" == "1" ]]; then
    console_bootstrap_flow
  elif [[ "$TARGET_KEY_ALREADY_WORKS" != "1" ]]; then
    install_public_key
  fi
  write_config
  verify_passwordless_login

  echo
  ok "配置完成。以后可以直接使用："
  echo "   ssh $HOST_ALIAS"
  echo
  ok "私钥位置：$KEY_FILE"
  pause_and_exit 0
}

main "$@"
