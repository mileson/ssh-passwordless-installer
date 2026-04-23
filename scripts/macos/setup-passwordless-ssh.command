#!/bin/bash
set -Eeuo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="SSH 免密配置器（macOS）"
DEFAULT_REMOTE_USER="root"

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
need_command tr
need_command mktemp

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

trim_value() {
  printf '%s' "$1" | awk '{$1=$1; print}'
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
  SSH_USER="$(trim_value "${SSH_USER_INPUT:-$DEFAULT_REMOTE_USER}")"
  [[ -n "$SSH_USER" ]] || { err "SSH 用户名不能为空。"; pause_and_exit 1; }

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

ensure_keypair() {
  if [[ -f "$KEY_FILE" && -f "$KEY_FILE.pub" ]]; then
    ok "检测到已有密钥，将复用：$KEY_FILE"
    return
  fi

  log "正在生成新的 SSH 密钥：$KEY_FILE"
  ssh-keygen -t ed25519 -f "$KEY_FILE" -C "${USER}@$(hostname -s)-${HOST_ALIAS}" -N ""
  chmod 600 "$KEY_FILE"
  chmod 644 "$KEY_FILE.pub"
  ok "密钥生成完成"
}

install_public_key() {
  echo
  log "接下来会要求你输入服务器密码，用于安装公钥。"
  log "密码只会由本机 ssh 读取，不会写入脚本或配置文件。"
  echo

  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -i "$KEY_FILE.pub" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${SSH_HOST}"
    return
  fi

  cat "$KEY_FILE.pub" | ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${SSH_HOST}" '
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
  '
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
    echo "  User $SSH_USER"
    echo "  IdentityFile $KEY_FILE"
    echo "  IdentitiesOnly yes"
    echo "  PreferredAuthentications publickey"
    echo "$MARK_END"
  } > "$CONFIG_FILE"

  rm -f "$tmp_file"
  ok "已写入 ~/.ssh/config 别名：$HOST_ALIAS"
}

verify_passwordless_login() {
  log "正在验证新免密 SSH..."
  ssh \
    -i "$KEY_FILE" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o StrictHostKeyChecking=accept-new \
    -o ControlMaster=no \
    -o ControlPath=none \
    "${SSH_USER}@${SSH_HOST}" \
    "echo __SSH_OK__"

  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o ControlMaster=no \
    -o ControlPath=none \
    "$HOST_ALIAS" \
    "echo __SSH_ALIAS_OK__"

  ok "免密 SSH 验证通过"
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
  ensure_keypair
  install_public_key
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
