#!/bin/bash
set -Eeuo pipefail

log() { printf '\n==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
trap 'printf "失败位置：第 %s 行（退出码 %s）\n" "$LINENO" "$?" >&2' ERR

[[ "$(uname -s)" == Darwin ]] || die "此脚本仅适用于 macOS。"
[[ "$(uname -m)" == arm64 ]] || die "此脚本仅适用于 Apple 芯片 Mac。"
[[ "$(id -u)" -ne 0 ]] || die "请以普通用户运行，不要使用 sudo 执行整个脚本。"

# Verify the terminal's actual HTTPS route, including any VPN/proxy settings.
log "检查终端外网连接"
for url in https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
           https://formulae.brew.sh/api/formula/git.json \
           https://sh.rustup.rs \
           https://static.rust-lang.org/dist/channel-rust-stable.toml.sha256; do
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --location --head --connect-timeout 10 --max-time 25 "$url" >/dev/null \
    || die "终端无法访问 $url。请先连接 VPN，并确认终端的代理/DNS 设置。"
done

# A stock Mac requires administrator authorization. Never stop for a password.
sudo -n true 2>/dev/null || die "当前终端没有免交互管理员授权。需由管理员预配免密 sudo，或在运行前执行 sudo -v；脚本无法绕过 macOS 身份验证。"

ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"

add_zshrc_line() {
  local line="$1"
  /usr/bin/grep -Fqx "$line" "$ZSHRC" || printf '\n%s\n' "$line" >> "$ZSHRC"
}

log "安装 Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
  # Match Homebrew's supported headless CLT discovery method.
  clt_marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo -n touch "$clt_marker"
  clt_list="$(LC_ALL=C /usr/sbin/softwareupdate --list 2>&1)" || {
    sudo -n rm -f "$clt_marker"
    die "无法查询 Command Line Tools 更新。"
  }
  clt_label="$(printf '%s\n' "$clt_list" \
    | /usr/bin/awk -F 'Label: ' '/Label: Command Line Tools/ && !/[Bb]eta/ {print $2}' \
    | /usr/bin/tail -n 1)"
  sudo -n rm -f "$clt_marker"
  [[ -n "$clt_label" ]] || die "Apple 软件更新未提供 Command Line Tools 静默安装包。"
  sudo -n /usr/sbin/softwareupdate --install "$clt_label"
  sudo -n /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
  xcrun --find clang >/dev/null 2>&1 || die "Command Line Tools 安装后 clang 仍不可用。"
fi

log "安装 Rosetta 2"
if ! /usr/bin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  sudo -n /usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

log "安装或配置 Homebrew"
if command -v brew >/dev/null 2>&1; then
  BREW_BIN="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN=/usr/local/bin/brew
else
  NONINTERACTIVE=1 /bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN=/usr/local/bin/brew
  else
    die "Homebrew 安装后未找到 brew。"
  fi
fi

BREW_SHELLENV="eval \"\$($BREW_BIN shellenv)\""
add_zshrc_line "$BREW_SHELLENV"
eval "$("$BREW_BIN" shellenv)"

log "更新 Homebrew"
brew update
brew upgrade

log "安装开发依赖与命令行工具"
formulae=(
  pkgconf openssl@3 git gh git-delta git-lfs lazygit tig diff-so-fancy hub ugit
  fd ast-grep the_silver_searcher bat tree tldr
  aria2 wget yt-dlp cloudflared caddy mkcert trippy
  jq hyperfine pandoc tokei sshpass wakeonlan trufflehog duti
)
brew install "${formulae[@]}"
git lfs install

log "安装 iTerm2"
brew install --cask iterm2

log "将 iTerm2 设为常见脚本文件的默认打开程序"
for ext in command tool zsh csh pl; do
  duti -s com.googlecode.iterm2 "$ext" all
done

log "安装 Rust 官方 rustup"
if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
fi
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
add_zshrc_line '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
command -v rustup >/dev/null 2>&1 || die "rustup 安装后仍不可用。"
rustup toolchain install stable
rustup default stable
rustup target add riscv32i-unknown-none-elf

log "验证"
brew --version
git --version
rustc --version
cargo --version
rustup target list --installed
printf '\n初始化完成。新开的 zsh 窗口会自动加载 ~/.zshrc。\n'
