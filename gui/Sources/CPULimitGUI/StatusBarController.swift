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
