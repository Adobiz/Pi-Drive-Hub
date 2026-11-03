import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var menuBarController: MenuBarController?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DesktopWindows.shared.install(primary: self, controller: flutterViewController)
    menuBarController = MenuBarController(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
