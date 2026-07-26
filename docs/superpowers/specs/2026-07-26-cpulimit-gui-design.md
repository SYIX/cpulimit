# CPULimit 菜单栏 GUI 设计

> 日期: 2026-07-26
> 状态: 已确认
> 平台: macOS 12 (Darwin 21.6), Xcode 13.2.1, SwiftUI 3 + AppKit

## 背景与目标

基于本仓库的 cpulimit(C 语言命令行工具,通过周期性 SIGSTOP/SIGCONT 限制目标进程 CPU 占用),开发一个 macOS 菜单栏图形界面,方便个人日常使用:选择进程、设置 CPU 百分比限制、管理多个限制任务。

**使用范围**:仅本机自用;仅限制当前用户自己的进程(无需 root 提权)。

**非目标**(明确排除):
- CPU 占用曲线/实时监控
- 自动规则(按进程名自动应用限制)
- 限制 root 或其他用户的进程
- 进程列表定时轮询刷新
- 跨平台支持

## 方案选型

- **界面框架**:SwiftUI 原生应用。三个候选(SwiftUI / Python+tkinter / Tauri·Electron)中资源占用最小(约 20-40 MB 内存,空闲 CPU 接近 0),且最适合菜单栏常驻形态。
- **与 cpulimit 集成方式**:调用编译好的 `cpulimit` 二进制,不修改 C 代码、不用 Swift 重写限速逻辑。每个限制任务对应一个 `cpulimit -p <pid> -l <percent>` 子进程,停止任务即终止该子进程。任务间天然隔离,cpulimit 自身退出可被 GUI 感知。
- **菜单栏实现**:Xcode 13.2.1 / macOS 12 无 `MenuBarExtra`(需 macOS 13),改用 AppKit `NSStatusItem` + `NSPopover` 承载 SwiftUI 视图。应用设 `LSUIElement = YES`,不占 Dock。

## 架构

```
┌─ 菜单栏图标 (NSStatusItem)
│    └─ NSPopover
│         └─ SwiftUI ContentView
│              ├─ ProcessListView   进程列表 + 搜索 + 百分比输入
│              └─ TaskListView      活动任务列表
│
├─ ProcessLister      枚举当前用户进程 (调用 ps)
├─ LimitTaskManager   任务数组; 启动/终止 cpulimit 子进程 (Foundation Process)
└─ Resources/cpulimit 由本仓库 Makefile 编译并内嵌的二进制
```

### 组件职责

| 组件 | 职责 | 依赖 |
|------|------|------|
| `StatusBarController` | 创建 NSStatusItem、管理 NSPopover 显隐 | AppKit |
| `ProcessLister` | 返回当前用户进程列表 (pid、名称);面板打开或手动刷新时调用一次 | `ps -u <uid> -o pid=,comm=` 子进程 |
| `LimitTaskManager` | 维护 `[LimitTask]`;启动 cpulimit 子进程、terminationHandler 清理、退出时全部终止 | Foundation `Process` |
| `LimitTask` | 单个任务模型:目标 pid、进程名、百分比、Process 句柄、状态 | — |
| SwiftUI 视图层 | 展示与交互,不含业务逻辑 | 以上组件 (ObservableObject) |

## 界面

弹出面板约 320×420,上下两区:

- **上半区(发起限制)**:搜索框按进程名过滤;进程列表(名称 + PID),单选;百分比输入(1-100,默认 50);"限制"按钮;手动刷新按钮。
- **下半区(活动任务)**:每行显示进程名、PID、限制百分比、状态,行尾"停止"按钮。cpulimit 子进程退出(如目标进程已结束)时,该行自动移除。

无任务且面板关闭时,应用完全空闲(无定时器、无轮询),保证零后台占用。

## 数据流

1. 用户点菜单栏图标 → 面板打开 → `ProcessLister` 刷新一次进程列表。
2. 用户选进程、输百分比、点"限制" → `LimitTaskManager` 启动 `cpulimit -p <pid> -l <n>` 子进程,任务入列。
3. 子进程 `terminationHandler` 触发(目标进程结束、被杀或出错)→ 主线程移除对应任务行。
4. 用户点"停止" → terminate 该 cpulimit 子进程(cpulimit 的信号处理会向目标进程发 SIGCONT 恢复运行)。
5. 应用退出 → 终止所有 cpulimit 子进程,目标进程全部恢复。

## 错误处理

- 目标进程无权限或不存在:cpulimit 立即退出并输出错误;GUI 捕获 stderr,在任务行位置显示错误信息后移除。
- 重复限制:同一 PID 已有活动任务时,"限制"按钮禁用并提示。
- 百分比输入:限定 1-100 整数,非法输入禁用按钮。
- 内嵌二进制缺失:启动时校验 Resources 中 cpulimit 存在且可执行,否则弹窗提示并退出。

## 构建与产物

- 仓库根目录 `make` 产出 `src/cpulimit`,复制进 app bundle 的 Resources。
- Xcode 工程放在仓库 `gui/` 目录下,不影响原有 C 代码与 Makefile。
- 本地自用,不做代码签名分发处理(本机 ad-hoc 签名即可)。

## 测试策略

按项目约定(CLAUDE.md:不需要编写测试),不写自动化测试;以手动验收为准:

1. 启动一个耗 CPU 的测试进程(如 `yes > /dev/null`),GUI 中限制到 50%,活动监视器确认占用下降。
2. 点"停止"后进程恢复满速。
3. 杀掉目标进程,任务行自动消失。
4. 退出 GUI,确认无残留 cpulimit 进程、目标进程未处于 stopped 状态。
