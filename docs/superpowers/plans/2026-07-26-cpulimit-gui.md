# cpulimit macOS 菜单栏 GUI 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为本仓库的 cpulimit 开发一个 macOS 菜单栏 GUI,支持选进程、设 CPU 百分比限制、多任务管理。

**Architecture:** SwiftUI + AppKit 菜单栏应用(`NSStatusItem` + `NSPopover`,不占 Dock)。每个限制任务对应一个 `cpulimit -z -p <pid> -l <percent>` 子进程;停止任务即终止子进程。工程形式为 Swift Package(可用 Xcode 13 打开,也可 `swift build` 命令行构建),由 `gui/Makefile` 组装成 `.app` 并内嵌 cpulimit 二进制。

**Tech Stack:** Swift 5.5 / SwiftUI 3 / AppKit / Foundation `Process`,SPM,make。

**设计规格:** `docs/superpowers/specs/2026-07-26-cpulimit-gui-design.md`

## Global Constraints

- 目标平台 macOS 12(Darwin 21.6),工具链 Xcode 13.2.1 / Swift 5.5:**禁止使用 macOS 13+ API**(如 `MenuBarExtra`)。
- 不修改 `src/` 下任何 C 代码,不修改根目录及 `src/Makefile`。
- 按项目 CLAUDE.md 约定**不编写自动化测试、不运行 GUI 程序**;每个任务的验证方式 = `swift build` / `make` 构建成功(类型检查),功能验收由用户手动完成。
- cpulimit 调用参数固定为 `-z -p <pid> -l <percent>`(`-z` 必需:目标进程退出时 cpulimit 随之退出,GUI 依赖此行为清理任务行)。
- 只列出/限制当前用户的进程;不做定时轮询(面板打开或手动刷新时取一次进程列表)。
- UI 文案中文,代码标识符英文,注释简洁。
- 所有新文件在 `gui/` 目录下;commit 信息用英文,风格与仓库历史一致(如 `feat: ...`)。

## 文件结构

```
gui/
  Package.swift                      SPM 清单 (executable, macOS 12)
  .gitignore                         忽略 .build/ 与 CPULimitGUI.app
  Info.plist                         LSUIElement=YES 等
  Makefile                           构建 C cpulimit + swift build + 组装 .app
  Sources/CPULimitGUI/
    main.swift                       入口: NSApplication + AppDelegate
    Models.swift                     UserProcess, LimitTask
    ProcessLister.swift              用 ps 枚举当前用户进程
    LimitTaskManager.swift           任务生命周期: 启动/停止/清理 cpulimit 子进程
    StatusBarController.swift        NSStatusItem + NSPopover 承载 SwiftUI
    Views/
      ContentView.swift              面板根视图 (320×420)
      ProcessListView.swift          搜索 + 进程列表 + 百分比 + 限制按钮
      TaskListView.swift             活动任务列表 + 停止按钮
```

---

### Task 1: SPM 脚手架与数据模型

**Files:**
- Create: `gui/Package.swift`
- Create: `gui/.gitignore`
- Create: `gui/Sources/CPULimitGUI/main.swift`(临时最小入口,Task 5 会替换为完整版)
- Create: `gui/Sources/CPULimitGUI/Models.swift`

**Interfaces:**
- Produces: `struct UserProcess { let pid: Int32; let name: String }`(Identifiable, id = pid);`final class LimitTask: ObservableObject, Identifiable`,字段 `id: UUID`、`pid: Int32`、`name: String`、`percent: Int`、`process: Process`、`@Published var state: State`,其中 `enum State { case running; case failed(String) }`。后续所有任务依赖这两个类型。

- [ ] **Step 1: 创建 `gui/Package.swift`**

```swift
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CPULimitGUI",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "CPULimitGUI",
            path: "Sources/CPULimitGUI"
        )
    ]
)
```

- [ ] **Step 2: 创建 `gui/.gitignore`**

```
.build/
CPULimitGUI.app
```

- [ ] **Step 3: 创建临时最小入口 `gui/Sources/CPULimitGUI/main.swift`**

此文件仅为让 executable target 可编译,Task 5 将整体替换:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Task 5 将在此接入 AppDelegate 与 StatusBarController
```

- [ ] **Step 4: 创建 `gui/Sources/CPULimitGUI/Models.swift`**

```swift
import Foundation

// 进程列表条目
struct UserProcess: Identifiable, Hashable {
    let pid: Int32
    let name: String
    var id: Int32 { pid }
}

