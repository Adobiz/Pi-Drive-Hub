import AppKit
import SwiftUI

struct TransferRatePoint {
  let time: Double
  let download: Double
  let upload: Double
}

struct MenuBarTask: Identifiable {
  let windowID: Int64
  let rawID: String
  let kind: String
  let name: String
  let provider: String
  let status: String
  let done: Double
  let total: Double?
  let speed: Double
  var id: String { "\(windowID):\(kind):\(rawID)" }
  var isDownload: Bool { kind == "download" }
  var isRunning: Bool { status == "downloading" || status == "uploading" }
  var canPause: Bool { isRunning || status == "queued" }
  var canResume: Bool { status == "paused" }
  var progress: Double { guard let total = total, total > 0 else { return 0 }; return min(1, max(0, done / total)) }

  init(_ value: [String: Any], windowID: Int64 = 0) {
    self.windowID = windowID
    rawID = value["id"] as? String ?? ""
    kind = value["kind"] as? String ?? "download"
    name = value["name"] as? String ?? ""
    provider = value["provider"] as? String ?? ""
    status = value["status"] as? String ?? "queued"
    done = MenuBarSnapshot.number(value["done"])
    total = (value["total"] as? NSNumber).map { max(0, $0.doubleValue) }
    speed = MenuBarSnapshot.number(value["speed"])
  }
}

struct MenuBarSnapshot {
  let timestamp: Double
  let downloadRate: Double
  let uploadRate: Double
  let downloaded: Double
  let uploaded: Double
  let peak: Double
  let active: Int
  let queued: Int
  let paused: Int
  let failed: Int
  let completed: Int
  let tasks: [MenuBarTask]
  let history: [TransferRatePoint]

  static func number(_ value: Any?) -> Double {
    let number = (value as? NSNumber)?.doubleValue ?? 0
    return number.isFinite ? max(0, number) : 0
  }
  init(_ value: [String: Any] = [:], windowID: Int64 = 0) {
    timestamp = (value["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
    downloadRate = Self.number(value["downloadRate"])
    uploadRate = Self.number(value["uploadRate"])
    downloaded = Self.number(value["downloaded"])
    uploaded = Self.number(value["uploaded"])
    peak = Self.number(value["peak"])
    active = Int(Self.number(value["active"]))
    queued = Int(Self.number(value["queued"]))
    paused = Int(Self.number(value["paused"]))
    failed = Int(Self.number(value["failed"]))
    completed = Int(Self.number(value["completed"]))
    tasks = (value["tasks"] as? [[String: Any]] ?? []).prefix(12).map { MenuBarTask($0, windowID: windowID) }
    history = (value["history"] as? [[String: Any]] ?? []).suffix(61).map {
      TransferRatePoint(time: Self.number($0["time"]), download: Self.number($0["download"]), upload: Self.number($0["upload"]))
    }
  }
  init(sources: [MenuBarSnapshot], time: Double, history: [TransferRatePoint],
       downloaded: Double, uploaded: Double, completed: Int) {
    timestamp = time
    downloadRate = sources.reduce(0) { $0 + $1.downloadRate }
    uploadRate = sources.reduce(0) { $0 + $1.uploadRate }
    self.downloaded = downloaded; self.uploaded = uploaded; self.completed = completed
    peak = history.map { $0.download }.max() ?? 0
    active = sources.reduce(0) { $0 + $1.active }; queued = sources.reduce(0) { $0 + $1.queued }
    paused = sources.reduce(0) { $0 + $1.paused }; failed = sources.reduce(0) { $0 + $1.failed }
    func rank(_ task: MenuBarTask) -> Int { task.isRunning ? 0 : task.status == "queued" ? 1 : task.status == "paused" ? 2 : 3 }
    tasks = Array(sources.flatMap { $0.tasks }.sorted { rank($0) < rank($1) }.prefix(36))
    self.history = history
  }

}

final class MenuBarModel: ObservableObject {
  @Published var snapshot = MenuBarSnapshot()
  @Published var english = false
  func text(_ zh: String, _ en: String) -> String { english ? en : zh }
}

func transferSize(_ bytes: Double, rate: Bool = false) -> String {
  let suffix = rate ? "/s" : ""
  if bytes < 1024 { return String(format: "%.0f B%@", bytes, suffix) }
  if bytes < 1024 * 1024 { return String(format: "%.1f KB%@", bytes / 1024, suffix) }
  if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB%@", bytes / 1024 / 1024, suffix) }
  return String(format: "%.2f GB%@", bytes / 1024 / 1024 / 1024, suffix)
}

/// A single continuous outline; shared by the status image and dashboard mark.
enum CloudGlyph {
  static func path(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 28, y: 64))
    path.addLine(to: CGPoint(x: 76, y: 64))
    path.addCurve(to: CGPoint(x: 94, y: 46), control1: CGPoint(x: 86, y: 64), control2: CGPoint(x: 94, y: 56))
    path.addCurve(to: CGPoint(x: 81, y: 29), control1: CGPoint(x: 94, y: 36), control2: CGPoint(x: 88, y: 29))
    path.addCurve(to: CGPoint(x: 77, y: 25), control1: CGPoint(x: 79, y: 29), control2: CGPoint(x: 77.5, y: 27))
    path.addCurve(to: CGPoint(x: 54, y: 8), control1: CGPoint(x: 74, y: 14), control2: CGPoint(x: 66, y: 8))
    path.addCurve(to: CGPoint(x: 31, y: 25), control1: CGPoint(x: 42, y: 8), control2: CGPoint(x: 34, y: 14))
    path.addCurve(to: CGPoint(x: 27, y: 29), control1: CGPoint(x: 30.5, y: 27), control2: CGPoint(x: 29, y: 29))
    path.addCurve(to: CGPoint(x: 12, y: 46), control1: CGPoint(x: 19, y: 29), control2: CGPoint(x: 12, y: 36))
    path.addCurve(to: CGPoint(x: 28, y: 64), control1: CGPoint(x: 12, y: 56), control2: CGPoint(x: 18, y: 64))
    path.closeSubpath()
    var transform = CGAffineTransform(a: rect.width / 100, b: 0, c: 0, d: rect.height / 72,
                                     tx: rect.minX, ty: rect.minY)
    return path.copy(using: &transform)!
  }
  static func image() -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.addPath(path(in: rect.insetBy(dx: 0.5, dy: 0.5)))
      context.setStrokeColor(NSColor.black.cgColor)
      context.setLineWidth(1.5)
      context.setLineJoin(.round)
      context.setLineCap(.round)
      context.strokePath()
      return true
    }
    image.isTemplate = true
    return image
  }
}

