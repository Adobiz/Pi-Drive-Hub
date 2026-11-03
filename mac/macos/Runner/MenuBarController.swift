import AppKit
import FlutterMacOS
import SwiftUI

/// One channel per engine; one native status item for the entire application.
final class MenuBarController {
  private let channel: FlutterMethodChannel
  let windowID: Int64
  init(messenger: FlutterBinaryMessenger, windowID: Int64 = 0) {
    self.windowID = windowID
    channel = FlutterMethodChannel(name: "pi_drive_hub/menu_bar", binaryMessenger: messenger)
    DesktopWindows.shared.register(self, id: windowID)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let values = call.arguments as? [String: Any] ?? [:]
      let requested = (values["viewId"] as? NSNumber)?.int64Value ?? self.windowID
      switch call.method {
      case "configure":
        let english = values["language"] as? String == "en"
        TransferMenuBarHub.shared.configure(english: english)
        DesktopWindows.shared.installCommands(english: english)
        result(self.windowID)
      case "update":
        TransferMenuBarHub.shared.update(self.windowID, values: values)
        DesktopWindows.shared.releaseIfIdle(self.windowID)
        result(nil)
      case "workspaceReady":
        DesktopWindows.shared.markReady(requested, tabs: (values["tabs"] as? NSNumber)?.intValue ?? 1)
        result(nil)
      case "newWindow": result(DesktopWindows.shared.newWindow())
      case "showWindow": result(DesktopWindows.shared.show(requested))
      case "closeWindow": DesktopWindows.shared.close(requested); result(nil)
      case "hideWindow": DesktopWindows.shared.hide(self.windowID); result(nil)
      case "setWindowTitle":
        if let title = values["title"] as? String { DesktopWindows.shared.setTitle(requested, title) }
        result(nil)
      case "toggle": TransferMenuBarHub.shared.togglePopover(); result(nil)
      case "destroy": TransferMenuBarHub.shared.destroy(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func send(_ action: String, task: MenuBarTask? = nil, completion: ((Any?) -> Void)? = nil) {
    var arguments: [String: Any] = ["action": action, "viewId": windowID]
    if let task = task { arguments["id"] = task.rawID; arguments["kind"] = task.kind }
    channel.invokeMethod("action", arguments: arguments, result: completion)
  }
}

/// Rates and session totals are aggregated across windows, not drawn from
/// whichever window happened to receive focus most recently.
final class TransferMenuBarHub: NSObject, NSPopoverDelegate {
  static let shared = TransferMenuBarHub()
  private let model = MenuBarModel()
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var snapshots: [Int64: MenuBarSnapshot] = [:]
  private var arrivals: [Int64: Date] = [:]
  private var previous: [Int64: (Double, Double, Int)] = [:]
  private var downloaded = 0.0
  private var uploaded = 0.0
  private var completed = 0
  private var history: [TransferRatePoint] = []
  private var timer: Timer?

  private override init() {
    super.init()
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 400, height: 554)
    popover.delegate = self
    popover.contentViewController = NSHostingController(rootView:
      TransferPopoverView(model: model) { [weak self] action, task in
        self?.perform(action, task: task)
      })
  }
  var snapshot: MenuBarSnapshot { model.snapshot }
  func source(_ id: Int64) -> MenuBarSnapshot? { snapshots[id] }
  func configure(english: Bool) {
    model.english = english
    if timer == nil {
      let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
      RunLoop.main.add(tick, forMode: .common); timer = tick
    }
    #if DEBUG
    if ProcessInfo.processInfo.environment["PI_WORKSPACE_SMOKE"] == "1" { return }
    #endif
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: 30)
    if let button = item.button {
      button.image = CloudGlyph.image(); button.imagePosition = .imageOnly
      button.target = self; button.action = #selector(clicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.setAccessibilityLabel(model.text("PI 网盘传输", "Pi Drive Hub transfers"))
    }
    statusItem = item
    refresh()
  }
  func update(_ id: Int64, values: [String: Any]) {
    let snapshot = MenuBarSnapshot(values, windowID: id)
    let before = previous[id] ?? (0, 0, 0)
    downloaded += max(0, snapshot.downloaded - before.0)
    uploaded += max(0, snapshot.uploaded - before.1)
    completed += max(0, snapshot.completed - before.2)
    previous[id] = (snapshot.downloaded, snapshot.uploaded, snapshot.completed)
    snapshots[id] = snapshot; arrivals[id] = Date()
    refresh()
  }
  func remove(_ id: Int64) {
    snapshots.removeValue(forKey: id); arrivals.removeValue(forKey: id); previous.removeValue(forKey: id)
    refresh()
  }
  private func currentSources() -> [MenuBarSnapshot] {
    let now = Date()
    return snapshots.filter { now.timeIntervalSince(arrivals[$0.key] ?? .distantPast) < 3 }.map { $0.value }
  }
  private func sample() {
    let sources = currentSources()
    let now = Date().timeIntervalSince1970 * 1000
    history.append(TransferRatePoint(time: now,
      download: sources.reduce(0) { $0 + $1.downloadRate }, upload: sources.reduce(0) { $0 + $1.uploadRate }))
    history.removeAll { $0.time < now - 60000 }
    if history.count > 61 { history.removeFirst(history.count - 61) }
    refresh()
  }
  private func refresh() {
    let data = MenuBarSnapshot(sources: currentSources(), time: Date().timeIntervalSince1970 * 1000,
      history: history, downloaded: downloaded, uploaded: uploaded, completed: completed)
    model.snapshot = data
    statusItem?.button?.toolTip = model.text("PI 网盘", "Pi Drive Hub") +
      " · ↓ " + transferSize(data.downloadRate, rate: true) + " · ↑ " + transferSize(data.uploadRate, rate: true)
  }
  @objc private func clicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
      showMenu()
    } else { togglePopover() }
  }
  func togglePopover() {
    if popover.isShown { popover.performClose(nil); return }
    guard let button = statusItem?.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    button.highlight(true)
  }
  func popoverDidClose(_ notification: Notification) { statusItem?.button?.highlight(false) }
  private func perform(_ action: String, task: MenuBarTask? = nil) {
    if action == "menu" { showMenu(); return }
    if action == "pauseAll" || action == "resumeAll" { DesktopWindows.shared.broadcast(action); return }
    if action == "pause" || action == "resume" {
      if let task = task { DesktopWindows.shared.send(action, to: task.windowID, task: task) }
      return
    }
    popover.performClose(nil)
    if action == "newWindow" { DesktopWindows.shared.newWindow(); return }
    let id = DesktopWindows.shared.show(task?.windowID)
    if action != "openMain" { DesktopWindows.shared.send(action, to: id, task: task) }
  }
  private func showMenu() {
    popover.performClose(nil)
    guard let item = statusItem, let button = item.button else { return }
    let menu = NSMenu()
    func entry(_ zh: String, _ en: String, _ action: String, key: String = "") {
      let entry = NSMenuItem(title: model.text(zh, en), action: #selector(menuAction(_:)), keyEquivalent: key)
      entry.target = self; entry.representedObject = action; menu.addItem(entry)
    }
    entry("显示主窗口", "Show main window", "openMain")
    entry("新建窗口", "New Window", "newWindow")
    entry("新建网盘标签页", "New Drive Tab", "newTab")
    entry("传输管理…", "Transfers…", "openTransfers")
    if model.snapshot.active + model.snapshot.queued > 0 {
      entry("暂停全部传输", "Pause all transfers", "pauseAll")
    } else if model.snapshot.paused > 0 {
      entry("继续全部传输", "Resume all transfers", "resumeAll")
    }
    menu.addItem(.separator()); entry("退出 PI 网盘", "Quit Pi Drive Hub", "quit", key: "q")
    item.menu = menu; button.performClick(nil); item.menu = nil
  }
  @objc private func menuAction(_ sender: NSMenuItem) {
    if let action = sender.representedObject as? String { perform(action) }
  }
  func destroy() {
    timer?.invalidate(); timer = nil; popover.close()
    if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    statusItem = nil
  }
}
