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
