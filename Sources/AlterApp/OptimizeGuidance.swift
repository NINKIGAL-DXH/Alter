import SwiftUI
import AlterCore

extension OptimizeTask {
    var guidance: (when: String, effect: String, recovery: String) {
        switch id {
        case "system_maintenance", "network_optimization":
            return ("域名解析异常或 DNS 缓存过期时。", "刷新解析缓存；需要权限的部分由你授权，网络服务可能短暂重启。", "缓存会自动重建；不能恢复旧 DNS 缓存。")
        case "cache_refresh":
            return ("Finder 缩略图或应用图标显示异常时。", "刷新 Quick Look 与图标缓存；首次加载缩略图可能变慢。", "缓存由 macOS 按需重建。")
        case "sqlite_vacuum":
            return ("Mail、Safari、Messages 已退出，数据库有可回收空页时。", "先检查进程、数据库完整性及空页比例，再压缩；上游跳过超过 100 MB 的数据库。", "数据库事务保护由 SQLite 提供；重要数据应已有备份，不承诺加速。")
        case "launch_services_rebuild":
            return ("打开方式菜单重复或文件关联失效时。", "重建 LaunchServices 注册信息，部分打开方式需要重新学习。", "重新选择默认打开应用；不提供数据库一键回滚。")
        case "network_stack_optimize":
            return ("排查路由或 ARP 异常时；不是日常加速按钮。", "刷新路由与 ARP，可能中断 VPN、SSH、下载和其他连接。", "系统重新学习路由；必要时重连网络或 VPN。")
        case "disk_permissions_repair":
            return ("确认当前用户目录存在权限异常时。", "调用 macOS 用户权限修复，可能改变自定义权限；需要管理员授权。", "自定义权限需从备份或原配置恢复。")
        case "spotlight_index_optimize":
            return ("搜索结果持续缺失或索引异常时。", "根据 Mole 检测结果重建 Spotlight；期间 CPU、磁盘活动增加。", "等待系统完成重建；期间搜索结果可能不完整。")
        case "prevent_network_dsstore":
            return ("不希望 Finder 在网络与 USB 卷写入 .DS_Store 时。", "修改当前用户 Finder 偏好；不删除已有 .DS_Store。", "删除对应偏好可恢复系统默认行为。")
        case "legacy_overrides_audit":
            return ("曾使用旧式调优工具，想恢复系统默认保护时。", "清除禁用 App Nap、跳过磁盘镜像验证等遗留覆盖设置。", "恢复系统默认；不会关闭 Gatekeeper 或 SIP。")
        case "periodic_maintenance":
            return ("Mole 检查发现系统周期维护记录过期时。", "调用系统提供的 daily / weekly / monthly 维护；不存在则跳过。", "由系统维护脚本决定改动；不是可撤销的文件移动。")
        case "login_items_audit":
            return ("希望了解多余或失效登录项时。", "审计登录项；具体启停请到“启动项”页面或系统设置。", "只读审计不需要恢复。")
        case "disk_verify":
            return ("怀疑文件系统异常时，优先使用系统磁盘工具。", "保留 Mole 默认跳过规则，避免已知不可及时取消的内核 I/O。", "没有执行磁盘修复，也不会把跳过显示为成功。")
        case "quarantine_cleanup":
            return ("明确希望删除下载来源历史记录时。", "清理 LaunchServices 下载历史数据库；不移除文件隔离标记，不等于性能提升。", "此历史删除不可从废纸篓恢复。")
        case "saved_state_cleanup":
            return ("旧应用窗口恢复状态占用空间或发生异常时。", "移除 30 天以上的保存状态；可能失去窗口恢复信息。", "重新打开应用生成状态；原会话信息不保证可恢复。")
        case "fix_broken_configs", "shared_file_list_repair":
            return ("偏好配置、Finder 收藏或最近文稿确实损坏时。", "按 Mole 规则检查并修复损坏的配置，部分偏好可能重置。", "需要原偏好或备份才能恢复个性化设置。")
        case "launch_agents_cleanup":
            return ("启动项指向已不存在的可执行文件时。", "清理符合上游规则的失效 LaunchAgent；先查看预检结果。", "重新安装所属应用可重建启动项；不能从 Alter 操作记录撤销。")
        case "spotlight_orphan_rules_cleanup":
            return ("Spotlight 保留已卸载应用的搜索规则时。", "仅修剪失效规则，保留仍然有效的搜索配置。", "需要时在 Spotlight 设置中重新配置。")
        case "notification_cleanup", "coreduet_cleanup":
            return ("希望整理旧通知或历史使用记录时。", "删除符合上游年龄规则的历史记录；不会释放正在使用的内存。", "历史删除不可撤销，不能当作必需的性能优化。")
        default: return ("先检查，再决定是否有必要。", detail, "以任务预检输出为准。")
        }
    }
}
struct OptimizeAdvice: View {
    let task: OptimizeTask
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("适用：" + task.guidance.when)
            Text("改动：" + task.guidance.effect)
            Text("恢复：" + task.guidance.recovery)
        }.font(.system(size:12)).lineSpacing(3)
    }
}