// 一个限制任务 = 一个 cpulimit 子进程
final class LimitTask: ObservableObject, Identifiable {
    enum State {
        case running
        case failed(String)
    }

    let id = UUID()
    let pid: Int32
    let name: String
    let percent: Int
    let process: Process
    @Published var state: State = .running

    init(pid: Int32, name: String, percent: Int, process: Process) {
        self.pid = pid
        self.name = name
        self.percent = percent
        self.process = process
    }
}
```

- [ ] **Step 5: 构建验证**

Run: `cd gui && swift build`
Expected: `Build complete!`(无 error;首次构建会创建 `.build/`)

- [ ] **Step 6: Commit**

```bash
git add gui/Package.swift gui/.gitignore gui/Sources
git commit -m "feat: scaffold SwiftUI menu bar GUI package with data models"
```

---

### Task 2: ProcessLister — 枚举当前用户进程

**Files:**
- Create: `gui/Sources/CPULimitGUI/ProcessLister.swift`

**Interfaces:**
- Consumes: `UserProcess`(Task 1)
- Produces: `enum ProcessLister { static func listUserProcesses() -> [UserProcess] }` — 返回当前用户全部进程(排除 GUI 自身),按名称排序。

- [ ] **Step 1: 创建 `gui/Sources/CPULimitGUI/ProcessLister.swift`**

```swift
import Foundation

