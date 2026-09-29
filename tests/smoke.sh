#!/bin/bash
# Real shell/file tests; no installers, sudo or package-manager success stubs.
set -Eeuo pipefail
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
: "${MAC_INIT_TEST_DIR:?Set MAC_INIT_TEST_DIR to a writable sandbox directory}"
source "$REPO_DIR/init-mac.sh"
WORK_DIR=$(mktemp -d "$MAC_INIT_TEST_DIR/smoke.XXXXXX")
HEARTBEAT_SECONDS=1
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; }
# Exercise the real selection logic with explicit inventory data, without invoking an installer.
saved_formulae=("${FORMULAE[@]}")
FORMULAE=(git gh git-delta)
INVENTORY=$'git\ngit-delta'
select_pending_formulae > "$WORK_DIR/selection.log"
assert test "${#PENDING_FORMULAE[@]}" = 1
assert test "${PENDING_FORMULAE[0]}" = gh
INVENTORY=$'git\ngh\ngit-delta'
select_pending_formulae > "$WORK_DIR/selection.log"
assert test "${#PENDING_FORMULAE[@]}" = 0
INVENTORY=
select_pending_formulae > "$WORK_DIR/selection.log"
assert test "${PENDING_FORMULAE[*]}" = 'git gh git-delta'
FORMULAE=("${saved_formulae[@]}")
printf 'PASS: 批量安装清单筛选（部分安装、全部安装、空清单）\n'
run '真实命令输出与心跳' /bin/bash -c 'echo stdout-marker; echo stderr-marker >&2; sleep 2' > "$WORK_DIR/live.log" 2>&1
assert test "$(grep -c stdout-marker "$WORK_DIR/live.log")" = 0
assert test "$(grep -c stderr-marker "$WORK_DIR/live.log")" = 0
detail_log=$(cut -f1 "$WORK_DIR/commands.tsv" | tail -n 1)
assert grep -q stdout-marker "$detail_log"
assert grep -q stderr-marker "$detail_log"
assert grep -q 已用 "$WORK_DIR/live.log"
status=0
run '真实失败命令' /bin/bash -c 'echo deliberate-failure >&2; exit 7' > "$WORK_DIR/failure.log" 2>&1 || status=$?
assert test "$status" = 7
assert grep -q deliberate-failure "$WORK_DIR/failure.log"
assert test -z "$ACTIVE_PID"
status=0
run '长错误日志' /bin/bash -c 'echo omitted-first-line; for ((i=1; i<=60; i++)); do echo "error-line-$i"; done; exit 9' > "$WORK_DIR/long-failure.log" 2>&1 || status=$?
assert test "$status" = 9
assert test "$(grep -c omitted-first-line "$WORK_DIR/long-failure.log")" = 0
assert test "$(grep -c '^error-line-' "$WORK_DIR/long-failure.log")" = 40
detail_log=$(cut -f1 "$WORK_DIR/commands.tsv" | tail -n 1)
assert grep -q omitted-first-line "$detail_log"
status=0
run '无输出失败' /bin/bash -c 'exit 3' > "$WORK_DIR/empty-failure.log" 2>&1 || status=$?
assert test "$status" = 3
assert grep -q '命令未提供错误输出' "$WORK_DIR/empty-failure.log"

