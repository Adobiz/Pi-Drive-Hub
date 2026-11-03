// Offline native integration harness. Compile into a disposable copy of the
// built app with -D DEBUG; it never captures the user's screen or logs in.
import AppKit
import FlutterMacOS
func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {}

@main enum WorkspaceSmoke {
  static var bridge: MenuBarController?
  static var second: Int64?
  static var third: Int64?
  static var confirmClose: (([String: Any]?) -> Void)?
  static func check(_ condition: Bool, _ message: String) {
    if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
  }
  static func main() {
    setenv("PI_WORKSPACE_SMOKE", "1", 1)
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let delegate = FlutterAppDelegate()
    app.delegate = delegate
    let controller = FlutterViewController()
    let primary = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    primary.contentViewController = controller
    delegate.mainFlutterWindow = primary
    DesktopWindows.shared.install(primary: primary, controller: controller)
    bridge = MenuBarController(messenger: controller.engine.binaryMessenger)
    primary.setFrameOrigin(NSPoint(x: -6000, y: 0))
    primary.orderFront(nil)
    app.finishLaunching()
    let hub = TransferMenuBarHub.shared
    let fixture: [String: Any] = ["downloadRate": 2048, "uploadRate": 1024,
      "downloaded": 4096, "uploaded": 1024, "active": 1,
      "tasks": [["id": "same", "kind": "download", "name": "sample", "status": "downloading"]]]
    hub.update(101, values: fixture); hub.update(102, values: fixture)
    check(hub.snapshot.downloadRate == 4096, "menu bar sums rates across engines")
    check(Set(hub.snapshot.tasks.map { $0.id }).count == 2, "task IDs include their owner window")
    hub.remove(101); hub.remove(102)
    check(hub.snapshot.downloaded == 8192, "session totals survive an engine closing")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      second = DesktopWindows.shared.newWindow()
      third = DesktopWindows.shared.newWindow()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      let windows = DesktopWindows.shared
      check(windows.windowIDs.count == 3, "three independent native Flutter windows render")
      check(windows.readyTabs.count == 3, "all three Dart view trees rendered")
      check(Set(windows.windowIDs).count == 3, "native window IDs are unique")
      windows.send("newTab", to: second!)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      let windows = DesktopWindows.shared
      check(windows.readyTabs[second!] == 2, "new-tab command targets only the second window")
      check(windows.readyTabs[third!] == 1, "third window keeps its independent tab state")
      hub.update(second!, values: [:])
      windows.closeStateRequest = { id, reply in
        check(id == second!, "close acknowledgement targets the correct engine")
        confirmClose = reply
      }
      windows.close(second!)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.25) {
      let windows = DesktopWindows.shared
      check(windows.windowIDs.contains(second!), "stale idle snapshot cannot close an engine before Dart confirms")
      windows.releaseIfIdle(second!)
      confirmClose?(["paused": 1])
      check(windows.windowIDs.contains(second!), "fresh busy acknowledgement retains the transfer engine")
      windows.show(second!)
      confirmClose?([:])
      check(hub.source(second!)?.paused == 1, "reopening a window ignores its earlier close acknowledgement")
      windows.closeStateRequest = nil
      windows.close(second!)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
      let windows = DesktopWindows.shared
      check(windows.windowIDs.count == 2, "secondary close releases its native view")
      check(windows.readyTabs.count == 2, "closed view readiness is removed")
      windows.show(third!)
      print("WORKSPACE_SMOKE_OK")
      exit(0)
    }
    withExtendedLifetime(delegate) { app.run() }
  }
}
