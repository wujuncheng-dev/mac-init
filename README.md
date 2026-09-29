# 初始化 Mac

面向 Apple 芯片 Mac 的开发环境一键初始化脚本。安装 Xcode 命令行工具、Rosetta 2、Homebrew、常用命令行软件、iTerm2、Rust 及 `riscv32i-unknown-none-elf` 目标，并将 Homebrew 和 Rust 环境配置写入 `~/.zshrc`。

## 前置条件

- Apple 芯片 Mac；终端已连接外网（需要 VPN 时先连接）。
- 管理员账号；首次运行前需完成一次 `sudo` 身份验证。脚本不会绕过 macOS 授权。部分系统若不提供命令行工具的静默安装包，需先由管理员或 MDM 预装。

## 快速使用

```sh
curl -fsSL https://raw.githubusercontent.com/wujuncheng-dev/mac-init/main/init-mac.sh -o init-mac.sh && sudo -v && bash init-mac.sh
```

## 后置条件

脚本会跳过已安装的清单软件；结束时显示 Homebrew、Git、Rust 版本及已安装的 Rust 目标。打开新的 zsh 窗口即可使用更新后的环境变量。安装失败时脚本会停止并显示错误，可修复后重跑。
