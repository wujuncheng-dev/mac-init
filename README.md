# 初始化 Mac

Apple 芯片 Mac 开发环境初始化。补装 Git、搜索、下载、网络等清单工具，配置 Rosetta、iTerm2、Rust stable / RISC-V 与 zsh 历史记录。已安装项目跳过，默认不执行 `brew update` 或 `brew upgrade`。

## 快速使用

前置条件：Apple 芯片、终端可访问 GitHub/Homebrew/Rust；系统组件缺失时可能要求管理员密码。

```sh
curl -fsSL https://raw.githubusercontent.com/wujuncheng-dev/mac-init/main/init-mac.sh -o init-mac.sh && /bin/bash init-mac.sh
```

彩色阶段状态、原始命令输出和每 15 秒耗时提示实时显示；完整日志及 zshrc 备份保存在 `~/Library/Logs/mac-init/run-*`。独立软件失败后继续处理其他项目，最后汇总；有失败项时退出码为 1。`NO_COLOR=1` 可关闭颜色。

```sh
/bin/bash init-mac.sh --check   # 只读检查现有安装和配置
/bin/bash init-mac.sh --update  # 明确要求安装前刷新 Homebrew 目录
```

完成后新开终端：历史自动保存、跨窗口共享、去重与历史输入建议生效；以空格开头的命令不记入历史。iTerm2 用作常见终端脚本的默认打开程序，支持的终端消息采用中文 UTF-8；仅在应用自带简体中文资源时设置中文界面，否则明确提示。不会给未翻译的菜单伪造中文设置。

Apple 未提供 CLT 安装包、网络下载失败或现有 CLT 无法支持实际构建时，会报告具体失败；全新 macOS 安装不能由语法检查或只读检查证明成功。

## 开发测试

`MAC_INIT_TEST_DIR=/可写测试目录 /bin/bash tests/run-sandbox.sh` 使用 macOS 沙盒及系统 Bash 3.2 验证真实输出、持久日志、失败退出和历史配置幂等。仅允许测试目录、系统临时文件和管道写入，不执行系统安装。
