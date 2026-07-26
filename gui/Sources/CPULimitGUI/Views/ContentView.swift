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
