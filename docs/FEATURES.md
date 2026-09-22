# Mole 功能矩阵 — Alter 0.2

“七个主要模块接入”指每个页面使用真实上游模块，不代表把所有 CLI 选项、提权路径和删除脚本原样暴露给用户。

| Mole 功能 | Alter 接入 | 保留限制 |
| --- | --- | --- |
| `clean` | 完整用户清理 dry-run、实际 ledger、保护与白名单复核、逐项移动废纸篓 | root 系统清理、直接执行外部包管理器清理、清空废纸篓与快照删除未开放；日志中的“would clean”不一定对应可移动候选 |
| `uninstall` | 应用占用、真实关联数据发现、共享数据保护、选项预览、可恢复移动 | 不强杀进程，不自动运行厂商卸载器或 brew cask 卸载脚本；需要这类卸载的应用明确提示 |
| `optimize` | 上游 21 个 handler 的目录与逐项预检；单项用户权限执行、可选终端管理员授权 | 不一键批量维护；磁盘验证保持上游默认禁用；部分任务因白名单/条件/权限跳过；管理员路径未做真实维护实测 |
| `analyze` | 真实 Go JSON；圆形 Space Lens、按面积占用、列表联动、下钻/返回、路径输入、隐藏与小文件、搜索分页 | OS 权限继续生效；系统目录只读；有输出/时间/内存预算；未照搬 CLI TUI 的全部快捷键和偏好 |
| `status` | 真实 Go JSON，主指标卡片和完整原始指标，可选 10 秒刷新 | 不是永久后台进程告警服务；不支持的传感器以原始返回为准 |
| `purge` | 指定项目根目录，使用上游项目产物识别，执行前重新发现、流式内容复核、移到废纸篓 | 不删除源代码，不运行 package-manager scripts；最近使用的产物可能由上游规则保留 |
| `installer` | 上游安装包搜索范围、扩展名与归档识别，逐项确认移动 | 不是任意压缩包清理；不绕过隐私权限，不永久删除 |
| 白名单 | 清理与维护读取已有 Mole 白名单 | 暂无 GUI 编辑器，预览不创建/迁移配置 |
| CLI 自更新/卸载/补全/Touch ID | 来源、版本与授权声明保留；Alter 由自身 Release 分发 | 不操作用户原有 Mole 安装、shell 配置、PAM 或系统认证设置 |

## 21 项维护目录

| 上游 ID | 具体作用 |
| --- | --- |
| `system_maintenance` | DNS 缓存刷新、Spotlight 状态检查 |
| `cache_refresh` | QuickLook 缩略图与图标缓存刷新 |
| `saved_state_cleanup` | 清理超过 30 天的应用保存状态 |
| `fix_broken_configs` | 检查并修复损坏的偏好配置 |
| `network_optimization` | DNS 缓存与 mDNSResponder 刷新 |
| `sqlite_vacuum` | Mail、Safari、Messages 等数据库压缩；保留运行中应用等上游保护 |
| `launch_services_rebuild` | 重建“打开方式”和文件关联 |
| `prevent_network_dsstore` | 修改 Finder 对网络/外接卷 `.DS_Store` 的持久偏好 |
| `legacy_overrides_audit` | 检查并移除旧工具留下的 App Nap/磁盘镜像验证覆盖设置 |
| `network_stack_optimize` | 按上游条件刷新路由和 ARP，可能短暂影响网络 |
| `disk_permissions_repair` | 修复用户目录权限问题 |
| `spotlight_index_optimize` | 按检测结果重建 Spotlight 索引 |
| `spotlight_orphan_rules_cleanup` | 清理已卸载应用的 Spotlight 搜索规则 |
| `periodic_maintenance` | 按条件运行 macOS 日/周/月维护脚本 |
| `shared_file_list_repair` | 修复损坏的收藏和最近文稿列表 |
| `disk_verify` | 文件系统验证；在 Alter 中保持上游默认禁用，返回 skipped |
| `login_items_audit` | 审计损坏登录项 |
| `quarantine_cleanup` | 清理 Gatekeeper 下载历史数据库，不等于关闭 Gatekeeper |
| `launch_agents_cleanup` | 清理目标程序已不存在的 LaunchAgent |
| `notification_cleanup` | 清理旧通知记录 |
| `coreduet_cleanup` | 清理旧使用记录 |

维护预检结果可能是“无需操作”“条件未满足”或“无法访问”，不一定产生可执行变更。每项都需要单独确认；取消并不撤销已发生的维护。完整风险与验证范围见 [安全说明](SAFETY.md)。
