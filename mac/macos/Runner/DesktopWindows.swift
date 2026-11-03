import AppKit
import FlutterMacOS

/// The SDK's public macOS API has one implicit view per engine. Each window
/// gets an engine; the native menu-bar hub combines their transfer snapshots.
final class DesktopWindows: NSObject, NSWindowDelegate {
  static let shared = DesktopWindows()
  private struct Entry {
    let window: NSWindow
    let controller: FlutterViewController
    var bridge: MenuBarController?
  }
  private var entries: [Int64: Entry] = [:]
  private var nextID: Int64 = 1
  private var lastID: Int64 = 0
  private var closed: Set<Int64> = []
  private var releasing: Set<Int64> = []
  private var closeRevisions: [Int64: Int] = [:]
  private var pendingClose: [Int64: Int] = [:]
  #if DEBUG
  // An offline test can delay the Dart acknowledgement to exercise the race.
  var closeStateRequest: ((Int64, @escaping ([String: Any]?) -> Void) -> Void)?
  #endif
  private(set) var readyTabs: [Int64: Int] = [:]
  var windowIDs: [Int64] { Array(entries.keys).sorted() }
  func markReady(_ id: Int64, tabs: Int) { if entries[id] != nil { readyTabs[id] = tabs } }

  func install(primary: NSWindow, controller: FlutterViewController) {
    entries[0] = Entry(window: primary, controller: controller, bridge: nil)
    configure(primary, id: 0)
    primary.setContentSize(NSSize(width: 1080, height: 720))
    primary.center()
  }
  func register(_ bridge: MenuBarController, id: Int64) { entries[id]?.bridge = bridge }
  private func configure(_ window: NSWindow, id: Int64) {
    window.delegate = self
    window.minSize = NSSize(width: 880, height: 600)
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("pi-window-\(id)")
  }
  func viewID(for window: NSWindow?) -> Int64? {
    guard let window = window else { return nil }
    return entries.first(where: { $0.value.window === window })?.key
  }
  var preferredID: Int64 { viewID(for: NSApp.keyWindow) ?? lastID }
  func send(_ action: String, to id: Int64, task: MenuBarTask? = nil) {
    entries[id]?.bridge?.send(action, task: task)
  }
  func broadcast(_ action: String) {
    for entry in entries.values { entry.bridge?.send(action) }
  }

  @discardableResult func newWindow() -> Int64? {
    let id = nextID; nextID += 1
    let controller = FlutterViewController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    RegisterGeneratedPlugins(registry: controller)
    entries[id] = Entry(window: window, controller: controller, bridge: nil)
    configure(window, id: id)
    // The initializer registers itself in entries. Construct it before taking
    // a mutable dictionary subscript to avoid overlapping Swift accesses.
    let bridge = MenuBarController(messenger: controller.engine.binaryMessenger, windowID: id)
    entries[id]?.bridge = bridge
    window.title = "PI 网盘"
    window.center()
    if let previous = entries[lastID]?.window {
      _ = window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 28, y: previous.frame.maxY - 28))
    }
    lastID = id
    if NSApp.activationPolicy() == .prohibited {
      window.setFrameOrigin(NSPoint(x: -6000, y: 0))
      window.orderFront(nil)
    } else {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return id
  }
  @discardableResult func show(_ id: Int64? = nil) -> Int64 {
    let selected = entries[id ?? preferredID] != nil ? (id ?? preferredID) : 0
    closed.remove(selected)
    pendingClose.removeValue(forKey: selected)
    let window = entries[selected]?.window
    window?.deminiaturize(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return selected
  }
  func close(_ id: Int64) { entries[id]?.window.performClose(nil) }
  func hide(_ id: Int64? = nil) { entries[id ?? preferredID]?.window.orderOut(nil) }
  func setTitle(_ id: Int64, _ title: String) { entries[id]?.window.title = title }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let id = viewID(for: sender) else { return true }
    closed.insert(id)
    let revision = (closeRevisions[id] ?? 0) + 1
    closeRevisions[id] = revision
    pendingClose[id] = revision
    sender.orderOut(nil)
    let confirmed: ([String: Any]?) -> Void = { [weak self] values in
      guard let self = self, self.closed.contains(id),
            self.pendingClose[id] == revision, let values = values else { return }
      TransferMenuBarHub.shared.update(id, values: values)
      self.pendingClose.removeValue(forKey: id)
      self.releaseIfIdle(id)
    }
    #if DEBUG
    if let request = closeStateRequest { request(id, confirmed); return false }
    #endif
    entries[id]?.bridge?.send("windowHidden", completion: { confirmed($0 as? [String: Any]) })
    return false
  }
  func releaseIfIdle(_ id: Int64) {
    guard id != 0, closed.contains(id), pendingClose[id] == nil, !releasing.contains(id),
          let snapshot = TransferMenuBarHub.shared.source(id),
          snapshot.active + snapshot.queued + snapshot.paused == 0 else { return }
    releasing.insert(id)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.releasing.remove(id)
      guard self.closed.contains(id), self.pendingClose[id] == nil, let entry = self.entries[id],
            let latest = TransferMenuBarHub.shared.source(id),
            latest.active + latest.queued + latest.paused == 0 else { return }
      entry.window.delegate = nil
      entry.controller.engine.shutDownEngine()
      entry.window.contentViewController = nil
      entry.window.close()
      self.entries.removeValue(forKey: id)
      self.readyTabs.removeValue(forKey: id)
      self.closed.remove(id)
      self.closeRevisions.removeValue(forKey: id)
      TransferMenuBarHub.shared.remove(id)
      if self.lastID == id { self.lastID = 0 }
    }
  }
  func windowDidBecomeKey(_ notification: Notification) {
    if let id = viewID(for: notification.object as? NSWindow) {
      lastID = id; send("focusWindow", to: id)
    }
  }

  func installCommands(english: Bool) {
    guard let mainMenu = NSApp.mainMenu else { return }
    let existing = mainMenu.items.first(where: { $0.identifier?.rawValue == "pi-file-menu" })
    let fileItem = existing ?? NSMenuItem(title: english ? "File" : "文件", action: nil, keyEquivalent: "")
    fileItem.identifier = NSUserInterfaceItemIdentifier("pi-file-menu")
    if existing == nil { mainMenu.insertItem(fileItem, at: min(1, mainMenu.items.count)) }
    let menu = NSMenu(title: fileItem.title)
    func add(_ zh: String, _ en: String, _ action: String, _ key: String, shift: Bool = false) {
      let item = NSMenuItem(title: english ? en : zh, action: #selector(workspaceCommand(_:)), keyEquivalent: key)
      item.target = self; item.representedObject = action
      item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
      menu.addItem(item)
    }
    add("新建窗口", "New Window", "newWindow", "n")
    add("新建网盘标签页", "New Drive Tab", "newTab", "t")
    menu.addItem(.separator())
    add("关闭标签页", "Close Tab", "closeTab", "w")
    add("关闭窗口", "Close Window", "closeWindow", "w", shift: true)
    fileItem.submenu = menu
  }
  @objc private func workspaceCommand(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? String else { return }
    if action == "newWindow" { newWindow(); return }
    if action == "closeWindow" { close(preferredID); return }
    send(action, to: show())
  }
}
