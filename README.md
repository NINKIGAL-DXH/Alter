<div align="center">
  <img src="Sources/AlterApp/Resources/Brand/Alter.png" width="112" alt="Alter 应用头像">
  <h1>Alter</h1>
  <p><strong>给 Mac，留一点余裕。</strong></p>
  <p>原生 macOS 空间管理与角色陪伴应用 · Mole 保护内核 · Liquid Glass</p>
  <p><a href="https://github.com/NINKIGAL-DXH/Alter/releases">下载 DMG</a> · <a href="#安全边界">安全边界</a> · <a href="#本地构建">本地构建</a> · <a href="THIRD_PARTY_NOTICES.md">第三方声明</a></p>
</div>

> **0.1.0 预览版**：先查看，再决定。默认只读，不自动清理；仅支持把逐项确认的旧安装包移入废纸篓。当前构建为 ad-hoc 签名，尚未获得 Apple Developer ID 签名和公证。

## 这是什么

Alter 把空间检查、受限的安装包整理，以及 23 种角色神情放进一个原生 SwiftUI 应用。设计参考 [Apple 材质指南](https://developer.apple.com/design/human-interface-guidelines/materials)：在导航和操作控件使用 Liquid Glass，内容保持清楚易读。macOS 26 使用原生玻璃 API，旧版系统提供标准材质回退。

角色图片按场景分别呈现；上下蓝色边框、黑边和底部白色横条在显示时逐张裁切，原始参考图保留。磁盘空间与清理页面均有放大的角色画面，应用图标与界面标识使用同一头像。

## 能做什么

| 页面 | 当前功能 |
| --- | --- |
| 总览 | 读取系统磁盘总量与可用容量，提供整理入口 |
| 智能清理 | 查找 Downloads 内至少 30 天未变动的安装包；经 Mole 保护检查、手动选择、再次确认后移入废纸篓 |
| 磁盘空间 | 只读分析你选择的目录，显示较大的文件；支持取消 |
| 应用管理 | 只读统计应用占用，不提供卸载或关联文件删除 |
| Alter 陪伴 | 23 张图片逐一浏览、顺序预览，保留每一种神情 |
| 操作记录 | 记录真实移动，支持恢复到原路径且不覆盖同名文件 |
| 设置 | 跟随系统／月白／夜色，角色显示与首页画面，安全和许可证信息 |

没有后台自动扫描、遥测、在线账户或自动更新。首次启动不会扫描下载目录，更不会移动文件。HTML 设计稿中的数字和清理流程是演示；原生应用显示本地实际元数据。

## 下载与安装

在 [Releases](https://github.com/NINKIGAL-DXH/Alter/releases) 选择对应安装包：

| Mac | 文件 |
| --- | --- |
| Apple Silicon（M 系列） | `Alter-0.1.0-arm64.dmg` |
| Intel | `Alter-0.1.0-x86_64.dmg` |

最低系统版本为 **macOS 14**；原生 Liquid Glass 需要 **macOS 26 或更新版本**。Intel 与 Apple Silicon 在各自的 GitHub macOS runner 上构建和测试。

1. 下载 DMG 与同名 `.sha256` 文件。在下载目录运行 `shasum -a 256 -c Alter-0.1.0-arm64.dmg.sha256`（Intel 请替换架构名）。
2. 打开 DMG，将 `Alter.app` 拖入“应用程序”。
3. 当前版本未公证，macOS 可能阻止打开。确认来源和校验和后，由你通过系统“隐私与安全性”提供的正规流程处理。不要关闭 Gatekeeper 或通过移除隔离标记绕过检查。
4. 扫描下载目录时，系统可能请求该目录的访问许可。不需要管理员密码或“完全磁盘访问权限”；无法读取的路径会跳过并标记。

详见 [安装说明](docs/INSTALL.md)。

## 安全边界

**本版未实现以下操作：** `sudo`／管理员提权、永久删除、清空废纸篓、递归删除、应用卸载、系统优化、服务重启、包管理器清理，以及任意终端命令执行。

唯一能改变用户文件位置的功能，受这些条件限制：

- 只允许当前用户 Downloads 及其下一层目录内的 `.dmg`、`.pkg`、`.iso`、`.xip` 普通文件；文件至少 30 天未变动。
- 初始选择为空。先显示具体项目与路径，再由用户确认；单次最多 **20 项／25 GB**，确认 **5 分钟**后过期。
- Mole 保护规则与白名单在扫描和执行前分别检查。未知结果、校验失败、超时或取消都停止操作。
- 验证所有者、链接数、文件身份和修改时间。逐层打开真实目录，不跟随符号链接，不操作其他用户可写的来源目录。
- 使用同卷、不覆盖的原子重命名移入私有废纸篓。跨卷时拒绝，**没有复制后删除的回退**。
- 恢复时再次验证文件身份和目标路径，拒绝覆盖已有文件。取消后报告实际完成数量。

**移入废纸篓不会立即增加可用磁盘空间。** Alter 不负责清空废纸篓。

安全限制降低误操作风险，并不构成绝对安全保证。同一用户权限的恶意进程仍可能竞争修改文件；移动后、记录落盘前崩溃时，需要到废纸篓手动恢复唯一命名的文件。完整说明见 [安全设计与限制](docs/SAFETY.md)。

## 内存与扫描预算

扫描在单个后台任务中流式遍历，只读取元数据，不读取文件正文，不解压文件，也不把整个目录树装进内存。

| 项目 | 上限／策略 |
| --- | --- |
| 并行扫描 | 1 个任务，可取消 |
| 下载目录 | 10 秒、30,000 个条目、保留 128 个结果、最多下一层目录 |
| 缓存观察 | 12 秒、60,000 个条目、保留 64 个结果；只读 |
| 所选目录 | 20 秒、100,000 个条目、保留 300 个大文件结果 |
| 遍历深度 | 最高 24 层；不跟随符号链接，不跨设备遍历 |
| 图片 | 按显示尺寸缩略解码；20 MB 缓存预算、最多 16 个缓存项；图库懒加载 |
| Mole 子进程 | 每批最多 64 条路径；10 秒超时；8 秒 CPU、128 MiB 采样 RSS、64 文件描述符限制 |
| 恢复记录 | 最多 200 条／256 KiB；达到上限后拒绝新增移动，不丢弃恢复信息 |

系统内存压力通知会取消工作并清空图片缓存。`NSCache` 是驱逐预算，不是整个进程的硬内存上限；文件系统阻塞也可能延迟取消。因此不承诺在所有环境下绝不发生内存耗尽。触及预算或读取失败会标为部分结果。占用估计受 APFS、硬链接、跳过的目录与权限等影响。

## Mole 内核与来源

Alter **实际调用 [tw93/Mole](https://github.com/tw93/Mole) 的路径与应用保护核心**：

- 固定版本：**V1.55.0**
- 固定提交：[`69ab325d4f05af0ea21aeeeae544046c9f04a76b`](https://github.com/tw93/Mole/tree/69ab325d4f05af0ea21aeeeae544046c9f04a76b)
- 许可证：**GPL-3.0**
- 实际调用：`should_protect_path`、`is_path_whitelisted`、`load_mole_whitelist`
- 保留原样的 5 个上游模块及 SHA-256 清单位于 [`Resources/Mole`](Sources/AlterApp/Resources/Mole)。每次运行保护检查前校验上游文件。

Mole 保护核心运行在禁止文件写入和网络访问的 macOS 沙箱子进程中。扫描器、确认流程和可恢复移动由 Alter 的原生适配层实现。**本版并未集成完整 Mole CLI 的清理／卸载／优化命令。**

Alter 是独立衍生项目，不是 Mole 官方 GUI，不是 Mole for Mac，与 Mole 或 Apple 均无官方关联或背书。名称、商标和原作者权利保留。感谢 tw93 与 Mole 贡献者，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

## 本地构建

需要 macOS、Xcode 26 或更新版本（包含相应 Swift SDK）、Python 3。无需第三方 Swift 包。

```bash
git clone https://github.com/NINKIGAL-DXH/Alter.git
cd Alter
python3 scripts/verify.py
swift test --jobs 2
./scripts/build.sh
./scripts/make-dmg.sh
```

输出位于 `dist/`，脚本拒绝覆盖已有 app 或 DMG。重复构建前请先将自己的旧产物移到别处。构建并发限制为 2；只有 Command Line Tools、没有 XCTest 的本机可运行 `python3 scripts/test-local.py` 验证同一批安全测试方法，正式 CI 使用 XCTest。

13 项测试全部在 UUID 命名的临时目录中运行，覆盖近期文件、受保护路径、符号链接、硬链接、遍历预算／取消、文件替换、过期确认、恢复冲突、记录文件符号链接、实际 Mole 保护判断和沙箱写入拒绝。**测试不会扫描或清理真实 Downloads／Library。**

### GitHub 构建

- 普通分支和 PR 工作流保持 `contents: read`，执行资源完整性检查、安全测试、双架构打包与 DMG 校验。
- 只有 `v*` 标签触发的独立发布工作流获得 `contents: write`，向预先创建的 Release 上传 DMG、校验和及对应源码；不会覆盖已有附件。
- 使用 Release 附件分发，避免依赖 Actions 产物存储额度。维护者需先准备草稿 Release，再创建相同版本标签；双架构验证通过、附件齐全后发布。
- 当前为 ad-hoc 签名。生产级 Developer ID 签名与 Apple 公证尚未配置，仓库不包含证书、密码或密钥。

## 项目结构

```text
Sources/AlterApp/        SwiftUI 界面、头像、23 张表情、Mole 资源
Sources/AlterCore/       有界扫描、文件验证、Mole 适配、废纸篓恢复
Tests/AlterCoreTests/    隔离的安全测试
scripts/                资源验证、app 与 DMG 打包
.github/workflows/      只读 CI 与独立标签发布
ui-preview/             原始 HTML 与更新后的玻璃设计稿（演示数据）
docs/                   安装与安全说明
```

## 参与贡献

欢迎提交可复现的问题或小范围改进。报告问题时，请注明 macOS 版本、芯片架构、应用版本和触发步骤；分享日志前移除私人路径及文件名。涉及移动、恢复、路径验证或资源限制的改动，需要补充隔离测试。请勿引入默认勾选、自动清理、永久删除或提权执行。

## 许可证与图片

Alter 代码按 [GNU GPL v3](LICENSE) 开源，保留 Mole 的作者、许可证和来源声明；发行版提供对应源码。

角色截图和头像由项目发起人提供，描绘 Fate 系列的贞德 Alter。**图片、角色、商标等权利归各自权利人，不属于代码 GPL 授权范围；仓库公开不意味着获得这些素材的再分发或商业使用许可。** 本项目不宣称拥有这些素材。如需再分发，可先替换为自己拥有相应授权的素材。权利问题可通过仓库 Issue 联系维护者。
