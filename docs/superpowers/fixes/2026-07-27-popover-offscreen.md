# 修复:菜单栏弹出面板上半部分超出屏幕

- 日期:2026-07-27
- 状态:已修改代码,待重新打包后人工验收

## 问题

点击菜单栏常驻图标后,弹出面板(NSPopover)的上半部分伸出屏幕顶端,无法看到和操作。

## 根因

`StatusBarController.swift` 中 popover 以 `preferredEdge: .minY` 锚定到状态栏按钮。
`NSStatusBarButton`(继承 `NSButton`)使用 flipped 坐标系,`minY` 边实际是按钮的
**上边缘**,popover 因此尝试显示在菜单栏上方(屏幕外)。macOS 12(实测 12.7.6)
在此场景下不会自动翻转回屏内,导致面板上半部分越界。

## 修改

文件:`gui/Sources/CPULimitGUI/StatusBarController.swift`

1. `preferredEdge` 由 `.minY` 改为 `.maxY`(flipped 坐标下的视觉下边缘),
   面板锚定到菜单栏图标正下方。
2. 新增 `popover.contentSize = NSSize(width: 320, height: 420)`,与
   `ContentView` 的固定 frame 一致,规避 macOS 12 上 `NSHostingController`
   首帧尺寸上报延迟造成的错位。

## 验证

```bash
cd gui && make
```

重新打开 `CPULimitGUI.app`(先退出旧实例),点击菜单栏图标,确认:

- 面板完整显示在菜单栏下方,带指向图标的箭头;
- 主屏与外接显示器均不越界。

## 备选方案(若仍复现)

显示 popover 后取 `popover.contentViewController?.view.window`,将其 frame
clamp 进 `NSScreen.visibleFrame`。当前未启用。
