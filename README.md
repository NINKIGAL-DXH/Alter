<div align="center">
  <img src="Sources/AlterApp/Resources/Brand/Alter.png" width="112" alt="Alter 应用头像">
  <h1>Alter</h1>
  <p><strong>给 Mac，留一点余裕。</strong></p>
  <p>原生 macOS 空间管理与角色陪伴应用 · Mole 内核 · Liquid Glass</p>
  <p><a href="https://github.com/NINKIGAL-DXH/Alter/releases">下载 DMG</a> · <a href="docs/FEATURES.md">功能与限制</a> · <a href="docs/SAFETY.md">安全设计</a> · <a href="THIRD_PARTY_NOTICES.md">第三方声明</a></p>
</div>

> **0.2.0 预览版**接入 Mole 的七个主要功能模块。扫描与预览只读，文件操作逐项选择、复核、确认后移入废纸篓；系统维护单独确认。受保护的系统删除、厂商卸载器和 Homebrew 卸载脚本仍有限制，不能视为完整复刻所有 CLI 行为。当前为 ad-hoc 签名，尚未获得 Developer ID 签名和 Apple 公证。

## 这是什么

Alter 使用真实的 [tw93/Mole](https://github.com/tw93/Mole) 内核，提供中文原生 SwiftUI 界面。Mole 固定在 **V1.55.0 / 69ab325d4f05af0ea21aeeeae544046c9f04a76b**，按 GPL-3.0 集成；不依赖你另行安装 Mole，也不会在启动时下载安装脚本。

界面参考 [Apple 材质指南](https://developer.apple.com/design/human-interface-guidelines/materials)，macOS 26 使用原生 Clear Liquid Glass 和窗口背后的系统材质，旧系统提供轻薄材质回退，并遵循“减少透明度”和“减少动态效果”。空间透镜参考 [CleanMyMac Space Lens](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results) 的面积与占用对应、圆形下钻及列表联动；圆形布局由 Alter 自行实现。

23 张角色图按页面和状态呈现，也可在陪伴页逐张浏览。上下蓝边、黑边和底部白条按图裁切，原始文件保留；应用头像与界面标识使用同一张用户提供的画像。

## 功能

| 模块 | 实际内核与行为 |
| --- | --- |
| 智能清理 `clean` | 调用 Mole 完整用户清理流程的 dry-run，提取缓存、日志、开发工具等候选清单；展开查看扫描日志与跳过原因。选中项目经第二次保护检查后移入废纸篓 |
| 应用管理 `uninstall` | Mole 发现应用、关联数据与仍在使用共享数据的其他应用；显示具体文件，再选择卸载范围。运行中的应用需先退出，Alter 不强制结束应用 |
| 系统维护 `optimize` | 读取上游全部 **21 项**维护目录，逐项运行真实预检；每次只执行一个已确认的 handler，明确区分 applied、unchanged、skipped、failed。管理员部分通过用户打开的终端授权 |
| 空间透镜 `analyze` | 真实 Go 分析器，圆面积对应字节数，支持隐藏项目、包目录、小文件、下钻、前进/后退、祖先路径、搜索和分页；支持文件选择器或直接输入路径 |
| 系统状态 `status` | 真实 Go 状态采样：CPU、内存、磁盘、网络、电池、进程及原始传感器数据；可选 10 秒刷新，仅在此页生效 |
| 项目产物 `purge` | 使用 Mole 的项目识别规则查找依赖和构建产物；选根目录或输入路径，执行前重新识别并核对目录内容 |
| 安装包 `installer` | 使用 Mole 的安装包扫描和识别规则，包括受支持的归档识别；不再限于旧版的 Downloads 下一层或 30 天门槛 |
| 操作记录 | 保存真实的文件移动，支持无覆盖恢复；达到记录预算后停止新增移动 |

没有遥测、在线账户、后台自动清理或内核自动更新。启动不会扫描用户目录。旧 HTML 设计稿使用演示数据；原生应用显示真实本地结果。

**重要区别：** 文件整理移动到废纸篓，可恢复，但不会立即释放磁盘空间；维护可能改设置、重建数据库、清理历史记录或重启服务，不能一键撤销。两类操作有独立确认界面。

### 保留的边界

- 系统及其他受保护目录可以只读分析，权限仍由 macOS 决定；不会通过提权删除这些目录。不可访问内容可能不计入统计。
- 文件选择初始为空，每批最多 64 项，确认 5 分钟过期；不提供“一键执行所有维护”。
- 厂商专用卸载器、后台服务卸载和 Homebrew cask 脚本不自动运行。Homebrew 应用移动到废纸篓**不等于移除 cask 收据**，界面会提示。
- `disk_verify` 保留 Mole 的默认禁用：上游注明 APFS 异常时 `verifyVolume` 可能引起无法及时中止的内核 I/O。该项可查看预检，返回 skipped，不伪报完成。
- Mole 的 CLI 自更新、自卸载、Touch ID/PAM 配置、shell 补全和交互式白名单编辑没有移植为 Alter 按钮。已有 Mole 白名单会被读取，扫描不写配置。
- 不提供清空废纸篓、任意命令输入或关闭 Gatekeeper 的操作。完整范围见 [功能矩阵](docs/FEATURES.md)。

## 安装

最低 **macOS 14**，原生 Liquid Glass 需要 **macOS 26**。到 [Releases](https://github.com/NINKIGAL-DXH/Alter/releases) 选择：

| 芯片 | DMG |
| --- | --- |
| Apple Silicon | `Alter-0.2.0-arm64.dmg` |
| Intel | `Alter-0.2.0-x86_64.dmg` |

同时下载 `.sha256`，在下载目录运行 `shasum -a 256 -c Alter-0.2.0-arm64.dmg.sha256`（Intel 替换架构名），再将 DMG 中的 `Alter.app` 拖入应用程序。未公证版本可能被 macOS 阻止；核实来源后使用系统“隐私与安全性”的正规流程，不要关闭 Gatekeeper 或移除隔离标记。

扫描桌面、文稿、下载或其他受保护目录时，macOS 可能要求相应访问许可。空间透镜提供隐私设置入口，但不会自动授予完全磁盘访问。普通扫描和文件移动不需要管理员密码；系统维护中只有你选择“在终端授权此项”才会请求授权。详见 [安装说明](docs/INSTALL.md)。

## 安全与资源预算

预览工作进程禁止网络与私有任务目录之外的写入。macOS 禁止沙盒内执行 `ps`，因此 Alter 在沙盒外用固定参数读取一份有界进程快照，再交给上游解析和保护规则；快照仅存于本次私有临时目录，用完删除，不记录或上传。无法取得快照时停止，绝不把未知状态当作应用空闲。

选中项目使用文件描述符逐层检查，不跟随父路径符号链接。目录内容用流式元数据指纹复核，改变后需重新预览。实际移动使用同卷、不覆盖的 `renameatx_np(RENAME_EXCL)`；跨卷或权限不足就保留原文件，没有复制后删除回退。卸载和项目产物在执行前重新运行 Mole 发现规则。

| 项目 | 预算 |
| --- | --- |
| 工作任务 | 同时 1 个，可取消；内存压力触发取消与图片缓存驱逐 |
| 工作进程组 | 每 0.5 秒采样，约 512 MiB RSS、最多 64 个进程；Go 软内存目标 256 MiB、并行度 2 |
| 结果输出 | stdout/stderr 各最多 8 MiB；候选最多 5,000 个，分析直接子项最多 50,000 个 |
| 时间 | 分析/发现 900 秒；状态内核 60 秒；固定进程快照每次 10 秒；维护 600 秒 |
| 文件复核 | 每项最多 400,000 个对象、128 层、120 秒；只读元数据 |
| 空间透镜 | 最多 22 个单独圆 + 1 个合并圆；完整直接子项列表每页 100 个 |
| 图片 | 缩略解码，20 MB 缓存预算、最多 16 个缓存项；23 张图懒加载 |
| 恢复记录 | 200 条 / 256 KiB；不覆盖旧记录来继续操作 |

Mole 的部分规则需要读取归档目录或配置内容，并非所有扫描都只看元数据。预算是保护机制，不是绝对 OOM 保证；内核 I/O、不可观测的特权子进程及 UI 框架的内存不能被这些预算严格约束。中途取消维护也可能已经产生部分改变。更多限制见 [SAFETY.md](docs/SAFETY.md)。

## 内核来源与开源

- 上游：[tw93/Mole V1.55.0 固定提交](https://github.com/tw93/Mole/tree/69ab325d4f05af0ea21aeeeae544046c9f04a76b)
- [`Vendor/Mole`](Vendor/Mole) 保存 118 个上游文件及 SHA-256 清单，原文件保持不变。旧版纯保护核心另行保留，用于兼容测试。
- [`scripts/build-mole.py`](scripts/build-mole.py) 在临时构建副本中应用两处透明补丁：分析缓存改到私有任务目录；状态进程查询读取原生快照。解析、发现、保护与维护规则来自 Mole。
- 预览适配器禁止写入，卸载时仅适配只读沙盒中的权限预检；真正移动由独立原生检查执行。此适配不授权任何上游批量删除入口。
- Go 与实际链接模块的许可证随 app 提供，版本记录在 `Kernel/licenses/modules.json`。每个 Release 提供对应源码。

Alter 是独立衍生项目，**不是 Mole 官方 GUI、不是 Mole for Mac**，没有 Mole、Apple 或 MacPaw 的官方关联或背书。Mole 的作者与商标权利保留。详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

## 本地构建

需要 macOS、Xcode 26+ 或相应 Command Line Tools、Python 3、Go 1.27.1。Go 模块首次构建需联网，版本由上游 `go.mod` / `go.sum` 固定。

```bash
git clone https://github.com/NINKIGAL-DXH/Alter.git
cd Alter
python3 scripts/verify.py
python3 scripts/build-mole.py
python3 scripts/prepare-test-resources.py
swift test --jobs 2
./scripts/build.sh
./scripts/make-dmg.sh
```

仅安装 CLT、没有 XCTest 时，用 `python3 scripts/test-local.py` 执行同一批测试方法。可用 `ALTER_GO` 指定 Go 路径、`ALTER_ARCH=arm64` 或 `x86_64` 选择架构、`ALTER_VERSION` 指定版本。app 输出到 `dist/<版本>/<架构>/Alter.app`；DMG 输出到 `dist/`。脚本拒绝覆盖已有 app/DMG。

25 项测试覆盖真实内核预览、隐藏/小文件与包目录、状态采样、运行中缓存保护、进程超时/输出预算、链接与受保护路径、过期/变化计划、目录移动恢复、覆盖冲突、沙盒写入拒绝以及圆面积比例和非重叠布局。文件移动、卸载和恢复只对 UUID 临时夹具执行；状态和部分上游诊断会读取当前系统元数据，测试不执行真实维护。

### GitHub 发布

普通分支和 PR 的 CI 使用 `contents: read`，Apple Silicon 与 Intel runner 分别跑测试、打包、签名和 DMG 校验。只有 `v*` 标签发布任务取得已授权的 `contents: write`，上传到预先准备的 Release。附件上传不覆盖旧附件；双架构成功、DMG/SHA-256/源码齐全后发布草稿。当前没有 Developer ID 证书、Apple 公证或自动更新；仓库不包含凭据。

## 贡献与许可证

欢迎提交可复现的问题或小范围改进。请写明 macOS、架构、版本和操作步骤，分享日志前移除私人路径与进程信息。涉及文件移动、维护、权限或预算的改动，需补充隔离验证；不要在真实用户目录运行破坏性测试。

Alter 代码按 [GNU GPL v3](LICENSE) 开源。角色截图和头像由项目发起人提供，描绘 Fate 系列的贞德 Alter；**图片、角色、商标等权利归各自权利人，不属于代码 GPL 授权范围**。公开仓库不构成这些素材的再分发或商业授权；重新分发前请确认素材权利或替换为有授权的图片。
