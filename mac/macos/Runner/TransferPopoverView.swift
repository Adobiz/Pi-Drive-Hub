import SwiftUI
import AppKit

private let downloadColor = Color(red: 0.12, green: 0.55, blue: 0.96)
private let uploadColor = Color(red: 0.94, green: 0.56, blue: 0.18)

struct TransferPopoverView: View {
  @ObservedObject var model: MenuBarModel
  var onAction: (String, MenuBarTask?) -> Void
  private var data: MenuBarSnapshot { model.snapshot }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      speedSummary.padding(.top, 21)
      SpeedHistoryChart(snapshot: data, english: model.english).padding(.top, 18)
      sessionStats.padding(.top, 14)
      Divider().padding(.vertical, 16)
      taskSection
      Spacer(minLength: 8)
      Divider().padding(.bottom, 12)
      HStack {
        Button(action: { onAction("openMain", nil) }) {
          HStack(spacing: 5) {
            Text(model.text("打开主窗口", "Open main window"))
            DashboardIcon(name: "arrow.up.right").font(.system(size: 10, weight: .semibold))
          }.font(.system(size: 12, weight: .medium)).foregroundColor(downloadColor)
        }.buttonStyle(PlainButtonStyle())
        Spacer()
        Button(model.text("传输管理", "Transfers"), action: { onAction("openTransfers", nil) })
          .font(.system(size: 12)).buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)
      }
    }
    .padding(20)
    .frame(width: 400, height: 554)
    .background(Color(NSColor.windowBackgroundColor).opacity(0.92))
  }

  private var header: some View {
    HStack(spacing: 9) {
      Image(nsImage: CloudGlyph.image()).renderingMode(.template)
        .foregroundColor(downloadColor).frame(width: 22, height: 18)
      Text(model.text("传输概览", "Transfers")).font(.system(size: 15, weight: .semibold))
      Spacer()
      Circle().fill(data.active > 0 ? Color.green : Color.secondary.opacity(0.45)).frame(width: 5, height: 5)
      Text(data.active > 0 ? model.text("传输中", "Transferring") : (data.paused > 0 ? model.text("已暂停", "Paused") : model.text("空闲", "Idle")))
        .font(.system(size: 11)).foregroundColor(.secondary)
      Button(action: { onAction("menu", nil) }) {
        DashboardIcon(name: "ellipsis").font(.system(size: 16, weight: .semibold))
          .foregroundColor(.secondary).frame(width: 24, height: 24)
      }.buttonStyle(PlainButtonStyle()).accessibility(label: Text(model.text("更多选项", "More options")))
    }
  }

  private var speedSummary: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 4) {
          DashboardIcon(name: "arrow.down").foregroundColor(downloadColor)
          Text(model.text("下载速率", "Download"))
        }.font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
        Text(transferSize(data.downloadRate, rate: true))
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .transferDigits().lineLimit(1).minimumScaleFactor(0.8)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        HStack(spacing: 4) {
          DashboardIcon(name: "arrow.up").foregroundColor(uploadColor)
          Text(model.text("上传", "Upload"))
        }.font(.system(size: 11)).foregroundColor(.secondary)
        Text(transferSize(data.uploadRate, rate: true))
          .font(.system(size: 17, weight: .medium, design: .rounded)).transferDigits()
      }.padding(.bottom, 3)
    }
  }

  private var sessionStats: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(model.text("本次已下载", "Session download")).font(.system(size: 10)).foregroundColor(.secondary)
        Text(transferSize(data.downloaded)).font(.system(size: 12, weight: .medium)).transferDigits()
      }
      Spacer()
      VStack(alignment: .center, spacing: 4) {
        Text(model.text("本次已上传", "Session upload")).font(.system(size: 10)).foregroundColor(.secondary)
        Text(transferSize(data.uploaded)).font(.system(size: 12, weight: .medium)).transferDigits()
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(model.text("60 秒下载峰值", "60s download peak")).font(.system(size: 10)).foregroundColor(.secondary)
        Text(transferSize(data.peak, rate: true)).font(.system(size: 12, weight: .medium)).transferDigits()
      }
    }
  }

  private var taskSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(model.text("传输任务", "Tasks")).font(.system(size: 12, weight: .semibold))
        Text("\(data.active) " + model.text("进行中", "active") + (data.queued > 0 ? " · \(data.queued) " + model.text("等待", "queued") : ""))
          .font(.system(size: 10)).foregroundColor(.secondary)
        Spacer()
        if data.active + data.queued + data.paused > 0 {
          let shouldPause = data.active + data.queued > 0
          Button(action: { onAction(shouldPause ? "pauseAll" : "resumeAll", nil) }) {
            HStack(spacing: 4) {
              DashboardIcon(name: shouldPause ? "pause.fill" : "play.fill").font(.system(size: 8))
              Text(shouldPause ? model.text("全部暂停", "Pause all") : model.text("全部继续", "Resume all"))
            }.font(.system(size: 10, weight: .medium))
              .padding(.horizontal, 8).padding(.vertical, 5)
              .background(Color.primary.opacity(0.05)).cornerRadius(6)
          }.buttonStyle(PlainButtonStyle())
        }
      }
      if data.tasks.isEmpty {
        VStack(spacing: 7) {
          DashboardIcon(name: "checkmark.circle").font(.system(size: 21, weight: .light)).foregroundColor(.secondary)
          Text(data.completed > 0 ? model.text("所有传输已完成", "All transfers complete") : model.text("暂无进行中的传输", "No active transfers"))
            .font(.system(size: 12, weight: .medium))
          Text(model.text("在主窗口添加文件，进度会显示在这里", "Add files in the main window to get started"))
            .font(.system(size: 10)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).frame(height: 106)
      } else {
        ScrollView(.vertical, showsIndicators: true) {
          VStack(spacing: 0) {
            ForEach(data.tasks) { task in
              TransferTaskRow(task: task, english: model.english, onAction: onAction)
              if task.id != data.tasks.last?.id { Divider().opacity(0.5) }
            }
          }
        }.frame(height: 125)
      }
    }
  }
}

