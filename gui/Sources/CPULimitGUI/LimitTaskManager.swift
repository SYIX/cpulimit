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
                proc.terminationHandler = nil
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
