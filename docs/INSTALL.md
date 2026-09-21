# Alter 0.1.0 安装说明

从 https://github.com/NINKIGAL-DXH/Alter/releases 下载对应芯片的 DMG 和 SHA-256 文件。Apple Silicon 使用 arm64，Intel 使用 x86_64。最低 macOS 14；原生 Liquid Glass 需要 macOS 26 或更新版本。

在下载目录使用 `shasum -a 256 -c Alter-0.1.0-arm64.dmg.sha256` 验证（Intel 替换架构名），打开 DMG，将 Alter.app 拖入应用程序。

当前版本使用 ad-hoc 签名，尚未获得 Apple Developer ID 签名和公证。系统可能阻止打开。请先核对来源和校验和，再由你通过 macOS 提供的“隐私与安全性”流程处理。不要关闭 Gatekeeper 或移除隔离标记作为安装捷径。

首次启动不会扫描或移动文件。只有开始扫描时才可能需要 Downloads 访问许可；不需要管理员密码或完全磁盘访问。读取失败会显示为部分结果。

文件整理仅限 Downloads 及下一层目录内至少 30 天未变动的安装包；选择默认空白。确认具体项目后才移入废纸篓，不永久删除、不清空废纸篓，也不卸载应用。移入废纸篓不会立即释放磁盘空间。操作记录支持无覆盖恢复；崩溃后若记录未保存，文件仍在废纸篓的 Alter-UUID.ext 项目中。

Mole V1.55.0 路径与应用保护核心按 GPL-3.0 集成，来源声明和对应源码随版本提供。角色图片权利归原权利人，不属于代码 GPL 授权。