private struct TransferTaskRow: View {
  let task: MenuBarTask
  let english: Bool
  let onAction: (String, MenuBarTask?) -> Void
  private var tint: Color { task.isDownload ? downloadColor : uploadColor }
  private var detail: String {
    let amount = transferSize(task.done) + (task.total.map { " / " + transferSize($0) } ?? "")
    if task.status == "paused" { return (english ? "Paused · " : "已暂停 · ") + amount }
    if task.status == "queued" { return english ? "Waiting to transfer" : "等待传输" }
    if task.status == "failed" { return english ? "Failed · View in transfers" : "传输失败 · 在传输管理中查看" }
    return amount
  }
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      DashboardIcon(name: task.isDownload ? "arrow.down.doc" : "arrow.up.doc")
        .font(.system(size: 17, weight: .light)).foregroundColor(tint)
        .frame(width: 28, height: 32)
        .background(tint.opacity(0.08)).cornerRadius(7)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 5) {
          Button(action: { onAction("openTransfers", task) }) {
            Text(task.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
          }.buttonStyle(PlainButtonStyle())
          Spacer(minLength: 2)
          if task.isRunning {
            Text(transferSize(task.speed, rate: true)).font(.system(size: 10)).transferDigits().foregroundColor(.secondary)
          }
        }
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.07))
            Capsule().fill(task.status == "paused" ? Color.secondary.opacity(0.55) : tint)
              .frame(width: max(0, geometry.size.width * CGFloat(task.progress)))
          }
        }.frame(height: 3)
        HStack {
          Text(task.provider).font(.system(size: 9)).foregroundColor(.secondary)
          Spacer()
          Text(detail).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
        }
      }
      if task.canPause || task.canResume {
        Button(action: { onAction(task.canResume ? "resume" : "pause", task) }) {
          DashboardIcon(name: task.canResume ? "play.fill" : "pause.fill")
            .font(.system(size: 10)).foregroundColor(.secondary).frame(width: 22, height: 30)
        }.buttonStyle(PlainButtonStyle())
          .accessibility(label: Text((task.canResume ? (english ? "Resume " : "继续 ") : (english ? "Pause " : "暂停 ")) + task.name))
      } else {
        DashboardIcon(name: "exclamationmark.circle").foregroundColor(uploadColor).frame(width: 22, height: 30)
      }
    }.padding(.vertical, 9).frame(height: 62)
  }
}

