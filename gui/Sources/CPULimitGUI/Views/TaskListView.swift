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
