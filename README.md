# 初始化 Mac

Apple 芯片 Mac 开发环境初始化。补装 Git、搜索、下载、网络等清单工具，配置 Rosetta、iTerm2、Rust stable / RISC-V 与 zsh 历史记录。已安装项目跳过，默认不执行 `brew update` 或 `brew upgrade`。

缺失的命令行工具使用一条 `brew install` 批量安装，默认由 Homebrew 自动决定下载并发；可用 `HOMEBREW_DOWNLOAD_CONCURRENCY=8 /bin/bash init-mac.sh` 指定并发连接数。批量命令失败后核验已安装结果，并继续后续阶段。

## 快速使用

前置条件：Apple 芯片、终端可访问 GitHub/Homebrew/Rust；系统组件缺失时可能要求管理员密码。

```sh
curl -fsSL https://raw.githubusercontent.com/wujuncheng-dev/mac-init/main/init-mac.sh -o init-mac.sh && /bin/bash init-mac.sh
```

终端只显示彩色阶段状态和每 15 秒耗时提示；命令失败时展示最后 40 行原始输出。完整输出保存在 `~/Library/Logs/mac-init/run-*` 的 `command.*` 文件，`commands.tsv` 对应任务名称，`run.log` 保存状态日志；zshrc 备份也在该目录。独立软件失败后继续处理其他项目，最后汇总；有失败项时退出码为 1。`NO_COLOR=1` 可关闭颜色。

```sh
/bin/bash init-mac.sh --check   # 只读检查现有安装和配置
/bin/bash init-mac.sh --update  # 明确要求安装前刷新 Homebrew 目录
```

完成后新开终端：沿用作者 Mac 的 5 万条历史配置，自动保存、跨窗口共享、去重、灰色历史/补全建议、↑/↓ 匹配历史和语法高亮；以空格开头的命令不记入历史。仅迁移配置，不包含任何历史命令。中文终端使用 `LANG`、`LC_CTYPE=zh_CN.UTF-8` 并清除 `LC_ALL` 覆盖。iTerm2 用作常见终端脚本的默认打开程序；自带简体中文资源时设置中文偏好，否则保留现有界面语言。

Apple 未提供 CLT 安装包、网络下载失败或现有 CLT 无法支持实际构建时，会报告具体失败；全新 macOS 安装不能由语法检查或只读检查证明成功。

## 开发测试

`MAC_INIT_TEST_DIR=/可写测试目录 /bin/bash tests/run-sandbox.sh` 使用 macOS 沙盒及系统 Bash 3.2 验证真实输出、持久日志、失败退出和历史配置幂等。仅允许测试目录、系统临时文件和管道写入，不执行系统安装。