struct SpeedHistoryChart: View {
  let snapshot: MenuBarSnapshot
  let english: Bool
  private var ceiling: Double {
    let peak = snapshot.history.reduce(0.0) { max($0, max($1.download, $1.upload)) }
    if peak == 0 { return 1024 * 1024 }
    let step = pow(10, floor(log10(peak)))
    return ceil(peak * 1.15 / step) * step
  }
  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 10) {
        legend(english ? "Download" : "下载", color: downloadColor)
        legend(english ? "Upload" : "上传", color: uploadColor)
        Spacer()
        Text(transferSize(ceiling, rate: true)).font(.system(size: 9)).transferDigits().foregroundColor(.secondary)
      }
      GeometryReader { geometry in
        ZStack {
          RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.025))
          Path { path in
            for row in 1...3 {
              let y = geometry.size.height * CGFloat(row) / 4
              path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
            }
            for column in 1...3 {
              let x = geometry.size.width * CGFloat(column) / 4
              path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
            }
          }.stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
          curve(in: geometry.size, upload: false, filled: true)
            .fill(LinearGradient(gradient: Gradient(colors: [downloadColor.opacity(0.28), downloadColor.opacity(0.04)]), startPoint: .top, endPoint: .bottom))
          curve(in: geometry.size, upload: true).stroke(uploadColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
          curve(in: geometry.size, upload: false).stroke(downloadColor, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }.clipped().cornerRadius(7)
      }.frame(height: 97)
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(english ? "Transfer speed over the last 60 seconds" : "最近 60 秒的传输速率曲线"))
      HStack {
        Text(english ? "60s ago" : "60 秒前")
        Spacer()
        Text(english ? "Now" : "当前")
      }.font(.system(size: 9)).foregroundColor(.secondary)
    }
  }
  private func legend(_ label: String, color: Color) -> some View {
    HStack(spacing: 4) { Circle().fill(color).frame(width: 4, height: 4); Text(label).font(.system(size: 9)) }.foregroundColor(.secondary)
  }
  private func curve(in size: CGSize, upload: Bool, filled: Bool = false) -> Path {
    var path = Path()
    let start = snapshot.timestamp - 60000
    path.move(to: CGPoint(x: 0, y: size.height))
    for point in snapshot.history where point.time >= start && point.time <= snapshot.timestamp {
      let x = CGFloat((point.time - start) / 60000) * size.width
      let y = size.height * CGFloat(1 - min(1, (upload ? point.upload : point.download) / ceiling))
      path.addLine(to: CGPoint(x: x, y: y))
    }
    if filled { path.addLine(to: CGPoint(x: size.width, y: size.height)); path.closeSubpath() }
    return path
  }
}

#if DEBUG
struct TransferPopoverView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      TransferPopoverView(model: .preview(), onAction: { _, _ in }).previewDisplayName("Active transfers")
      TransferPopoverView(model: .preview(empty: true), onAction: { _, _ in }).previewDisplayName("Idle")
      TransferPopoverView(model: .preview(), onAction: { _, _ in }).environment(\.colorScheme, .dark).previewDisplayName("Dark")
    }
  }
}
#endif

// Keep the existing 10.15 deployment target; use symbols where supported.
private struct DashboardIcon: View {
  let name: String
  @ViewBuilder var body: some View {
    if #available(macOS 11, *) {
      Image(systemName: name)
    } else {
      Text(["arrow.down": "↓", "arrow.up": "↑", "arrow.up.right": "↗",
            "ellipsis": "⋯", "pause.fill": "Ⅱ", "play.fill": "▶",
            "checkmark.circle": "✓", "arrow.down.doc": "↓", "arrow.up.doc": "↑",
            "exclamationmark.circle": "!"][name] ?? "•")
    }
  }
}
private extension View {
  @ViewBuilder func transferDigits() -> some View {
    if #available(macOS 12, *) { self.monospacedDigit() } else { self }
  }
}
