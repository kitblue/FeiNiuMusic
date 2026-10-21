import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 应用是否正在退出（状态栏菜单「退出」/ Cmd+Q 触发）。
  /// 供 MainFlutterWindow.windowShouldClose 判断：真正退出时放行关闭，
  /// 仅关闭按钮点击时隐藏到托盘。NSApplication 没有公开 isTerminating，
  /// 等播放器清理完成、批准真正退出时才置位。
  static var isTerminating = false
  private var terminationPending = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if AppDelegate.isTerminating { return .terminateNow }
    if terminationPending { return .terminateLater }
    guard let window = mainFlutterWindow as? MainFlutterWindow else {
      return .terminateCancel
    }
    terminationPending = true
    // 先返回 terminateLater，保留 Flutter 引擎处理播放器的异步清理。
    DispatchQueue.main.async { [weak self] in
      window.prepareForExit { success in
        DispatchQueue.main.async {
          self?.terminationPending = false
          AppDelegate.isTerminating = success
          sender.reply(toApplicationShouldTerminate: success)
        }
      }
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭最后一个窗口时不退出应用：应用驻留菜单栏（状态栏），
    // 仅通过状态栏菜单「退出」退出。关闭行为由 MainFlutterWindow
    // windowShouldClose 拦截（关闭按钮隐藏到菜单栏）。
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // flag 也包含桌面歌词等子窗口，不能据此判断主窗口是否需要恢复。
    guard let window = mainFlutterWindow else { return true }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    if #available(macOS 14.0, *) {
      sender.activate()
    } else {
      sender.activate(ignoringOtherApps: true)
    }
    // 已明确恢复主窗口，不再让 AppKit 执行默认的窗口选择逻辑。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
