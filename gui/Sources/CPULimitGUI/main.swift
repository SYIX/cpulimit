import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let taskManager = LimitTaskManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LimitTaskManager.cpulimitURL() != nil else {
            let alert = NSAlert()
            alert.messageText = "未找到 cpulimit 可执行文件"
            alert.informativeText = "请先在 gui/ 目录运行 make 构建完整的 .app 包。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        statusBarController = StatusBarController(taskManager: taskManager)
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskManager.stopAll()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
