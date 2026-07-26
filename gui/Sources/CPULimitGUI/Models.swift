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
