#!/bin/bash
# Compatible with the Bash 3.2 shipped with macOS.
set -Eeuo pipefail

FORMULAE=(pkgconf openssl@3 git gh git-delta git-lfs lazygit tig diff-so-fancy hub ugit
  fd ast-grep the_silver_searcher bat tree tldr aria2 wget yt-dlp cloudflared caddy
  mkcert trippy jq hyperfine pandoc tokei sshpass wakeonlan trufflehog duti zsh-autosuggestions
  zsh-history-substring-search zsh-syntax-highlighting)
TARGET=riscv32i-unknown-none-elf
FAILURES=()
WARNINGS=()
BREW_BIN=/opt/homebrew/bin/brew
STATE_DIR=${MAC_INIT_STATE_DIR:-"$HOME/Library/Logs/mac-init"}
ZSHRC=${MAC_INIT_ZSHRC:-"$HOME/.zshrc"}
HEARTBEAT_SECONDS=${MAC_INIT_HEARTBEAT_SECONDS:-15}
ACTIVE_PID=
WORK_DIR=
CLT_MARKER_OWNED=0
CLT_MARKER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
COLOR_RESET= COLOR_BLUE= COLOR_GREEN= COLOR_YELLOW= COLOR_RED=

colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR_RESET=$'\033[0m'; COLOR_BLUE=$'\033[36m'; COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'; COLOR_RED=$'\033[31m'
  fi
}
log() {
  local level=$1 color=$COLOR_BLUE
  shift
  case "$level" in 成功|跳过) color=$COLOR_GREEN;; 提醒) color=$COLOR_YELLOW;; 失败) color=$COLOR_RED;; esac
  printf '%s[%s] %-4s %s%s\n' "$color" "$(date '+%H:%M:%S')" "$level" "$*" "$COLOR_RESET"
}
fail() {
  local item
  if (( ${#FAILURES[@]} )); then for item in "${FAILURES[@]}"; do [[ "$item" != "$*" ]] || return 0; done; fi
  FAILURES+=("$*"); log 失败 "$*"
}
warn() {
  local item
  if (( ${#WARNINGS[@]} )); then for item in "${WARNINGS[@]}"; do [[ "$item" != "$*" ]] || return 0; done; fi
  WARNINGS+=("$*"); log 提醒 "$*"
}
contains() { /usr/bin/grep -Fx "$2" <<< "$1" >/dev/null; }
cleanup() {
  if [[ -n "$ACTIVE_PID" ]]; then kill "$ACTIVE_PID" 2>/dev/null || :; wait "$ACTIVE_PID" 2>/dev/null || :; fi
  if [[ "$CLT_MARKER_OWNED" == 1 ]]; then rm -f "$CLT_MARKER"; fi
  # Keep downloaded installers and command output with this run's log for diagnosis.
}
unexpected_error() {
  local status=$1 line=$2
  log 失败 "意外错误：第 $line 行，退出码 ${status}。日志：${LOG_FILE:-尚未创建}"
  exit "$status"
}
start_log() {
  umask 077
  mkdir -p "$STATE_DIR"
  WORK_DIR=$(mktemp -d "$STATE_DIR/run-$(date '+%Y%m%d-%H%M%S').XXXXXX")
  LOG_FILE="$WORK_DIR/run.log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log 信息 "日志实时保存到：$LOG_FILE"
}
# Run in the foreground, preserving stdin/TTY for genuine administrator authentication.
# The heartbeat only reports elapsed time; it never manipulates sudo credentials.
run() {
  local title=$1 started=$SECONDS status=0 command_log
  shift
  command_log=$(mktemp "$WORK_DIR/command.XXXXXX") || return 1
  printf '%s\t%s\n' "$command_log" "$title" >> "$WORK_DIR/commands.tsv"
  log 执行 "$title"
  (
    sleeper=
    trap 'if [[ -n "$sleeper" ]]; then kill "$sleeper" 2>/dev/null || :; wait "$sleeper" 2>/dev/null || :; fi; exit 0' TERM INT
    while :; do
      sleep "$HEARTBEAT_SECONDS" &
      sleeper=$!
      wait "$sleeper" || exit 0
      log 等待 "${title}，已用 $((SECONDS - started)) 秒"
    done
  ) &
  ACTIVE_PID=$!
  "$@" > "$command_log" 2>&1 || status=$?
  kill "$ACTIVE_PID" 2>/dev/null || :
  wait "$ACTIVE_PID" 2>/dev/null || :
  ACTIVE_PID=
  if [[ "$status" == 0 ]]; then
    log 成功 "${title}（$((SECONDS - started)) 秒）"
  else
    log 失败 "${title}（退出码 ${status}，$((SECONDS - started)) 秒）"
    log 信息 "完整错误日志：$command_log"
    if [[ -s "$command_log" ]]; then
      log 信息 '命令输出（最后 40 行）：'
      /usr/bin/tail -n 40 "$command_log"
    else
      log 信息 '命令未提供错误输出。'
    fi
  fi
  return "$status"
}
platform_check() {
  [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { log 失败 "仅支持原生 Apple 芯片 macOS；请勿在 Rosetta 终端中运行。"; return 1; }
  [[ "$(id -u)" != 0 ]] || { log 失败 "请以普通用户运行整个脚本。"; return 1; }
  [[ "$HEARTBEAT_SECONDS" =~ ^[1-9][0-9]*$ ]] || { log 失败 "心跳间隔必须是正整数。"; return 1; }
}
network_check() {
  local url
  log 阶段 '[1/7] 检查终端 HTTPS 连接（可验证可达性，不能判断是否经过 VPN）'
  for url in https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    https://formulae.brew.sh/api/formula/git.json https://sh.rustup.rs \
    https://static.rust-lang.org/dist/channel-rust-stable.toml.sha256; do
    run "访问 $url" curl --proto '=https' --tlsv1.2 -fLsS --connect-timeout 10 \
      --max-time 30 -o /dev/null "$url" || { fail "终端无法访问 ${url}；检查 VPN、终端代理和 DNS。"; return 1; }
  done
}
clt_available() { /usr/bin/xcode-select -p >/dev/null 2>&1 && /usr/bin/xcrun --find clang >/dev/null 2>&1; }
select_clt_label() {
  # Only labels are accepted, never titles, OS upgrades or beta releases.
  /usr/bin/awk '/^[[:space:]]*\*/ && /Command Line Tools/ && !/[Bb]eta/ {
    sub(/^[[:space:]]*\*[[:space:]]*/, ""); sub(/^Label: /, ""); print
  }' "$1" | /usr/bin/tail -n 1
}
apple_tools() {
  local label
  log 阶段 '[2/7] Apple 编译工具与 Rosetta'
  if clt_available; then
    log 跳过 'Command Line Tools 已可调用；实际构建兼容性由安装器检查'
  elif [[ -x /Library/Developer/CommandLineTools/usr/bin/clang ]]; then
    run '修复 Command Line Tools 路径（可能需要管理员密码）' sudo /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools || fail 'CLT 路径修复失败'
  elif [[ -e "$CLT_MARKER" ]]; then
    fail "发现现有 CLT 安装标记，请确认其他安装任务：$CLT_MARKER"
  else
    touch "$CLT_MARKER"
    CLT_MARKER_OWNED=1
    if run '查询 Apple 可用安装包' /bin/bash -o pipefail -c 'LC_ALL=C /usr/sbin/softwareupdate --list 2>&1 | tee "$1"' _ "$WORK_DIR/softwareupdate.log"; then
      label=$(select_clt_label "$WORK_DIR/softwareupdate.log")
      if [[ -n "$label" ]]; then
        run "安装 ${label}（可能需要管理员密码）" sudo /usr/sbin/softwareupdate --install "$label" || fail 'CLT 安装失败'
      else
        fail 'Apple 未提供正式版 CLT 安装包；请从 https://developer.apple.com/download/all/ 安装匹配版本。更新列表已保存。'
      fi
    else
      fail 'Apple 更新列表查询失败，详见原始输出'
    fi
    rm -f "$CLT_MARKER"
    CLT_MARKER_OWNED=0
  fi
  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    log 跳过 'Rosetta 2 已安装'
  else
    run '安装 Rosetta 2 并接受许可' /usr/sbin/softwareupdate --install-rosetta --agree-to-license || fail 'Rosetta 2 安装失败'
  fi
}
setup_brew() {
  log 阶段 '[3/7] Homebrew'
  if [[ -x "$BREW_BIN" ]]; then
    log 跳过 'Homebrew 已安装'
  else
    if ! clt_available; then fail 'CLT 不可用，暂不启动可能打开 GUI 的 Homebrew 安装器'; return 1; fi
    run '下载 Homebrew 官方安装器' curl --proto '=https' --tlsv1.2 -fLSs --connect-timeout 10 --max-time 180 \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$WORK_DIR/homebrew-install.sh" || { fail 'Homebrew 安装器下载失败'; return 1; }
    run '验证 Homebrew 安装权限（可能需要管理员密码）' sudo -v || { fail 'Homebrew 管理员授权失败'; return 1; }
    run '安装 Homebrew（自动确认）' env NONINTERACTIVE=1 /bin/bash "$WORK_DIR/homebrew-install.sh" || { fail 'Homebrew 安装失败'; return 1; }
  fi
  [[ -x "$BREW_BIN" ]] || { fail '未找到 /opt/homebrew/bin/brew'; return 1; }
  eval "$("$BREW_BIN" shellenv)" || { fail 'Homebrew 环境加载失败'; return 1; }
  # Explicit policy: initialize missing software, do not refresh all taps or upgrade the machine.
  export HOMEBREW_NO_ASK=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1
  export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  if [[ "$UPDATE_BREW" == 1 ]]; then
    run '按 --update 要求刷新 Homebrew 目录' "$BREW_BIN" update || { fail '指定的 Homebrew 目录更新失败'; return 1; }
  else
    log 跳过 '默认不运行 brew update / brew upgrade；需要刷新目录可传 --update'
  fi
}
load_inventory() {
  run '读取本地 Homebrew 安装清单' /bin/bash -c '"$1" list --formula -1 > "$2"' _ "$BREW_BIN" "$WORK_DIR/formulae.txt" || return 1
  INVENTORY=$(cat "$WORK_DIR/formulae.txt")
}
lfs_configured() {
  [[ "$(git config --global --get filter.lfs.process 2>/dev/null)" == 'git-lfs filter-process' ]] \
    && [[ "$(git config --global --get filter.lfs.required 2>/dev/null)" == true ]]
}
select_pending_formulae() {
  local formula index=0
  PENDING_FORMULAE=()
  for formula in "${FORMULAE[@]}"; do
    index=$((index + 1))
    if contains "$INVENTORY" "$formula"; then
      log 跳过 "[$index/${#FORMULAE[@]}] $formula 已安装"
    else
      PENDING_FORMULAE+=("$formula")
      log 信息 "[$index/${#FORMULAE[@]}] 待安装 $formula"
    fi
  done
}
install_formulae() {
  local formula
  log 阶段 '[4/7] 命令行工具'
  if ! load_inventory; then fail '无法读取本地安装清单'; return 1; fi
  select_pending_formulae
  if (( ${#PENDING_FORMULAE[@]} )); then
    export HOMEBREW_DOWNLOAD_CONCURRENCY=${HOMEBREW_DOWNLOAD_CONCURRENCY:-auto}
    log 信息 "批量安装 ${#PENDING_FORMULAE[@]} 个软件；下载并发：$HOMEBREW_DOWNLOAD_CONCURRENCY"
    run '批量安装缺失软件（Homebrew 并发下载）' "$BREW_BIN" install --formula -y "${PENDING_FORMULAE[@]}" \
      || fail 'Homebrew 批量安装返回失败，详见错误日志；将核验实际安装结果'
    load_inventory || { fail '批量安装后无法刷新本地清单'; return 1; }
    for formula in "${PENDING_FORMULAE[@]}"; do
      if contains "$INVENTORY" "$formula"; then log 成功 "$formula 已登记安装"
      else fail "$formula 未安装；修复错误后重跑会跳过已安装项目"; fi
    done
  else
    log 跳过 '命令行工具均已安装'
  fi
  if lfs_configured; then
    log 跳过 'Git LFS 全局过滤器已配置'
  elif command -v git-lfs >/dev/null 2>&1; then
    run '初始化 Git LFS 全局过滤器（已有配置由 Git LFS 保留）' git lfs install --skip-repo || fail 'Git LFS 配置失败'
  else
    fail 'Git LFS 不可用，无法配置过滤器'
  fi
}
iterm_path() {
  local candidate
  for candidate in /Applications/iTerm.app "$HOME/Applications/iTerm.app"; do
    if [[ -d "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}
chinese_resource() {
  local app=$1 language
  for language in zh-Hans zh_CN zh-CN; do
    if [[ -d "$app/Contents/Resources/$language.lproj" ]]; then printf '%s\n' "$language"; return 0; fi
  done
  return 1
}
setup_iterm() {
  local app language ext result
  log 阶段 '[5/7] iTerm2 与语言'
  if app=$(iterm_path); then log 跳过 "iTerm2 已安装：$app"
  elif run '安装 iTerm2' "$BREW_BIN" install --cask -y iterm2; then
    app=$(iterm_path) || { fail '安装后未找到 iTerm.app'; return 1; }
  else fail 'iTerm2 安装失败'; return 1; fi
  if command -v duti >/dev/null 2>&1; then
    for ext in command tool zsh csh pl; do
      result=$(duti -x "$ext" 2>/dev/null) || result=
      if [[ "${result##*$'\n'}" == com.googlecode.iterm2 ]]; then log 跳过 ".$ext 默认程序已是 iTerm2"
      elif run "设置 .$ext 默认打开程序" duti -s com.googlecode.iterm2 ".$ext" all; then
        result=$(duti -x "$ext") || { fail "无法验证 .$ext 默认程序"; continue; }
        [[ "${result##*$'\n'}" == com.googlecode.iterm2 ]] || fail ".$ext 默认程序未生效"
      else fail ".$ext 文件关联设置失败"; fi
    done
  else fail '缺少 duti，未设置 iTerm2 默认文件关联'; fi
  if language=$(chinese_resource "$app"); then
    run '设置 iTerm2 简体中文界面偏好（重启应用后生效）' defaults write com.googlecode.iterm2 AppleLanguages -array "$language" en || fail 'iTerm2 语言偏好设置失败'
  else
    log 信息 '保留 iTerm2 现有语言偏好；终端中文由 zsh 的 UTF-8 配置提供。'
  fi
}
shell_block() {
  cat <<'ZSH'
# >>> mac-init >>>
# Managed by mac-init. User settings outside this block are preserved.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if [[ -d "$HOME/.cargo/bin" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
unsetopt INC_APPEND_HISTORY INC_APPEND_HISTORY_TIME
setopt APPEND_HISTORY SHARE_HISTORY EXTENDED_HISTORY HIST_FCNTL_LOCK
setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_IGNORE_SPACE
setopt HIST_EXPIRE_DUPS_FIRST HIST_REDUCE_BLANKS
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
if [[ -o interactive && -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  if (( ! $+functions[_zsh_autosuggest_start] )); then
    source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  fi
fi
if [[ -o interactive && -r /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  if (( ! $+functions[history-substring-search-up] )); then
    source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh
  fi
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi
# Match the source Mac's terminal locale; keep iTerm2 menu preferences separate.
export LANG=zh_CN.UTF-8
export LC_CTYPE=zh_CN.UTF-8
unset LC_ALL
# Load highlighting after the history widgets.
if [[ -o interactive && -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  if (( ! $+functions[_zsh_highlight] )); then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  fi
fi
# <<< mac-init <<<
ZSH
}
write_zshrc() {
  local target=$1 candidate=$2 begins ends
  [[ ! -e "$target" || -f "$target" ]] || return 1
  if [[ -f "$target" ]]; then
    begins=$(/usr/bin/grep -c '^# >>> mac-init >>>$' "$target" || :)
    ends=$(/usr/bin/grep -c '^# <<< mac-init <<<$' "$target" || :)
    [[ "$begins" == "$ends" && "$begins" -le 1 ]] || { log 失败 'zshrc 管理区块不完整，请先修复标记'; return 1; }
    if [[ "$begins" == 1 ]]; then
      /usr/bin/awk '/^# >>> mac-init >>>$/{b=NR} /^# <<< mac-init <<<$/{e=NR} END{exit !(b<e)}' "$target" || { log 失败 'zshrc 管理区块顺序错误'; return 1; }
    fi
    /usr/bin/awk '/^# >>> mac-init >>>$/ {skip=1; next} /^# <<< mac-init <<<$/{skip=0; next} !skip{print}' "$target" > "$candidate" || return 1
  else : > "$candidate"; fi
  shell_block >> "$candidate" || return 1
  /bin/zsh -n "$candidate" || return 1
  if [[ -f "$target" ]] && cmp -s "$target" "$candidate"; then log 跳过 'zsh 历史记录与环境配置已一致'; return 0; fi
  if [[ -f "$target" ]]; then cp -p "$target" "$WORK_DIR/zshrc.before" || return 1; fi
  cat "$candidate" > "$target" || return 1
  log 成功 '已配置历史持久保存、多窗口共享、去重与历史输入建议；新终端窗口生效'
}
setup_shell() {
  log 阶段 '[6/7] zsh 环境与历史记录'
  write_zshrc "$ZSHRC" "$WORK_DIR/zshrc.new" || fail 'zsh 配置写入失败'
}
setup_rust() {
  log 阶段 '[7/7] Rust 与 RISC-V'
  if [[ -x "$HOME/.cargo/bin/rustup" ]]; then export PATH="$HOME/.cargo/bin:$PATH"; fi
  if command -v rustup >/dev/null 2>&1; then log 跳过 'rustup 已安装'
  else
    run '下载 Rust 官方安装器' curl --proto '=https' --tlsv1.2 -fLSs --connect-timeout 10 --max-time 180 https://sh.rustup.rs -o "$WORK_DIR/rustup.sh" || { fail 'Rust 安装器下载失败'; return 1; }
    run '安装 Rust stable（自动确认）' /bin/sh "$WORK_DIR/rustup.sh" -y --no-modify-path --default-toolchain stable || { fail 'Rust 安装失败'; return 1; }
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
  local toolchains targets
  toolchains=$(rustup toolchain list) || { fail '无法读取 Rust 工具链'; return 1; }
  if /usr/bin/grep -E '^stable-' <<< "$toolchains" >/dev/null; then log 跳过 'Rust stable 已安装'
  else run '安装 stable 工具链' rustup toolchain install stable || { fail 'stable 安装失败'; return 1; }; fi
  targets=$(rustup target list --toolchain stable --installed) || { fail '无法读取 Rust 目标'; return 1; }
  if contains "$targets" "$TARGET"; then log 跳过 "$TARGET 已安装"
  else run "添加 $TARGET" rustup target add --toolchain stable "$TARGET" || fail 'RISC-V 目标安装失败'; fi
  run '验证 Rust stable' rustup run stable rustc --version || fail 'Rust stable 验证失败'
}
check_installation() {
  local inventory formula app targets ext result actual_block
  [[ -x "$BREW_BIN" ]] || { fail 'Homebrew 缺失'; return 1; }
  export HOMEBREW_NO_AUTO_UPDATE=1
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  inventory=$("$BREW_BIN" list --formula -1) || { fail '无法读取安装清单'; return 1; }
  for formula in "${FORMULAE[@]}"; do
    if contains "$inventory" "$formula"; then log 成功 "$formula 已登记安装"; else fail "$formula 未安装"; fi
  done
  if app=$(iterm_path); then
    log 成功 "iTerm2：$app"
    log 信息 'iTerm2 界面语言保留应用现有偏好；中文终端配置单独核验。'
  else fail 'iTerm2 未安装'; fi
  if [[ -x "$HOME/.cargo/bin/rustup" ]]; then export PATH="$HOME/.cargo/bin:$PATH"; fi
  if command -v rustup >/dev/null 2>&1; then
    targets=$(rustup target list --toolchain stable --installed) || { fail 'Rust stable 目标不可用'; return 1; }
    contains "$targets" "$TARGET" && log 成功 "$TARGET 已安装" || fail "$TARGET 未安装"
  else fail 'rustup 未安装'; fi
  clt_available && log 成功 'CLT 可调用' || fail 'CLT 不可调用'
  /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1 && log 成功 'Rosetta 已安装' || fail 'Rosetta 未安装'
  if [[ -f "$ZSHRC" ]]; then
    actual_block=$(/usr/bin/awk '/^# >>> mac-init >>>$/{inside=1} inside{print} /^# <<< mac-init <<<$/{inside=0}' "$ZSHRC")
    [[ "$actual_block" == "$(shell_block)" ]] && log 成功 'zsh 环境与历史配置一致' || fail 'zsh 环境与历史配置未写入或不一致'
  else fail 'zsh 配置文件缺失'; fi
  lfs_configured && log 成功 'Git LFS 过滤器已配置' || fail 'Git LFS 过滤器未配置'
  if command -v duti >/dev/null 2>&1; then
    for ext in command tool zsh csh pl; do
      result=$(duti -x "$ext" 2>/dev/null) || result=
      [[ "${result##*$'\n'}" == com.googlecode.iterm2 ]] && log 成功 ".$ext 默认程序为 iTerm2" || fail ".$ext 默认打开程序尚未设为 iTerm2"
    done
  fi
}
summary() {
  local item
  if (( ${#WARNINGS[@]} )); then for item in "${WARNINGS[@]}"; do log 提醒 "$item"; done; fi
  if (( ${#FAILURES[@]} )); then
    log 失败 "未全部完成：${#FAILURES[@]} 项问题。修复后重跑会跳过已安装项目。"
    for item in "${FAILURES[@]}"; do log 失败 "$item"; done
    return 1
  fi
  log 成功 "安装与核验完成，另有 ${#WARNINGS[@]} 条提醒。请新开 zsh 窗口；有界面语言变更时重启 iTerm2。"
}
main() {
  local mode=install
  UPDATE_BREW=0
  while (( $# )); do
    case "$1" in --check) mode=check;; --update) UPDATE_BREW=1;; --help|-h) printf '用法：bash init-mac.sh [--check | --update]\n--check 只读检查安装状态；--update 安装前显式刷新 Homebrew 目录。\n'; return 0;; *) printf '未知参数：%s\n' "$1" >&2; return 2;; esac
    shift
  done
  colors
  platform_check || return 1
  if [[ "$mode" == check ]]; then check_installation || :; summary; return $?; fi
  start_log
  trap cleanup EXIT
  trap 'unexpected_error "$?" "$LINENO"' ERR
  trap 'log 失败 "用户中断；已完成项目可在下次运行时跳过"; exit 130' INT TERM
  network_check || { summary || :; trap - ERR; return 1; }
  apple_tools
  if setup_brew; then
    install_formulae || :
    setup_iterm || :
  else fail 'Homebrew 阶段失败，依赖它的安装步骤未执行'; fi
  setup_shell
  setup_rust || :
  log 阶段 '最终核验'
  check_installation || :
  log 信息 "完整日志：${LOG_FILE}；zshrc 备份（若有修改）：$WORK_DIR/zshrc.before"
  local status=0
  summary || status=$?
  trap - ERR
  return "$status"
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