#if DEBUG
extension MenuBarModel {
  static func preview(empty: Bool = false) -> MenuBarModel {
    let model = MenuBarModel()
    if empty { return model }
    let now = Date().timeIntervalSince1970 * 1000
    let mb = 1024.0 * 1024
    let history: [[String: Any]] = (0..<61).map { index in
      let down = index < 8 ? 0 : (8.5 + 4.2 * sin(Double(index) / 6) + 1.2 * sin(Double(index) * 1.9)) * mb
      return ["time": now - Double(60 - index) * 1000, "download": max(0, down), "upload": (1.4 + sin(Double(index) / 7) * 0.8) * mb]
    }
    model.snapshot = MenuBarSnapshot([
      "timestamp": now, "downloadRate": 12.4 * mb, "uploadRate": 2.1 * mb,
      "downloaded": 3.24 * 1024 * mb, "uploaded": 526 * mb, "peak": 14.7 * mb,
      "active": 2, "queued": 0, "paused": 1, "tasks": [
        ["id": "one", "kind": "download", "name": "设计资源与项目归档.zip", "provider": "百度网盘", "status": "downloading", "done": 1.62 * 1024 * mb, "total": 2.4 * 1024 * mb, "speed": 12.4 * mb],
        ["id": "two", "kind": "upload", "name": "周末的旅行.mov", "provider": "夸克网盘", "status": "uploading", "done": 240 * mb, "total": 890 * mb, "speed": 2.1 * mb],
        ["id": "three", "kind": "download", "name": "参考资料.pdf", "provider": "123云盘", "status": "paused", "done": 36 * mb, "total": 128 * mb, "speed": 0],
      ], "history": history,
    ])
    return model
  }
}
#endif
