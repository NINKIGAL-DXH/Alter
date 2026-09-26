import SwiftUI
import AppKit
import AlterCore

struct AlterMenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { BrandImage(size:34); Text("Alter").font(.title2); Spacer(); Button { openWindow(id:"main"); NSApp.activate() } label: { Image(systemName:"arrow.up.forward.square") }.buttonStyle(.plain).help("打开 Alter") }
            if let status = model.systemStatus {
                HStack { metric("CPU",String(format:"%.0f%%",status.cpu)); Spacer(); metric("内存",String(format:"%.0f%%",status.memory)); Spacer(); metric("可用空间",byteText(model.freeCapacity)) }
                Text("内存压力：" + status.pressure).font(.caption).foregroundStyle(.secondary)
                if let date = model.statusDate { Text("采样于 " + date.formatted(date:.omitted,time:.standard)).font(.caption2).foregroundStyle(.secondary) }
            } else { Text("打开时按需采样系统状态。没有模拟数据。").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack { Button("刷新") { model.refreshCapacity(); model.refreshStatus() }.disabled(model.busy); Spacer(); Button("空间透镜") { model.page = .storage; openWindow(id:"main"); NSApp.activate() } }
            if model.busy { HStack { ProgressView().controlSize(.mini); Text(model.activity).font(.caption).lineLimit(2) } }
        }.padding(20).frame(width:340)
            .task { if !model.busy && (model.statusDate == nil || Date().timeIntervalSince(model.statusDate!) > 30) { model.refreshStatus() } }
    }
    private func metric(_ name: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:7) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit() }
    }
}