enum ProcessLister {
    // 用 ps 列出当前用户进程 (pid + 命令路径),只在面板打开/手动刷新时调用
    static func listUserProcesses() -> [UserProcess] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-u", String(getuid()), "-o", "pid=,comm="]
        let stdout = Pipe()
        ps.standardOutput = stdout
        ps.standardError = Pipe()
        do {
            try ps.run()
        } catch {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let selfPid = ProcessInfo.processInfo.processIdentifier
        var result: [UserProcess] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]) else { continue }
            if pid == selfPid { continue }
            let command = trimmed[trimmed.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
            let name = (command as NSString).lastPathComponent
            result.append(UserProcess(pid: pid, name: name))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `cd gui && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add gui/Sources/CPULimitGUI/ProcessLister.swift
git commit -m "feat: add process lister using ps for current user"
```

---

### Task 3: LimitTaskManager — cpulimit 子进程生命周期

**Files:**
- Create: `gui/Sources/CPULimitGUI/LimitTaskManager.swift`

**Interfaces:**
- Consumes: `LimitTask`(Task 1)
- Produces:
  - `final class LimitTaskManager: ObservableObject`
  - `@Published private(set) var tasks: [LimitTask]`
  - `static func cpulimitURL() -> URL?` — 从 app bundle Resources 定位 cpulimit
  - `func isLimited(pid: Int32) -> Bool`
  - `func startLimit(pid: Int32, name: String, percent: Int)`
  - `func stopLimit(taskID: UUID)`
  - `func stopAll()`

- [ ] **Step 1: 创建 `gui/Sources/CPULimitGUI/LimitTaskManager.swift`**

要点:cpulimit 收到 SIGTERM 会先向目标进程发 SIGCONT 再退出(见 `src/cpulimit.c` 的 `quit()`),所以 `terminate()` 即可安全停止;`-z` 保证目标进程结束时 cpulimit 自行退出,由 `terminationHandler` 清理任务行;异常退出时读 stderr 显示错误,5 秒后自动移除该行。

```swift
import Foundation

final class LimitTaskManager: ObservableObject {
    @Published private(set) var tasks: [LimitTask] = []

    // .app 包内 Contents/Resources/cpulimit;裸二进制运行时返回 nil
    static func cpulimitURL() -> URL? {
        Bundle.main.url(forResource: "cpulimit", withExtension: nil)
    }

    func isLimited(pid: Int32) -> Bool {
        tasks.contains { $0.pid == pid }
    }

    func startLimit(pid: Int32, name: String, percent: Int) {
        guard !isLimited(pid: pid), let url = Self.cpulimitURL() else { return }

        let process = Process()
        process.executableURL = url
        process.arguments = ["-z", "-p", String(pid), "-l", String(percent)]
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        let task = LimitTask(pid: pid, name: name, percent: percent, process: process)
        process.terminationHandler = { [weak self] proc in
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self = self else { return }
                if proc.terminationStatus != 0 && !message.isEmpty {
                    task.state = .failed(message)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.remove(taskID: task.id)
                    }
                } else {
                    self.remove(taskID: task.id)
                }
            }
        }

        do {
            try process.run()
            tasks.append(task)
        } catch {
            // cpulimit 启动失败,不加入任务列表
        }
    }

    func stopLimit(taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        task.process.terminationHandler = nil
        task.process.terminate()
        remove(taskID: taskID)
    }

    func stopAll() {
        for task in tasks {
            task.process.terminationHandler = nil
            task.process.terminate()
        }
        tasks.removeAll()
    }

    private func remove(taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `cd gui && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add gui/Sources/CPULimitGUI/LimitTaskManager.swift
git commit -m "feat: add limit task manager wrapping cpulimit subprocesses"
```

---

### Task 4: SwiftUI 视图层

**Files:**
- Create: `gui/Sources/CPULimitGUI/Views/ProcessListView.swift`
- Create: `gui/Sources/CPULimitGUI/Views/TaskListView.swift`
- Create: `gui/Sources/CPULimitGUI/Views/ContentView.swift`

**Interfaces:**
- Consumes: `ProcessLister.listUserProcesses()`(Task 2);`LimitTaskManager` 的 `tasks`/`isLimited`/`startLimit`/`stopLimit`(Task 3);`UserProcess`/`LimitTask`(Task 1)
- Produces: `struct ContentView: View`,初始化参数 `taskManager: LimitTaskManager`,固定尺寸 320×420。Task 5 的 StatusBarController 依赖它。

- [ ] **Step 1: 创建 `gui/Sources/CPULimitGUI/Views/ProcessListView.swift`**

```swift
import SwiftUI

// 上半区: 搜索、进程列表、百分比输入、限制按钮
struct ProcessListView: View {
    @ObservedObject var taskManager: LimitTaskManager
    @State private var processes: [UserProcess] = []
    @State private var searchText = ""
    @State private var selection: Int32?
    @State private var percentText = "50"

    private var filtered: [UserProcess] {
        searchText.isEmpty
            ? processes
            : processes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var percent: Int? {
        guard let n = Int(percentText), (1...100).contains(n) else { return nil }
        return n
    }

    private var canLimit: Bool {
        guard let pid = selection, percent != nil else { return false }
        return !taskManager.isLimited(pid: pid)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("搜索进程名", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新进程列表")
            }
            List(filtered, selection: $selection) { proc in
                HStack {
                    Text(proc.name).lineLimit(1)
                    Spacer()
                    Text(String(proc.pid)).foregroundColor(.secondary)
                }
                .tag(proc.pid)
            }
            .frame(height: 180)
            HStack {
                Text("限制到")
                TextField("", text: $percentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 44)
                Text("%")
                Spacer()
                Button("限制", action: limit)
                    .disabled(!canLimit)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        processes = ProcessLister.listUserProcesses()
    }

    private func limit() {
        guard let pid = selection, let percent = percent,
              let proc = processes.first(where: { $0.pid == pid }) else { return }
        taskManager.startLimit(pid: pid, name: proc.name, percent: percent)
    }
}
```

- [ ] **Step 2: 创建 `gui/Sources/CPULimitGUI/Views/TaskListView.swift`**

```swift
import SwiftUI

// 下半区: 活动任务列表
struct TaskListView: View {
    @ObservedObject var taskManager: LimitTaskManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("活动任务").font(.headline)
            if taskManager.tasks.isEmpty {
                Text("暂无限制任务")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(taskManager.tasks) { task in
                            TaskRowView(task: task) {
                                taskManager.stopLimit(taskID: task.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }
}

struct TaskRowView: View {
    @ObservedObject var task: LimitTask
    let onStop: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(task.name) (\(task.pid))").lineLimit(1)
                switch task.state {
                case .running:
                    Text("限制 \(task.percent)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("停止", action: onStop)
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}
```

- [ ] **Step 3: 创建 `gui/Sources/CPULimitGUI/Views/ContentView.swift`**

```swift
import SwiftUI

// 弹出面板根视图
struct ContentView: View {
    @ObservedObject var taskManager: LimitTaskManager

    var body: some View {
        VStack(spacing: 8) {
            ProcessListView(taskManager: taskManager)
            Divider()
            TaskListView(taskManager: taskManager)
            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320, height: 420)
    }
}
```

- [ ] **Step 4: 构建验证**

Run: `cd gui && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add gui/Sources/CPULimitGUI/Views
git commit -m "feat: add SwiftUI panel views for process list and tasks"
```

---

### Task 5: 菜单栏控制器与应用入口

**Files:**
- Create: `gui/Sources/CPULimitGUI/StatusBarController.swift`
- Modify: `gui/Sources/CPULimitGUI/main.swift`(整体替换 Task 1 的临时内容)

**Interfaces:**
- Consumes: `ContentView(taskManager:)`(Task 4);`LimitTaskManager` 的 `cpulimitURL()`/`stopAll()`(Task 3)
- Produces: 完整可编译的应用入口;`final class StatusBarController: NSObject`,`init(taskManager: LimitTaskManager)`。

- [ ] **Step 1: 创建 `gui/Sources/CPULimitGUI/StatusBarController.swift`**

```swift
import AppKit
import SwiftUI

// 菜单栏图标 + 弹出面板 (macOS 12 无 MenuBarExtra, 用 NSStatusItem)
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(taskManager: LimitTaskManager) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()
        popover.behavior = .transient
        popover.contentViewController =
            NSHostingController(rootView: ContentView(taskManager: taskManager))
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speedometer",
                                   accessibilityDescription: "CPULimit")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 2: 整体替换 `gui/Sources/CPULimitGUI/main.swift`**

启动时校验内嵌 cpulimit 存在(规格要求);退出时终止全部子进程,目标进程自动恢复:

```swift
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
```

- [ ] **Step 3: 构建验证**

Run: `cd gui && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add gui/Sources/CPULimitGUI/StatusBarController.swift gui/Sources/CPULimitGUI/main.swift
git commit -m "feat: add status bar controller and app entry point"
```

---

### Task 6: Info.plist 与 .app 打包

**Files:**
- Create: `gui/Info.plist`
- Create: `gui/Makefile`

**Interfaces:**
- Consumes: Task 1-5 产出的 Swift 源码;`src/Makefile` 产出的 `src/cpulimit`
- Produces: `gui/CPULimitGUI.app`(含 `Contents/MacOS/CPULimitGUI`、`Contents/Resources/cpulimit`、`Contents/Info.plist`),ad-hoc 签名。

- [ ] **Step 1: 创建 `gui/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>CPULimitGUI</string>
	<key>CFBundleIdentifier</key>
	<string>local.cpulimit.gui</string>
	<key>CFBundleExecutable</key>
	<string>CPULimitGUI</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: 创建 `gui/Makefile`**

```make
APP = CPULimitGUI.app
BINARY = .build/release/CPULimitGUI
CPULIMIT = ../src/cpulimit
SOURCES = $(wildcard Sources/CPULimitGUI/*.swift Sources/CPULimitGUI/Views/*.swift)

.PHONY: all app clean

all: app

$(CPULIMIT):
	$(MAKE) -C ../src

$(BINARY): $(SOURCES) Package.swift
	swift build -c release

app: $(BINARY) $(CPULIMIT)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp $(CPULIMIT) $(APP)/Contents/Resources/
	codesign --force -s - $(APP)
	@echo "构建完成: $(APP)"

clean:
	rm -rf .build $(APP)
```

- [ ] **Step 3: 构建验证**

Run: `make -C gui`
Expected: 依次完成 C 编译(如未编译过)、`swift build -c release`、bundle 组装与 ad-hoc 签名,输出 `构建完成: CPULimitGUI.app`。

Run: `ls gui/CPULimitGUI.app/Contents/MacOS gui/CPULimitGUI.app/Contents/Resources`
Expected: `MacOS/` 下有 `CPULimitGUI`,`Resources/` 下有 `cpulimit`。

- [ ] **Step 4: Commit**

```bash
git add gui/Info.plist gui/Makefile
git commit -m "feat: add app bundle packaging with embedded cpulimit"
```

---

## 手动验收(由用户执行,不属于任务步骤)

1. `open gui/CPULimitGUI.app`,菜单栏出现 speedometer 图标。
2. 终端跑 `yes > /dev/null`,面板中搜索 `yes`,限制到 50%,活动监视器确认 CPU 占用降至约 50%。
3. 点"停止",`yes` 恢复满速。
4. 再次限制后 `kill` 掉 `yes`,任务行自动消失。
5. 退出 GUI(面板"退出"按钮),`pgrep cpulimit` 无残留,目标进程不处于 stopped 状态。