ZSHRC="$WORK_DIR/zshrc"
printf 'export MAC_INIT_TEST_VALUE=keep\n# Existing user settings\n' > "$ZSHRC"
write_zshrc "$ZSHRC" "$WORK_DIR/candidate"
cp "$ZSHRC" "$WORK_DIR/first"
write_zshrc "$ZSHRC" "$WORK_DIR/candidate"
assert cmp -s "$ZSHRC" "$WORK_DIR/first"
assert grep -q 'MAC_INIT_TEST_VALUE=keep' "$ZSHRC"
assert test "$(grep -c '^# >>> mac-init >>>$' "$ZSHRC")" = 1
/bin/zsh -f -c 'source "$1"; [[ "$MAC_INIT_TEST_VALUE" == keep && "$HISTSIZE" == 50000 && "$SAVEHIST" == 50000 && -o sharehistory && -o histignorespace && -o histreduceblanks && -o histexpiredupsfirst && ! -o incappendhistory && "$LANG" == zh_CN.UTF-8 && "$LC_CTYPE" == zh_CN.UTF-8 && ! ${+LC_ALL} == 1 && "$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE" == fg=8 && "${ZSH_AUTOSUGGEST_STRATEGY[*]}" == "history completion" ]]' _ "$ZSHRC"
printf '# >>> mac-init >>>\n' > "$WORK_DIR/broken"
cp "$WORK_DIR/broken" "$WORK_DIR/broken.before"
if write_zshrc "$WORK_DIR/broken" "$WORK_DIR/candidate"; then printf 'FAIL: accepted broken marker\n'; exit 1; fi
assert cmp -s "$WORK_DIR/broken" "$WORK_DIR/broken.before"
printf '# <<< mac-init <<<\n# >>> mac-init >>>\n' > "$WORK_DIR/reversed"
cp "$WORK_DIR/reversed" "$WORK_DIR/reversed.before"
if write_zshrc "$WORK_DIR/reversed" "$WORK_DIR/candidate"; then printf 'FAIL: accepted reversed markers\n'; exit 1; fi
assert cmp -s "$WORK_DIR/reversed" "$WORK_DIR/reversed.before"

cat > "$WORK_DIR/updates" <<'UPDATES'
* Label: macOS 27.0.1-26A434
* Label: Command Line Tools for Xcode-27.0
* Label: Command Line Tools for Xcode 28 beta
UPDATES
assert test "$(select_clt_label "$WORK_DIR/updates")" = 'Command Line Tools for Xcode-27.0'
printf '* Label: macOS 27.0.1-26A434\n' > "$WORK_DIR/updates"
assert test -z "$(select_clt_label "$WORK_DIR/updates")"
mkdir -p "$WORK_DIR/Test.app/Contents/Resources/zh-Hans.lproj"
assert test "$(chinese_resource "$WORK_DIR/Test.app")" = zh-Hans
if chinese_resource "$WORK_DIR/NoLocalization.app"; then printf 'FAIL: invented Chinese localization\n'; exit 1; fi

FAILURES=()
WARNINGS=()
fail 'expected test failure' > /dev/null
status=0
summary > "$WORK_DIR/summary.log" || status=$?
assert test "$status" = 1
assert grep -q expected "$WORK_DIR/summary.log"
printf 'PASS: 成功输出隐藏、失败输出展示与截取、心跳、退出码、配置幂等、zsh 历史选项、损坏配置保护、CLT 标签、中文资源检测、失败汇总\n测试日志：%s\n' "$WORK_DIR"
/bin/bash -c 'source "$1/init-mac.sh"; STATE_DIR="$2/persistent-log"; HEARTBEAT_SECONDS=1; start_log; run "持久日志测试" /bin/bash -c "echo saved-stdout; echo saved-stderr >&2"' _ "$REPO_DIR" "$WORK_DIR" > "$WORK_DIR/logger-output" 2>&1
assert test "$(grep -c saved-stdout "$WORK_DIR/logger-output")" = 0
assert test "$(grep -c saved-stderr "$WORK_DIR/logger-output")" = 0
for logfile in "$WORK_DIR/persistent-log"/run-*/run.log; do
  assert grep -q '成功.*持久日志测试' "$logfile"
  assert test "$(grep -c saved-stdout "$logfile")" = 0
done
for logfile in "$WORK_DIR/persistent-log"/run-*/command.*; do
  assert grep -q saved-stdout "$logfile"
  assert grep -q saved-stderr "$logfile"
done
printf 'PASS: 终端只显示状态，原始 stdout/stderr 完整持久保存\n'
if [[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh &&
      -r /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh &&
      -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  /bin/zsh -f -i -c 'source "$1"; source "$1"; (( $+functions[_zsh_autosuggest_start] && $+functions[history-substring-search-up] && $+functions[_zsh_highlight] )) || exit 1; [[ "$(bindkey "^[[A")" == *history-substring-search-up && "$(bindkey "^[[B")" == *history-substring-search-down ]] || exit 1; HISTFILE=/dev/null; SAVEHIST=0' _ "$ZSHRC"
  printf 'PASS: 本机真实 zsh 插件加载、重复加载保护及方向键绑定\n'
else
  printf 'SKIP: 本机缺少插件文件，未验证交互插件加载\n'
fi
