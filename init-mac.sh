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
(while sudo -n -v >/dev/null 2>&1; do sleep 60; done) &
sudo_keepalive_pid=$!
trap 'kill "$sudo_keepalive_pid" 2>/dev/null || true' EXIT

ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"

add_zshrc_line() {
  local line="$1"
  /usr/bin/grep -Fqx "$line" "$ZSHRC" || printf '\n%s\n' "$line" >> "$ZSHRC"
}

log "安装 Xcode Command Line Tools"
clt_ready=0
if xcode-select -p >/dev/null 2>&1 && xcrun --find clang >/dev/null 2>&1; then
  clt_ready=1
fi
clt_version=$(/usr/sbin/pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null \
  | /usr/bin/awk '/^version: / {print $2}' || true)
if [[ -z "$clt_version" ]]; then
  if command -v brew >/dev/null 2>&1; then
    clt_version=$(brew config | /usr/bin/awk -F ': ' '/^CLT: / {print $2}')
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    clt_version=$(/opt/homebrew/bin/brew config | /usr/bin/awk -F ': ' '/^CLT: / {print $2}')
  fi
fi
macos_major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d . -f 1)
clt_major=${clt_version%%.*}
if [[ "$clt_ready" -eq 0 || ( -n "$clt_version" && "$clt_major" =~ ^[0-9]+$ && "$clt_major" -lt "$macos_major" ) ]]; then
  # Software Update can install CLT without opening the xcode-select GUI.
  clt_marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  [[ ! -e "$clt_marker" ]] || die "检测到其他 Command Line Tools 安装任务：$clt_marker"
  sudo -n touch "$clt_marker"
  clt_list="$(LC_ALL=C /usr/sbin/softwareupdate --list 2>&1)" || {
    sudo -n rm -f "$clt_marker"
    die "无法查询 Command Line Tools 更新。"
  }
  clt_label="$(printf '%s\n' "$clt_list" \
    | /usr/bin/awk '/Command Line Tools/ && !/[Bb]eta/ && (/Label: / || /^[[:space:]]*\*/) { sub(/^.*Label: /, ""); sub(/^[[:space:]]*\*[[:space:]]*/, ""); print }' \
    | /usr/bin/tail -n 1)"
  sudo -n rm -f "$clt_marker"
  [[ -n "$clt_label" ]] || die "Apple 软件更新未提供适用于 macOS $macos_major 的 Command Line Tools 静默安装包。"
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

log "更新 Homebrew 软件目录"
brew update
export HOMEBREW_NO_ASK=1 HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_AUTO_UPDATE=1

# Homebrew knows which CLT release its current macOS version requires.
brew_clt_version=$(brew config | /usr/bin/awk -F ': ' '/^CLT: / {print $2}')
brew_clt_major=${brew_clt_version%%.*}
if [[ ! "$brew_clt_major" =~ ^[0-9]+$ || "$brew_clt_major" -lt "$macos_major" ]]; then
  die "当前 Command Line Tools 为 ${brew_clt_version:-未知版本}，不支持 macOS $macos_major。请先安装适配版本后重跑。"
fi

log "安装开发依赖与命令行工具"
formulae=(
  pkgconf openssl@3 git gh git-delta git-lfs lazygit tig diff-so-fancy hub ugit
  fd ast-grep the_silver_searcher bat tree tldr
  aria2 wget yt-dlp cloudflared caddy mkcert trippy
  jq hyperfine pandoc tokei sshpass wakeonlan trufflehog duti
)
missing_formulae=()
for formula in "${formulae[@]}"; do
  if brew list --formula --versions "$formula" >/dev/null 2>&1; then
    log "已安装，跳过：$formula"
  else
    missing_formulae+=("$formula")
  fi
done
if (( ${#missing_formulae[@]} > 0 )); then
  brew install --formula -y "${missing_formulae[@]}"
fi
if [[ "$(git config --global --get filter.lfs.process || true)" == 'git-lfs filter-process' ]] \
  && [[ "$(git config --global --get filter.lfs.clean || true)" == 'git-lfs clean -- %f' ]] \
  && [[ "$(git config --global --get filter.lfs.smudge || true)" == 'git-lfs smudge -- %f' ]]; then
  log "已配置，跳过：Git LFS"
else
  git lfs install --global --skip-repo
fi

log "安装 iTerm2"
if brew list --cask --versions iterm2 >/dev/null 2>&1 \
  || [[ -d /Applications/iTerm.app || -d "$HOME/Applications/iTerm.app" ]]; then
  log "已安装，跳过：iTerm2"
else
  brew install --cask -y iterm2
fi

log "将 iTerm2 设为常见脚本文件的默认打开程序"
for ext in command tool zsh csh pl; do
  if [[ "$(duti -x "$ext" 2>/dev/null | /usr/bin/tail -n 1)" == com.googlecode.iterm2 ]]; then
    log "已配置，跳过：.$ext"
  else
    duti -s com.googlecode.iterm2 "$ext" all
  fi
done

log "安装 Rust 官方 rustup"
if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
fi
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
add_zshrc_line '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
command -v rustup >/dev/null 2>&1 || die "rustup 安装后仍不可用。"
if ! rustup toolchain list | /usr/bin/grep -Eq '^stable-[^ ]+'; then
  rustup toolchain install stable
fi
if ! rustup default | /usr/bin/grep -q '^stable-'; then
  rustup default stable
fi
if ! rustup target list --toolchain stable --installed | /usr/bin/grep -Fxq riscv32i-unknown-none-elf; then
  rustup target add --toolchain stable riscv32i-unknown-none-elf
fi

log "验证"
brew --version
git --version
rustc --version
cargo --version
rustup target list --toolchain stable --installed
printf '\n初始化完成。新开的 zsh 窗口会自动加载 ~/.zshrc。\n'
